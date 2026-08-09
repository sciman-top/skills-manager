[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourceHookPath = (Join-Path $PSScriptRoot 'block-cross-thread-send.ps1'),
    [string]$SourcePolicyPath = (Join-Path $PSScriptRoot 'CrossThreadGuardPolicy.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CrossThreadPolicyProbe {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [AllowNull()][object]$ToolInput,
        [AllowEmptyString()][string]$TurnText = '',
        [string]$SessionId = 'doctor-source'
    )

    return Get-CrossThreadGuardDecision -Payload ([pscustomobject][ordered]@{
        session_id = $SessionId
        hook_event_name = 'PreToolUse'
        tool_name = $ToolName
        tool_input = $ToolInput
        __watch_turn_text = $TurnText
    })
}

$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'
$configPath = Join-Path $resolvedCodexHome 'config.toml'
$hostHook = Join-Path $resolvedCodexHome 'scripts\block-cross-thread-send.ps1'
$hostPolicy = Join-Path $resolvedCodexHome 'scripts\CrossThreadGuardPolicy.ps1'

$featureEnabled = $true
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $configText = Get-Content -Raw -LiteralPath $configPath
    if ($configText -match '(?mi)^\s*hooks\s*=\s*false\s*(?:#.*)?$') { $featureEnabled = $false }
}

$sourceExists = Test-Path -LiteralPath $SourceHookPath -PathType Leaf
$policySourceExists = Test-Path -LiteralPath $SourcePolicyPath -PathType Leaf
$hostExists = Test-Path -LiteralPath $hostHook -PathType Leaf
$policyHostExists = Test-Path -LiteralPath $hostPolicy -PathType Leaf
$sourceHash = if ($sourceExists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceHookPath).Hash.ToLowerInvariant() } else { $null }
$hostHash = if ($hostExists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant() } else { $null }
$policySourceHash = if ($policySourceExists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePolicyPath).Hash.ToLowerInvariant() } else { $null }
$policyHostHash = if ($policyHostExists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $hostPolicy).Hash.ToLowerInvariant() } else { $null }
$hashMatches = -not [string]::IsNullOrWhiteSpace($sourceHash) -and $sourceHash -ceq $hostHash -and
    -not [string]::IsNullOrWhiteSpace($policySourceHash) -and $policySourceHash -ceq $policyHostHash

$definitionMatches = $false
$errorMessage = $null
try {
    if (Test-Path -LiteralPath $hooksPath -PathType Leaf) {
        $document = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json -Depth 50 -ErrorAction Stop
        $matches = @(
            foreach ($group in @($document.hooks.PreToolUse)) {
                foreach ($handler in @($group.hooks)) {
                    if ([string]$group.matcher -ceq '*' -and [string]$handler.type -ceq 'command' -and
                        [string]$handler.command -like "*$hostHook*") {
                        [pscustomobject]@{ group=$group; handler=$handler }
                    }
                }
            }
        )
        if ($matches.Count -eq 1) {
            $command = [string]$matches[0].handler.command
            $commandWindows = [string]$matches[0].handler.commandWindows
            $expectedCommand = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedScriptSha256 "{1}" -ExpectedPolicySha256 "{2}"' -f $hostHook, $sourceHash, $policySourceHash
            $definitionMatches = $command -ceq $expectedCommand -and $commandWindows -ceq $command
        }
    }
}
catch {
    $errorMessage = $_.Exception.Message
}

$simulationCases = [ordered]@{
    direct_send_blocked = $false
    direct_handoff_blocked = $false
    heartbeat_mutation_blocked = $false
    heartbeat_power_blocked = $false
    exact_legacy_delete_allowed = $false
    negated_delete_blocked = $false
    read_only_view_allowed = $false
}
$simulationFailures = [ordered]@{}

if ($hashMatches) {
    try {
        . $hostPolicy
        $heartbeat = '<heartbeat><automation_id>legacy-watch</automation_id><instructions>watch-interrupted-task:v1 target_thread_id=doctor-source</instructions></heartbeat>'
        $probes = [ordered]@{
            direct_send_blocked = [ordered]@{ Expected='deny'; Decision=(Invoke-CrossThreadPolicyProbe -ToolName 'codex_app__send_message_to_thread' -ToolInput ([ordered]@{ threadId='target'; prompt='blocked' })) }
            direct_handoff_blocked = [ordered]@{ Expected='deny'; Decision=(Invoke-CrossThreadPolicyProbe -ToolName 'codex_app__handoff_thread' -ToolInput ([ordered]@{ threadId='target' })) }
            heartbeat_mutation_blocked = [ordered]@{ Expected='deny'; Decision=(Invoke-CrossThreadPolicyProbe -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{ mode='update'; id='watch-interrupted-task-v1-target-thread-id-doctor-source'; status='ACTIVE' }) -TurnText $heartbeat) }
            heartbeat_power_blocked = [ordered]@{ Expected='deny'; Decision=(Invoke-CrossThreadPolicyProbe -ToolName 'shell_command' -ToolInput ([ordered]@{ command='shutdown.exe /s /t 120' }) -TurnText $heartbeat) }
            exact_legacy_delete_allowed = [ordered]@{ Expected='allow'; Decision=(Invoke-CrossThreadPolicyProbe -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{ mode='delete'; id='watch-interrupted-task-v1-target-thread-id-doctor-source' }) -TurnText '关闭当前任务的旧守夜。') }
            negated_delete_blocked = [ordered]@{ Expected='deny'; Decision=(Invoke-CrossThreadPolicyProbe -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{ mode='delete'; id='watch-interrupted-task-v1-target-thread-id-doctor-source' }) -TurnText '不要关闭当前任务守夜。') }
            read_only_view_allowed = [ordered]@{ Expected='allow'; Decision=(Invoke-CrossThreadPolicyProbe -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{ mode='view'; id='watch-interrupted-task-v1-target-thread-id-doctor-source' }) -TurnText $heartbeat) }
        }
        foreach ($probe in $probes.GetEnumerator()) {
            $actual = [string]$probe.Value.Decision.permission_decision
            $simulationCases[$probe.Key] = $actual -ceq [string]$probe.Value.Expected
            if (-not $simulationCases[$probe.Key]) { $simulationFailures[$probe.Key] = "expected=$($probe.Value.Expected);actual=$actual" }
        }
    }
    catch {
        $simulationFailures['policy_load'] = $_.Exception.Message
    }
}

$simulationPassed = @($simulationCases.Values | Where-Object { -not $_ }).Count -eq 0
$staticConfigurationReady = $featureEnabled -and $hashMatches -and $definitionMatches -and $simulationPassed

[pscustomobject]@{
    configuration_ready = $false
    static_configuration_ready = $staticConfigurationReady
    feature_enabled = $featureEnabled
    watch_runtime_status = 'retired_fail_closed'
    source_sha256 = $sourceHash
    host_sha256 = $hostHash
    policy_source_sha256 = $policySourceHash
    policy_host_sha256 = $policyHostHash
    hash_matches = $hashMatches
    definition_matches = $definitionMatches
    simulation_passed = $simulationPassed
    simulation_cases = [pscustomobject]$simulationCases
    simulation_failures = [pscustomobject]$simulationFailures
    trust_status = 'unverified_requires_slash_hooks'
    live_path_status = 'unverified_requires_fresh_session_probe'
    specialized_path_boundary = 'guardrail_only'
    overall = 'soft_guard_only'
    error = $errorMessage
}
