[CmdletBinding()]
param(
    [string]$Cwd = (Get-Location).Path,
    [string]$OutputPath = '',
    [ValidateRange(5, 120)][int]$TimeoutSeconds = 30,
    [switch]$ForceRefresh
)

$ErrorActionPreference = 'Stop'

function Add-Capability([Collections.Generic.List[object]]$List, [Collections.Generic.HashSet[string]]$Seen, [string]$Kind, [string]$Name, [string]$Description, [string]$Availability, [string]$SideEffect, [hashtable]$Evidence, [string]$DisplayName = '', [string]$RuntimeName = '', [object[]]$Aliases = @(), $Callable = $null, $Authenticated = $null, [object[]]$Tools = @(), [string]$Path = '', [string]$SourceRoot = '') {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $key = '{0}|{1}' -f $Kind, $Name
    if (-not $Seen.Add($key)) { return }
    $List.Add([pscustomobject]@{
        kind = $Kind; name = $Name; description = $Description
        display_name = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $Name } else { $DisplayName }
        runtime_name = $RuntimeName; aliases = @($Aliases | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        availability = $Availability; callable = $Callable; authenticated = $Authenticated
        path = $Path; source_root = $SourceRoot
        side_effect = $SideEffect; approval = if ($SideEffect -in @('read_only', 'external_read')) { 'none' } else { 'unknown' }
        tools = @($Tools | Where-Object { $null -ne $_ }); evidence = $Evidence
    }) | Out-Null
}

function Convert-ToolDescriptor($Tool, [string]$FallbackName, [bool]$External, [bool]$ProtocolTool = $false) {
    $name = if ($Tool.PSObject.Properties.Match('name').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Tool.name)) { [string]$Tool.name } else { $FallbackName }
    $title = if ($Tool.PSObject.Properties.Match('title').Count -gt 0) { [string]$Tool.title } else { '' }
    $description = if ($Tool.PSObject.Properties.Match('description').Count -gt 0) { [string]$Tool.description } else { '' }
    $annotations = if ($Tool.PSObject.Properties.Match('annotations').Count -gt 0) { $Tool.annotations } else { $null }
    $hasReadOnlyHint = $null -ne $annotations -and $annotations.PSObject.Properties.Match('readOnlyHint').Count -gt 0
    $hasDestructiveHint = $null -ne $annotations -and $annotations.PSObject.Properties.Match('destructiveHint').Count -gt 0
    $hasOpenWorldHint = $null -ne $annotations -and $annotations.PSObject.Properties.Match('openWorldHint').Count -gt 0
    $readOnlyHint = if ($hasReadOnlyHint) { [bool]$annotations.readOnlyHint } elseif ($ProtocolTool) { $false } else { $null }
    $destructiveHint = if ($hasDestructiveHint) { [bool]$annotations.destructiveHint } elseif ($ProtocolTool) { $true } else { $null }
    $openWorldHint = if ($hasOpenWorldHint) { [bool]$annotations.openWorldHint } elseif ($ProtocolTool) { $true } else { $null }
    $text = ('{0} {1} {2}' -f $name, $title, $description).ToLowerInvariant()
    $sideEffect = if ($readOnlyHint -eq $true) {
        if ($External) { 'external_read' } else { 'read_only' }
    }
    elseif ($destructiveHint -eq $true) { 'destructive' }
    elseif ($hasReadOnlyHint -or $ProtocolTool) { 'controlled_write' }
    elseif ($text -match '\b(delete|remove|destroy|drop|purge)\b') { 'destructive' }
    elseif ($text -match '\b(create|update|write|send|post|publish|refund|charge|modify|edit|upload|archive|label)\b') { 'controlled_write' }
    elseif ($text -match '\b(read|search|list|get|fetch|find|query|summari[sz]e|inspect|lookup)\b') { if ($External) { 'external_read' } else { 'read_only' } }
    else { 'unknown' }
    $classification = if ($hasReadOnlyHint -or $hasDestructiveHint -or $hasOpenWorldHint) { 'protocol_annotation' } elseif ($ProtocolTool) { 'protocol_default' } else { 'conservative_metadata' }
    [pscustomobject]@{
        name = $name; title = $title; description = $description; side_effect = $sideEffect
        authenticated = $null; approval = if ($sideEffect -in @('read_only', 'external_read')) { 'none' } elseif ($sideEffect -in @('controlled_write', 'destructive')) { 'required' } else { 'unknown' }
        classification = $classification; read_only_hint = $readOnlyHint; destructive_hint = $destructiveHint; open_world_hint = $openWorldHint
        evidence = [ordered]@{ read_only_hint = $readOnlyHint; destructive_hint = $destructiveHint; open_world_hint = $openWorldHint; classification = $classification }
    }
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

