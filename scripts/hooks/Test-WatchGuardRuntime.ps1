[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$HooksListJson,
    [ValidateRange(5, 60)][int]$TimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OptionalProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Invoke-FreshHooksList {
    param([Parameter(Mandatory = $true)][int]$TimeoutSeconds)

    $codexCommand = Get-Command codex -ErrorAction Stop | Select-Object -First 1
    $codexPath = [string]$codexCommand.Source
    if ([string]::IsNullOrWhiteSpace($codexPath)) { $codexPath = [string]$codexCommand.Path }
    if ([string]::IsNullOrWhiteSpace($codexPath)) { throw 'Could not resolve the codex executable or PS7 script.' }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    if ($codexCommand.CommandType -in @('ExternalScript', 'Function', 'Filter') -or [System.IO.Path]::GetExtension($codexPath) -ieq '.ps1') {
        $pwshPath = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwshPath)) { $pwshPath = Join-Path $PSHOME 'pwsh' }
        $psi.FileName = $pwshPath
        foreach ($argument in @('-NoProfile', '-File', $codexPath, 'app-server', '--stdio')) { $psi.ArgumentList.Add($argument) }
    }
    else {
        $psi.FileName = $codexPath
        foreach ($argument in @('app-server', '--stdio')) { $psi.ArgumentList.Add($argument) }
    }
    $script:watchGuardLauncherExecutable = $psi.FileName
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $null = $process.Start()
    try {
        $initialize = [ordered]@{
            jsonrpc = '2.0'
            id = 1
            method = 'initialize'
            params = [ordered]@{
                clientInfo = [ordered]@{ name = 'watch-guard-runtime-doctor'; title = 'Watch guard runtime doctor'; version = '2.0.0' }
                capabilities = [ordered]@{ experimentalApi = $true }
            }
        } | ConvertTo-Json -Depth 10 -Compress
        $process.StandardInput.WriteLine($initialize)
        $process.StandardInput.Flush()

        $sentHooksList = $false
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $readTask = $process.StandardOutput.ReadLineAsync()
        while ([DateTime]::UtcNow -lt $deadline) {
            $winner = [System.Threading.Tasks.Task]::WhenAny($readTask, [System.Threading.Tasks.Task]::Delay(500)).GetAwaiter().GetResult()
            if ($winner -ne $readTask) {
                if ($process.HasExited) { break }
                continue
            }

            $line = $readTask.GetAwaiter().GetResult()
            if ($null -eq $line) { break }
            $readTask = $process.StandardOutput.ReadLineAsync()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $response = $line | ConvertFrom-Json -Depth 50 -ErrorAction Stop }
            catch { continue }

            $responseId = Get-OptionalProperty -InputObject $response -Name 'id'
            if ($responseId -eq 1 -and -not $sentHooksList) {
                $process.StandardInput.WriteLine((@{ jsonrpc = '2.0'; method = 'initialized'; params = @{} } | ConvertTo-Json -Compress))
                $process.StandardInput.WriteLine((@{ jsonrpc = '2.0'; id = 2; method = 'hooks/list'; params = @{} } | ConvertTo-Json -Compress))
                $process.StandardInput.Flush()
                $sentHooksList = $true
                continue
            }
            if ($responseId -eq 2) { return $response }
        }

        throw 'Fresh app-server hooks/list did not return before timeout.'
    }
    finally {
        try { $process.StandardInput.Close() } catch {}
        if (-not $process.WaitForExit(3000)) {
            $process.Kill($true)
            $process.WaitForExit()
        }
    }
}

$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hostHook = Join-Path $resolvedCodexHome 'scripts\block-cross-thread-send.ps1'
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'
$hostExists = Test-Path -LiteralPath $hostHook -PathType Leaf
$hostHash = if ($hostExists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant() } else { $null }
$freshProcess = [string]::IsNullOrWhiteSpace($HooksListJson)
$script:watchGuardLauncherExecutable = $null
$errorMessage = $null

try {
    $hooksList = if ($freshProcess) { Invoke-FreshHooksList -TimeoutSeconds $TimeoutSeconds } else { $HooksListJson | ConvertFrom-Json -Depth 50 -ErrorAction Stop }
}
catch {
    $hooksList = $null
    $errorMessage = $_.Exception.Message
}

$hookMatches = @()
if ($null -ne $hooksList) {
    $hookMatches = @(
        foreach ($entry in @($hooksList.result.data)) {
            foreach ($hook in @($entry.hooks)) {
                if ([string]$hook.command -like '*block-cross-thread-send.ps1*') { $hook }
            }
        }
    )
}

