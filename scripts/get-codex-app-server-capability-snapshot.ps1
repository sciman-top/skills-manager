[CmdletBinding()]
param(
    [string]$Cwd = (Get-Location).Path,
    [string]$OutputPath = '',
    [ValidateRange(5, 120)][int]$TimeoutSeconds = 30,
    [switch]$ForceRefresh
)

$ErrorActionPreference = 'Stop'

function Add-Capability([Collections.Generic.List[object]]$List, [Collections.Generic.HashSet[string]]$Seen, [string]$Kind, [string]$Name, [string]$Description, [string]$Availability, [string]$SideEffect, [hashtable]$Evidence) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $key = '{0}|{1}' -f $Kind, $Name
    if (-not $Seen.Add($key)) { return }
    $List.Add([pscustomobject]@{
        kind = $Kind; name = $Name; description = $Description
        availability = $Availability; side_effect = $SideEffect; evidence = $Evidence
    }) | Out-Null
}

$codexJs = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\bin\codex.js'
$bootstrapArguments = [Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $codexJs -PathType Leaf) {
    $nodeCommand = @(Get-Command node -All -ErrorAction Stop | Where-Object { $_.CommandType -eq 'Application' -and [IO.Path]::GetExtension($_.Source) -eq '.exe' } | Select-Object -First 1)
    if ($nodeCommand.Count -eq 0) { throw 'node.exe is required to launch the installed Codex CLI.' }
    $codex = $nodeCommand[0].Source
    $bootstrapArguments.Add($codexJs)
}
else {
    $codexCommand = @(Get-Command codex -All -ErrorAction Stop | Where-Object { $_.CommandType -eq 'Application' -and [IO.Path]::GetExtension($_.Source) -eq '.exe' } | Select-Object -First 1)
    if ($codexCommand.Count -eq 0) { throw 'A native codex.exe is required for the stdio snapshot adapter.' }
    $codex = $codexCommand[0].Source
}
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $codex
$bootstrapArguments | ForEach-Object { $psi.ArgumentList.Add($_) }
$psi.ArgumentList.Add('app-server')
$psi.ArgumentList.Add('--stdio')
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$process = [Diagnostics.Process]::new()
$process.StartInfo = $psi
if (-not $process.Start()) { throw 'Failed to start codex app-server.' }

$requests = @(
    [ordered]@{ method = 'initialize'; id = 0; params = [ordered]@{ clientInfo = [ordered]@{ name = 'skills_manager_snapshot'; title = 'skills-manager capability snapshot'; version = '1.0.0' }; capabilities = [ordered]@{ optOutNotificationMethods = @('skills/changed', 'app/list/updated') } } },
    [ordered]@{ method = 'initialized'; params = @{} },
    [ordered]@{ method = 'skills/list'; id = 1; params = [ordered]@{ cwds = @([IO.Path]::GetFullPath($Cwd)); forceReload = [bool]$ForceRefresh } },
    [ordered]@{ method = 'app/installed'; id = 2; params = [ordered]@{ forceRefresh = [bool]$ForceRefresh } },
    [ordered]@{ method = 'app/list'; id = 3; params = [ordered]@{ cursor = $null; limit = 100; forceRefetch = [bool]$ForceRefresh } },
    [ordered]@{ method = 'mcpServerStatus/list'; id = 4; params = [ordered]@{ cursor = $null; limit = 100; detail = 'toolsAndAuthOnly' } }
)

foreach ($request in $requests) {
    $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 10 -Compress))
}
$process.StandardInput.Flush()