$responses = @{}
try {
    foreach ($request in $requests) { $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 10 -Compress)) }
    $process.StandardInput.Flush()
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($responses.Count -lt 5 -and [DateTimeOffset]::UtcNow -lt $deadline) {
        $remaining = [Math]::Max(1, [int]($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
        $readTask = $process.StandardOutput.ReadLineAsync()
        if (-not $readTask.Wait($remaining)) { break }
        $line = $readTask.Result
        if ($null -eq $line) { break }
        try { $message = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($message.PSObject.Properties.Match('id').Count -gt 0 -and $null -ne $message.id) { $responses[[int]$message.id] = $message }
    }
    $appIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($responses.ContainsKey(2) -and $null -ne $responses[2].result) { foreach ($app in @($responses[2].result.apps)) { $appIds.Add([string]$app.id) | Out-Null } }
    if ($responses.ContainsKey(3) -and $null -ne $responses[3].result) { foreach ($app in @($responses[3].result.data)) { $appIds.Add([string]$app.id) | Out-Null } }
    if ($appIds.Count -gt 0) {
        $process.StandardInput.WriteLine(([ordered]@{ method = 'app/read'; id = 5; params = [ordered]@{ appIds = @($appIds); includeTools = $true } } | ConvertTo-Json -Depth 8 -Compress))
        $process.StandardInput.Flush()
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $responses.ContainsKey(5) -and [DateTimeOffset]::UtcNow -lt $deadline) {
            $remaining = [Math]::Max(1, [int]($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
            $readTask = $process.StandardOutput.ReadLineAsync()
            if (-not $readTask.Wait($remaining)) { break }
            $line = $readTask.Result
            if ($null -eq $line) { break }
            try { $message = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($message.PSObject.Properties.Match('id').Count -gt 0 -and $null -ne $message.id) { $responses[[int]$message.id] = $message }
        }
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
if (-not $responses.ContainsKey(5)) { $sourceErrors.Add([pscustomobject]@{ request_id = 5; message = 'app/read display metadata was not returned before timeout.' }) | Out-Null }
elseif ($responses[5].PSObject.Properties.Match('error').Count -gt 0 -and $null -ne $responses[5].error) {
    $message = (([string]$responses[5].error.message -replace '\s+', ' ').Trim())
    if ($message.Length -gt 240) { $message = $message.Substring(0, 240) }
    $sourceErrors.Add([pscustomobject]@{ request_id = 5; message = $message }) | Out-Null
}

$capabilities = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($scope in @($responses[1].result.data)) {
    foreach ($skill in @($scope.skills)) {
        $availability = if ([bool]$skill.enabled) { 'available' } else { 'cold_load' }
        $skillPath = [string]$skill.path
        $sourceRoot = if ([string]::IsNullOrWhiteSpace($skillPath)) { '' } else { Split-Path (Split-Path $skillPath -Parent) -Parent }
        $displayName = if ($null -ne $skill.interface -and $skill.interface.PSObject.Properties.Match('displayName').Count -gt 0) { [string]$skill.interface.displayName } else { [string]$skill.name }
        Add-Capability $capabilities $seen 'skill' ([string]$skill.name) ([string]$skill.description) $availability 'read_only' @{ source = 'skills/list'; cwd = [string]$scope.cwd; enabled = [bool]$skill.enabled; scope = [string]$skill.scope } $displayName '' @() ([bool]$skill.enabled) $true @() $skillPath $sourceRoot
    }
}

$installedApps = @{}
if ($null -ne $responses[2].result) { foreach ($app in @($responses[2].result.apps)) { $installedApps[[string]$app.id] = $app } }
$appMetadata = @{}
if ($responses.ContainsKey(5) -and $null -ne $responses[5].result) { foreach ($app in @($responses[5].result.apps)) { $appMetadata[[string]$app.id] = $app } }
$listedAppIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($app in $(if ($null -ne $responses[3].result) { @($responses[3].result.data) } else { @() })) {
    $listedAppIds.Add([string]$app.id) | Out-Null
    $installed = if ($installedApps.ContainsKey([string]$app.id)) { $installedApps[[string]$app.id] } else { $null }
    $callable = $null -ne $installed -and [bool]$installed.callable
    $availability = if (-not [bool]$app.isAccessible) { 'inaccessible' } elseif (-not [bool]$app.isEnabled) { 'disabled' } elseif ($callable) { 'available' } else { 'not_callable' }
    $metadata = if ($appMetadata.ContainsKey([string]$app.id)) { $appMetadata[[string]$app.id] } else { $null }
    $displayName = if ($null -ne $metadata) { [string]$metadata.name } else { [string]$app.name }
    $runtimeName = if ($null -ne $installed) { [string]$installed.runtimeName } else { '' }
    $aliases = @($app.name, $runtimeName) + $(if ($null -ne $metadata) { @($metadata.pluginDisplayNames) } else { @($app.pluginDisplayNames) })
    $tools = if ($null -eq $metadata) { @() } else { @($metadata.toolSummaries | ForEach-Object { Convert-ToolDescriptor $_ ([string]$_.name) $true }) }
    foreach ($tool in $tools) { $tool.authenticated = $callable }
    Add-Capability $capabilities $seen 'app' ([string]$app.id) $(if ($null -ne $metadata -and -not [string]::IsNullOrWhiteSpace([string]$metadata.description)) { [string]$metadata.description } else { [string]$app.description }) $availability 'unknown' @{ source = 'app/list+app/installed+app/read'; accessible = [bool]$app.isAccessible; enabled = [bool]$app.isEnabled; callable = $callable } $displayName $runtimeName $aliases $callable $(if ($callable) { $true } else { $null }) $tools
}
foreach ($appId in @($installedApps.Keys | Where-Object { -not $listedAppIds.Contains([string]$_) })) {
    $installed = $installedApps[$appId]
    $availability = if ([bool]$installed.callable) { 'available' } elseif ([bool]$installed.enabled) { 'not_callable' } else { 'disabled' }
    $metadata = if ($appMetadata.ContainsKey([string]$appId)) { $appMetadata[[string]$appId] } else { $null }
    $displayName = if ($null -ne $metadata) { [string]$metadata.name } else { [string]$installed.runtimeName }
    $aliases = @([string]$installed.runtimeName) + $(if ($null -ne $metadata) { @($metadata.pluginDisplayNames) } else { @() })
    $tools = if ($null -eq $metadata) { @() } else { @($metadata.toolSummaries | ForEach-Object { Convert-ToolDescriptor $_ ([string]$_.name) $true }) }
    foreach ($tool in $tools) { $tool.authenticated = [bool]$installed.callable }
    Add-Capability $capabilities $seen 'app' ([string]$appId) $(if ($null -ne $metadata) { [string]$metadata.description } else { [string]$installed.runtimeName }) $availability 'unknown' @{ source = 'app/installed+app/read'; enabled = [bool]$installed.enabled; callable = [bool]$installed.callable } $displayName ([string]$installed.runtimeName) $aliases ([bool]$installed.callable) $(if ([bool]$installed.callable) { $true } else { $null }) $tools
}

$mcpRows = if ($null -ne $responses[4].result -and $responses[4].result.PSObject.Properties.Match('data').Count -gt 0) { @($responses[4].result.data) } elseif ($null -ne $responses[4].result -and $responses[4].result.PSObject.Properties.Match('servers').Count -gt 0) { @($responses[4].result.servers) } else { @() }
$appToolsByNamespace = @{}
foreach ($server in $mcpRows) {
    $name = if ($server.PSObject.Properties.Match('name').Count -gt 0) { [string]$server.name } else { [string]$server.serverName }
    $auth = if ($server.PSObject.Properties.Match('authStatus').Count -gt 0) { [string]$server.authStatus } else { '' }
    $status = if ($server.PSObject.Properties.Match('status').Count -gt 0) { [string]$server.status } else { '' }
    $availability = if ($auth -match 'expired|required|unauth') { 'needs_auth' } elseif ($status -match 'failed|disabled|error') { 'unavailable' } else { 'available' }
    $authenticated = if ($auth -eq 'notLoggedIn') { $false } elseif ($auth -in @('unsupported', 'bearerToken', 'oAuth')) { $true } else { $null }
    $tools = [Collections.Generic.List[object]]::new()
    if ($null -ne $server.tools) {
        foreach ($property in @($server.tools.PSObject.Properties)) {
            $tool = Convert-ToolDescriptor $property.Value ([string]$property.Name) $true $true
            $tool.authenticated = $authenticated
            $tools.Add($tool) | Out-Null
            if ([string]$property.Name -match '^(?<namespace>[^.]+)\.') {
                $namespace = $Matches['namespace'].ToLowerInvariant()
                if (-not $appToolsByNamespace.ContainsKey($namespace)) { $appToolsByNamespace[$namespace] = [Collections.Generic.List[object]]::new() }
                $appToolsByNamespace[$namespace].Add($tool) | Out-Null
            }
        }
    }
    Add-Capability $capabilities $seen 'mcp' $name $('Codex MCP server {0}' -f $name) $availability 'unknown' @{ source = 'mcpServerStatus/list'; status = $status; auth_status = $auth; tool_count = $tools.Count } $name $name @() $null $authenticated @($tools)
}

foreach ($appCapability in @($capabilities | Where-Object kind -eq 'app')) {
    $namespaces = @([string]$appCapability.display_name, [string]$appCapability.runtime_name) | ForEach-Object { $_.ToLowerInvariant() -replace '[^a-z0-9]+', '_' } | Select-Object -Unique
    $mappedTools = [Collections.Generic.List[object]]::new()
    foreach ($namespace in $namespaces) {
        if ($appToolsByNamespace.ContainsKey($namespace)) { foreach ($tool in $appToolsByNamespace[$namespace]) { $mappedTools.Add($tool) | Out-Null } }
    }
    if ($mappedTools.Count -gt 0) {
        $appCapability.tools = @($mappedTools)
        $appCapability.evidence.tool_source = 'mcpServerStatus/list:codex_apps namespace'
        $appCapability.evidence.tool_count = $mappedTools.Count
    }
}

$snapshot = [ordered]@{
    schema_version = 3
    captured_at = [DateTimeOffset]::UtcNow.ToString('o')
    source = 'codex-app-server'
    cwd = [IO.Path]::GetFullPath($Cwd)
    read_only = $true
    status = if ($sourceErrors.Count -eq 0) { 'complete' } elseif (@($sourceErrors | Where-Object request_id -notin @(3, 5)).Count -eq 0) { 'runtime_complete_catalog_partial' } else { 'partial' }
    coverage = [ordered]@{
        skills = ($null -ne $responses[1].result)
        installed_apps = ($null -ne $responses[2].result)
        app_catalog = ($null -ne $responses[3].result)
        app_metadata_tools = ($responses.ContainsKey(5) -and $null -ne $responses[5].result)
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