$hook = if ($hookMatches.Count -eq 1) { $hookMatches[0] } else { $null }
$command = if ($null -ne $hook) { [string]$hook.command } else { '' }
$expectedHash = if ($command -match '(?i)-ExpectedScriptSha256\s+["'']?([0-9a-f]{64})') { $Matches[1].ToLowerInvariant() } else { $null }
$targetPromptHash = if ($command -match '(?i)-ExpectedTargetPromptSha256\s+["'']?([0-9a-f]{64})') { $Matches[1].ToLowerInvariant() } else { $null }
$fleetPromptHash = if ($command -match '(?i)-ExpectedFleetPromptSha256\s+["'']?([0-9a-f]{64})') { $Matches[1].ToLowerInvariant() } else { $null }
$fleetShutdownPromptHash = if ($command -match '(?i)-ExpectedFleetShutdownPromptSha256\s+["'']?([0-9a-f]{64})') { $Matches[1].ToLowerInvariant() } else { $null }

$sourceHookMatches = @()
try {
    if (Test-Path -LiteralPath $hooksPath -PathType Leaf) {
        $sourceDocument = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json -Depth 50 -ErrorAction Stop
        foreach ($group in @($sourceDocument.hooks.PreToolUse)) {
            foreach ($handler in @($group.hooks)) {
                if ([string]$handler.command -like '*block-cross-thread-send.ps1*') {
                    $sourceHookMatches += [pscustomobject]@{ group = $group; handler = $handler }
                }
            }
        }
    }
}
catch {
    if ([string]::IsNullOrWhiteSpace($errorMessage)) { $errorMessage = $_.Exception.Message }
}

$sourceHook = if ($sourceHookMatches.Count -eq 1) { $sourceHookMatches[0] } else { $null }
$sourceCommand = if ($null -ne $sourceHook) { [string]$sourceHook.handler.command } else { '' }
$sourceCommandWindows = if ($null -ne $sourceHook) { [string](Get-OptionalProperty -InputObject $sourceHook.handler -Name 'commandWindows') } else { '' }
$sourceShapeMatches = $null -ne $sourceHook -and [string]$sourceHook.group.matcher -ceq '*' -and
    [string]$sourceHook.handler.type -ceq 'command' -and $sourceCommand -ceq $command -and
    -not [string]::IsNullOrWhiteSpace($sourceCommandWindows) -and $sourceCommandWindows -ceq $sourceCommand

$enabled = $null -ne $hook -and [bool]$hook.enabled
$trustStatus = if ($null -ne $hook) { [string]$hook.trustStatus } else { 'missing' }
$currentHash = if ($null -ne $hook) { [string]$hook.currentHash } else { $null }
$runtimeShapeMatches = $null -ne $hook -and [string]$hook.eventName -ceq 'preToolUse' -and
    [string]$hook.handlerType -ceq 'command' -and [string]$hook.matcher -ceq '*'
$shapeMatches = $runtimeShapeMatches -and $sourceShapeMatches
$definitionMatches = $hostExists -and -not [string]::IsNullOrWhiteSpace($expectedHash) -and $expectedHash -ceq $hostHash -and
    $targetPromptHash -match '^[0-9a-f]{64}$' -and $fleetPromptHash -match '^[0-9a-f]{64}$' -and $fleetShutdownPromptHash -match '^[0-9a-f]{64}$' -and $shapeMatches
$configurationReady = $hookMatches.Count -eq 1 -and $enabled -and $trustStatus -ceq 'trusted' -and $definitionMatches -and
    -not [string]::IsNullOrWhiteSpace($currentHash)

[pscustomobject]@{
    configuration_ready = $configurationReady
    fresh_process = $freshProcess
    launcher_executable = $script:watchGuardLauncherExecutable
    hook_count = $hookMatches.Count
    enabled = $enabled
    trust_status = $trustStatus
    current_hash = $currentHash
    host_hook_path = $hostHook
    host_sha256 = $hostHash
    expected_script_sha256 = $expectedHash
    target_prompt_sha256 = $targetPromptHash
    fleet_prompt_sha256 = $fleetPromptHash
    fleet_shutdown_prompt_sha256 = $fleetShutdownPromptHash
    runtime_shape_matches = $runtimeShapeMatches
    source_shape_matches = $sourceShapeMatches
    shape_matches = $shapeMatches
    definition_matches = $definitionMatches
    live_send_probe_required = $true
    live_automation_probe_required = $true
    specialized_path_boundary = 'guardrail_only'
    overall = if ($configurationReady) { 'trusted_requires_live_probes' } else { 'soft_guard_only' }
    error = $errorMessage
}
