[CmdletBinding()]
param(
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$SourceCommit = '',

    [string]$HookSourcePath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))) 'scripts\hooks\block-cross-thread-send.ps1'),
    [string]$InstalledHookPath = '',
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
    $SourceCommit = (& git -C $repoRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
}
if ($SourceCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'source_commit_invalid' }

$targetGenerator = Join-Path $PSScriptRoot 'New-WatchHeartbeatPrompt.ps1'
$fleetGenerator = Join-Path $PSScriptRoot 'New-WatchFleetSupervisorPrompt.ps1'
$generationId = Get-WatchRuntimeGenerationId
$target = (& $targetGenerator -TargetThreadId 'runtime-generation-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop
$shutdownTarget = (& $targetGenerator -TargetThreadId 'runtime-generation-probe' -ShutdownManaged -AsJson) | ConvertFrom-Json -ErrorAction Stop
$fleet = (& $fleetGenerator -SupervisorThreadId 'runtime-generation-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop
$shutdownFleet = (& $fleetGenerator -SupervisorThreadId 'runtime-generation-probe' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json -ErrorAction Stop
$resolvedHook = (Resolve-Path -LiteralPath $HookSourcePath -ErrorAction Stop).Path
$hookSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedHook).Hash.ToLowerInvariant()
$installedHookHash = if (-not [string]::IsNullOrWhiteSpace($InstalledHookPath) -and (Test-Path -LiteralPath $InstalledHookPath -PathType Leaf)) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $InstalledHookPath).Hash.ToLowerInvariant()
}
else { '' }

$bindingFields = [ordered]@{
    watch_runtime_generation_id = $generationId
    source_commit = $SourceCommit.ToLowerInvariant()
    target_prompt_sha256 = [string]$target.prompt_sha256
    shutdown_target_prompt_sha256 = [string]$shutdownTarget.prompt_sha256
    fleet_prompt_sha256 = [string]$fleet.prompt_sha256
    fleet_shutdown_prompt_sha256 = [string]$shutdownFleet.prompt_sha256
    hook_source_sha256 = $hookSourceHash
    installed_hook_sha256 = $installedHookHash
}
$bindingText = @($bindingFields.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join "`n"
$bindingHash = Get-WatchPromptSha256 -Body $bindingText

$result = [pscustomobject][ordered]@{
    schema_version = 1
    watch_runtime_generation_id = $generationId
    source_commit = $SourceCommit.ToLowerInvariant()
    policy_revision = 3
    target_prompt_sha256 = [string]$target.prompt_sha256
    shutdown_target_prompt_sha256 = [string]$shutdownTarget.prompt_sha256
    fleet_prompt_sha256 = [string]$fleet.prompt_sha256
    fleet_shutdown_prompt_sha256 = [string]$shutdownFleet.prompt_sha256
    hook_source_sha256 = $hookSourceHash
    installed_hook_sha256 = $installedHookHash
    generation_binding_sha256 = $bindingHash
}

if ($AsJson) { $result | ConvertTo-Json -Depth 5 -Compress } else { $result }
