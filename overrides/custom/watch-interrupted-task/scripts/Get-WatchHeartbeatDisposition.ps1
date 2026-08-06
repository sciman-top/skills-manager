[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'running',
        'resume_eligible',
        'continuation_gap',
        'recoverable_task_failure',
        'strategy_drift',
        'verification_failed',
        'goal_satisfied',
        'peer_busy',
        'natural_pause',
        'needs_input',
        'complete',
        'non_transient_failure',
        'stopped',
        'unknown',
        'stale_policy_running',
        'soft_guard_only'
    )]
    [string]$State,

    [ValidateSet('supervisor_monitor_only', 'conditional_recovery')]
    [string]$OperatingMode = 'conditional_recovery',

    [switch]$ShutdownManaged,
    [AllowEmptyString()][string]$PriorNotifiedReceiptKey = '',

    [ValidateSet('none', 'active', 'paused', 'complete', 'blocked')]
    [string]$GoalStatus = 'none',

    [switch]$HasPositiveEvidence,
    [AllowEmptyString()][string]$EvidenceTimestampUtc = '',
    [AllowEmptyString()][string]$CheckpointId = '',
    [AllowEmptyString()][string]$ReceiptKey = '',
    [AllowEmptyString()][string]$NextRetryAtUtc = '',
    [string]$NowUtc = ([DateTimeOffset]::UtcNow.ToString('o')),
    [ValidateRange(1, 1440)][int]$EvidenceFreshnessMinutes = 15,

    [ValidateSet('none', 'safe', 'unknown', 'unsafe')]
    [string]$ExternalEffectState = 'unknown',

    [switch]$AcceptanceVerified,
    [switch]$NoActiveTurn,
    [switch]$TaskStopped,
    [AllowEmptyString()][string]$StopReason = '',
    [switch]$RecoveryPending,
    [AllowEmptyString()][string]$NextRetryAt = '',
    [ValidateRange(0, 1000)][int]$ConsecutiveSameBlockCount = 0,
    [switch]$SameBlockingConditionConfirmed,
    [switch]$NoMeaningfulProgressPossible,
    [switch]$AsJson
)

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')

$result = [ordered]@{
    state = $State
    operating_mode = $OperatingMode
    goal_status = $GoalStatus
    task_action = 'observe_only'
    goal_action = 'keep_active'
    automation_action = 'keep_active'
    quiesce_action = 'none'
    mutation_owner = 'none'
    notification_action = 'dont_notify'
    next_retry_at = if (-not [string]::IsNullOrWhiteSpace($NextRetryAtUtc)) { $NextRetryAtUtc } else { $NextRetryAt }
    requires_receipt = $false
    reason_code = 'state_observed'
    task_stopped = [bool]$TaskStopped
    stop_reason = $StopReason
    recovery_pending = [bool]$RecoveryPending
    prior_notified_receipt_key = $PriorNotifiedReceiptKey
}

$evaluationNow = [DateTimeOffset]::MinValue
$evaluationTimeValid = Test-WatchRfc3339Timestamp -Value $NowUtc -Parsed ([ref]$evaluationNow)
$retryBoundary = [DateTimeOffset]::MinValue
$retryBoundaryValid = [string]::IsNullOrWhiteSpace($NextRetryAtUtc) -or
    (Test-WatchRfc3339Timestamp -Value $NextRetryAtUtc -Parsed ([ref]$retryBoundary))

function Test-RecoveryEvidence {
    $timestamp = [DateTimeOffset]::MinValue
    $timestampValid = Test-WatchRfc3339Timestamp -Value $EvidenceTimestampUtc -Parsed ([ref]$timestamp)
    if (-not $evaluationTimeValid) {
        $result.reason_code = 'evaluation_time_invalid'
        return $false
    }
    $timestampFresh = $timestampValid -and $timestamp -ge $evaluationNow.AddMinutes(-$EvidenceFreshnessMinutes) -and $timestamp -le $evaluationNow.AddMinutes(5)

    if (-not $HasPositiveEvidence -or -not $timestampFresh) {
        $result.reason_code = 'missing_or_stale_evidence'
        return $false
    }
    if ($CheckpointId -notmatch '^watch-checkpoint:[0-9a-f]{64}$') {
        $result.reason_code = 'invalid_checkpoint'
        return $false
    }
    if ($ReceiptKey -notmatch '^watch-receipt:[0-9a-f]{64}$') {
        $result.reason_code = 'invalid_receipt_key'
        return $false
    }
    if ($ExternalEffectState -notin @('none', 'safe')) {
        $result.reason_code = 'external_effect_unproved'
        return $false
    }
    return $true
}