$responses = @{}
$deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
try {
    while ($responses.Count -lt 5 -and [DateTimeOffset]::UtcNow -lt $deadline) {
        $remaining = [Math]::Max(1, [int]($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
        $readTask = $process.StandardOutput.ReadLineAsync()
        if (-not $readTask.Wait($remaining)) { break }
        $line = $readTask.Result
        if ($null -eq $line) { break }
        try { $message = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($message.PSObject.Properties.Match('id').Count -gt 0 -and $null -ne $message.id) { $responses[[int]$message.id] = $message }
    }
}
finally {
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(2000)) { $process.Kill($true) }
    $process.Dispose()
}

$sourceErrors = [Collections.Generic.List[object]]::new()
foreach ($id in 0..4) {
    if (-not $responses.ContainsKey($id)) { throw ('Codex app-server did not return response id {0} before timeout.' -f $id) }
    if ($responses[$id].PSObject.Properties.Match('error').Count -gt 0 -and $null -ne $responses[$id].error) {
        $message = ([string]$responses[$id].error.message -replace '\s+', ' ').Trim()
        if ($message.Length -gt 240) { $message = $message.Substring(0, 240) }
        if ($id -in @(0, 1)) { throw ('Codex app-server request {0} failed: {1}' -f $id, $message) }
        $sourceErrors.Add([pscustomobject]@{ request_id = $id; message = $message }) | Out-Null
    }
}

$capabilities = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($scope in @($responses[1].result.data)) {
    foreach ($skill in @($scope.skills)) {
        $availability = if ([bool]$skill.enabled) { 'available' } else { 'disabled' }
        Add-Capability $capabilities $seen 'skill' ([string]$skill.name) ([string]$skill.description) $availability 'read_only' @{ source = 'skills/list'; cwd = [string]$scope.cwd; enabled = [bool]$skill.enabled }
    }
}

$installedApps = @{}
if ($null -ne $responses[2].result) { foreach ($app in @($responses[2].result.apps)) { $installedApps[[string]$app.id] = $app } }
$listedAppIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($app in $(if ($null -ne $responses[3].result) { @($responses[3].result.data) } else { @() })) {
    $listedAppIds.Add([string]$app.id) | Out-Null
    $installed = if ($installedApps.ContainsKey([string]$app.id)) { $installedApps[[string]$app.id] } else { $null }
    $callable = $null -ne $installed -and [bool]$installed.callable
    $availability = if (-not [bool]$app.isAccessible) { 'inaccessible' } elseif (-not [bool]$app.isEnabled) { 'disabled' } elseif ($callable) { 'available' } else { 'not_callable' }
    Add-Capability $capabilities $seen 'app' ([string]$app.id) ([string]$app.description) $availability 'unknown' @{ source = 'app/list+app/installed'; accessible = [bool]$app.isAccessible; enabled = [bool]$app.isEnabled; callable = $callable }
}
foreach ($appId in @($installedApps.Keys | Where-Object { -not $listedAppIds.Contains([string]$_) })) {
    $installed = $installedApps[$appId]
    $availability = if ([bool]$installed.callable) { 'available' } elseif ([bool]$installed.enabled) { 'not_callable' } else { 'disabled' }
    Add-Capability $capabilities $seen 'app' ([string]$appId) ([string]$installed.runtimeName) $availability 'unknown' @{ source = 'app/installed'; enabled = [bool]$installed.enabled; callable = [bool]$installed.callable }
}

$mcpRows = if ($null -ne $responses[4].result -and $responses[4].result.PSObject.Properties.Match('data').Count -gt 0) { @($responses[4].result.data) } elseif ($null -ne $responses[4].result -and $responses[4].result.PSObject.Properties.Match('servers').Count -gt 0) { @($responses[4].result.servers) } else { @() }
foreach ($server in $mcpRows) {
    $name = if ($server.PSObject.Properties.Match('name').Count -gt 0) { [string]$server.name } else { [string]$server.serverName }
    $auth = if ($server.PSObject.Properties.Match('authStatus').Count -gt 0) { [string]$server.authStatus } else { '' }
    $status = if ($server.PSObject.Properties.Match('status').Count -gt 0) { [string]$server.status } else { '' }
    $availability = if ($auth -match 'expired|required|unauth') { 'needs_auth' } elseif ($status -match 'failed|disabled|error') { 'unavailable' } else { 'available' }
    Add-Capability $capabilities $seen 'mcp' $name ('Codex MCP server {0}' -f $name) $availability 'unknown' @{ source = 'mcpServerStatus/list'; status = $status; auth_status = $auth; tool_count = @($server.tools).Count }
}

$snapshot = [ordered]@{
    schema_version = 2
    captured_at = [DateTimeOffset]::UtcNow.ToString('o')
    source = 'codex-app-server'
    cwd = [IO.Path]::GetFullPath($Cwd)
    read_only = $true
    status = if ($sourceErrors.Count -eq 0) { 'complete' } elseif (@($sourceErrors | Where-Object request_id -ne 3).Count -eq 0) { 'runtime_complete_catalog_partial' } else { 'partial' }
    coverage = [ordered]@{
        skills = ($null -ne $responses[1].result)
        installed_apps = ($null -ne $responses[2].result)
        app_catalog = ($null -ne $responses[3].result)
        mcp_servers = ($null -ne $responses[4].result)
    }
    source_errors = @($sourceErrors)
    capabilities = @($capabilities)
}
$json = $snapshot | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path $fullOutputPath -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($fullOutputPath, $json, [Text.UTF8Encoding]::new($false))
}
Write-Output $json
