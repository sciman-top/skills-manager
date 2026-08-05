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

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'cmd.exe'
    foreach ($argument in @('/d', '/s', '/c', 'codex app-server --stdio')) {
        $psi.ArgumentList.Add($argument)
    }
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
                clientInfo = [ordered]@{ name = 'watch-guard-runtime-doctor'; title = 'Watch guard runtime doctor'; version = '1.0.0' }
                capabilities = [ordered]@{ experimentalApi = $true }
            }
        } | ConvertTo-Json -Depth 10 -Compress
        $process.StandardInput.WriteLine($initialize)
        $process.StandardInput.Flush()

        $sentHooksList = $false
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $readTask = $process.StandardOutput.ReadLineAsync()
            $winner = [System.Threading.Tasks.Task]::WhenAny($readTask, [System.Threading.Tasks.Task]::Delay(1000)).GetAwaiter().GetResult()
            if ($winner -ne $readTask) {
                if ($process.HasExited) { break }
                continue
            }

            $line = $readTask.GetAwaiter().GetResult()
            if ($null -eq $line) { break }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $response = $line | ConvertFrom-Json -Depth 50
            $responseId = Get-OptionalProperty -InputObject $response -Name 'id'
            if ($responseId -eq 1 -and -not $sentHooksList) {
                $process.StandardInput.WriteLine((@{ jsonrpc = '2.0'; method = 'initialized'; params = @{} } | ConvertTo-Json -Compress))
                $process.StandardInput.WriteLine((@{ jsonrpc = '2.0'; id = 2; method = 'hooks/list'; params = @{} } | ConvertTo-Json -Compress))
                $process.StandardInput.Flush()
                $sentHooksList = $true
                continue
            }
            if ($responseId -eq 2) {
                return $response
            }
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
$hostExists = Test-Path -LiteralPath $hostHook -PathType Leaf
$hostHash = if ($hostExists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant() } else { $null }
$freshProcess = [string]::IsNullOrWhiteSpace($HooksListJson)
$errorMessage = $null

try {
    $hooksList = if ($freshProcess) { Invoke-FreshHooksList -TimeoutSeconds $TimeoutSeconds } else { $HooksListJson | ConvertFrom-Json -Depth 50 }
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
                if ([string]$hook.command -like '*block-cross-thread-send.ps1*') {
                    $hook
                }
            }
        }
    )
}

$hook = if ($hookMatches.Count -eq 1) { $hookMatches[0] } else { $null }
$expectedHash = $null
if ($null -ne $hook -and [string]$hook.command -match '(?i)-ExpectedScriptSha256\s+["'']?([0-9a-f]{64})') {
    $expectedHash = $Matches[1].ToLowerInvariant()
}

$enabled = $null -ne $hook -and [bool]$hook.enabled
$trustStatus = if ($null -ne $hook) { [string]$hook.trustStatus } else { 'missing' }
$currentHash = if ($null -ne $hook) { [string]$hook.currentHash } else { $null }
$definitionMatches = $hostExists -and -not [string]::IsNullOrWhiteSpace($expectedHash) -and $expectedHash -ceq $hostHash
$configurationReady = $hookMatches.Count -eq 1 -and $enabled -and $trustStatus -ceq 'trusted' -and $definitionMatches -and
    -not [string]::IsNullOrWhiteSpace($currentHash)

[pscustomobject]@{
    configuration_ready = $configurationReady
    fresh_process = $freshProcess
    hook_count = $hookMatches.Count
    enabled = $enabled
    trust_status = $trustStatus
    current_hash = $currentHash
    host_hook_path = $hostHook
    host_sha256 = $hostHash
    expected_script_sha256 = $expectedHash
    definition_matches = $definitionMatches
    live_send_probe_required = $true
    live_automation_probe_required = $true
    specialized_path_boundary = 'guardrail_only'
    overall = if ($configurationReady) { 'trusted_requires_live_probes' } else { 'soft_guard_only' }
    error = $errorMessage
}