function Test-StoppedEvidence {
    if (-not $TaskStopped) {
        $result.reason_code = 'stop_decision_unproved'
        return $false
    }
    if ($RecoveryPending -or -not [string]::IsNullOrWhiteSpace($NextRetryAt)) {
        $result.reason_code = 'recovery_or_retry_pending'
        return $false
    }
    if (-not $NoActiveTurn) {
        $result.reason_code = 'active_turn_present_or_unproved'
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($StopReason) -or $StopReason -notmatch '^[a-z0-9][a-z0-9._:-]{0,127}$') {
        $result.reason_code = 'stop_reason_invalid'
        return $false
    }
    return (Test-RecoveryEvidence)
}

if ($OperatingMode -ceq 'supervisor_monitor_only') {
    $result.reason_code = 'monitor_only_policy'
}
elseif ($State -in @('resume_eligible', 'continuation_gap', 'recoverable_task_failure', 'strategy_drift', 'verification_failed')) {
    if ($GoalStatus -in @('paused', 'complete', 'blocked')) {
        $result.reason_code = 'goal_not_active'
    }
    elseif (-not $evaluationTimeValid) {
        $result.reason_code = 'evaluation_time_invalid'
    }
    elseif (-not $retryBoundaryValid) {
        $result.reason_code = 'retry_time_invalid'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($NextRetryAtUtc) -and $retryBoundary -gt $evaluationNow) {
        $result.reason_code = 'retry_not_due'
    }
    elseif (Test-RecoveryEvidence) {
        $result.task_action = switch ($State) {
            'strategy_drift' { 'reconcile_goal_and_continue' }
            'recoverable_task_failure' { 'diagnose_replan_and_continue' }
            'verification_failed' { 'diagnose_replan_and_continue' }
            default { 'resume_from_checkpoint' }
        }
        $result.mutation_owner = 'target_thread'
        $result.requires_receipt = $true
        $result.reason_code = 'recovery_authorized'
    }
}
elseif ($State -ceq 'goal_satisfied') {
    if ($GoalStatus -in @('paused', 'blocked')) {
        $result.reason_code = 'goal_not_terminal'
    }
    elseif ($AcceptanceVerified) {
        $result.task_action = 'stop_after_verification'
        $result.goal_action = if ($GoalStatus -ceq 'active') { 'mark_complete' } else { 'none' }
        $result.mutation_owner = 'target_thread'
        if ($GoalStatus -in @('none', 'complete') -and $NoActiveTurn -and (Test-RecoveryEvidence)) {
            $result.automation_action = 'request_supervisor_cleanup'
            if ($ShutdownManaged) { $result.quiesce_action = 'pause_self' }
            $result.requires_receipt = $true
            $result.reason_code = 'acceptance_verified_cleanup_ready'
        }
        else {
            $result.reason_code = if ($GoalStatus -ceq 'active') { 'acceptance_verified_goal_completion_pending_cleanup' } else { 'cleanup_evidence_required' }
        }
    }
    else {
        $result.task_action = 'verify_goal_acceptance'
        $result.mutation_owner = 'target_thread'
        $result.reason_code = 'acceptance_unproved'
    }
}
elseif ($State -in @('natural_pause', 'needs_input', 'complete', 'non_transient_failure', 'stopped')) {
    $result.task_action = if ($State -ceq 'needs_input') { 'stop_for_user' } else { 'stop_terminal' }
    $result.reason_code = switch ($State) {
        'natural_pause' { 'user_pause_or_checkpoint' }
        'needs_input' { 'human_gate' }
        'complete' { 'task_complete' }
        'non_transient_failure' { 'non_transient_failure' }
        default { 'stable_stop_observed' }
    }
    if ($State -ceq 'needs_input' -and $GoalStatus -ceq 'active' -and
        $ConsecutiveSameBlockCount -ge 3 -and $SameBlockingConditionConfirmed -and
        $NoMeaningfulProgressPossible) {
        $result.goal_action = 'mark_blocked'
    }
    if (Test-StoppedEvidence) {
        $result.automation_action = 'request_supervisor_cleanup'
        if ($ShutdownManaged) { $result.quiesce_action = 'pause_self' }
        $result.mutation_owner = 'target_thread'
        $result.requires_receipt = $true
        $result.reason_code = 'proved_stopped_cleanup_ready'
        if ($State -in @('needs_input', 'non_transient_failure') -and $PriorNotifiedReceiptKey -cne $ReceiptKey) {
            $result.notification_action = 'notify_once'
        }
    }
}
elseif ($State -in @('unknown', 'soft_guard_only')) {
    $result.notification_action = 'notify_once'
    $result.reason_code = $State
}
elseif ($State -ceq 'peer_busy') {
    $result.reason_code = 'peer_busy_retry_later'
}
elseif ($State -ceq 'running') {
    $result.reason_code = 'already_running'
}
elseif ($State -ceq 'stale_policy_running') {
    $result.reason_code = 'stale_turn_must_finish'
}

$output = [pscustomobject]$result
if ($AsJson) {
    $output | ConvertTo-Json -Depth 5 -Compress
}
else {
    $output
}
