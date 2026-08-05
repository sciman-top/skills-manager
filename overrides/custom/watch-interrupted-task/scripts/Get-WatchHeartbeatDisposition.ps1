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
        'unknown',
        'stale_policy_running',
        'soft_guard_only'
    )]
    [string]$State,

    [ValidateSet('supervisor_monitor_only', 'conditional_recovery')]
    [string]$OperatingMode = 'conditional_recovery',

    [ValidateSet('none', 'active', 'paused', 'complete', 'blocked')]
    [string]$GoalStatus = 'none',

    [switch]$HasPositiveEvidence,
    [AllowEmptyString()][string]$EvidenceTimestampUtc = '',
    [AllowEmptyString()][string]$CheckpointId = '',
    [AllowEmptyString()][string]$ReceiptKey = '',

    [ValidateSet('none', 'safe', 'unknown', 'unsafe')]
    [string]$ExternalEffectState = 'unknown',

    [switch]$AcceptanceVerified,
    [ValidateRange(0, 1000)][int]$ConsecutiveSameBlockCount = 0,
    [switch]$SameBlockingConditionConfirmed,
    [switch]$NoMeaningfulProgressPossible,
    [switch]$AsJson
)

Set-StrictMode -Version Latest

$result = [ordered]@{
    state = $State
    operating_mode = $OperatingMode
    goal_status = $GoalStatus
    task_action = 'observe_only'
    goal_action = 'keep_active'
    automation_action = 'keep_active'
    mutation_owner = 'none'
    notification_action = 'dont_notify'
    requires_receipt = $false
    reason_code = 'state_observed'
}

function Test-RecoveryEvidence {
    $timestamp = [DateTimeOffset]::MinValue
    $timestampValid = [DateTimeOffset]::TryParse(
        $EvidenceTimestampUtc,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$timestamp
    )
    $now = [DateTimeOffset]::UtcNow
    $timestampFresh = $timestampValid -and $timestamp -ge $now.AddHours(-24) -and $timestamp -le $now.AddMinutes(5)

    if (-not $HasPositiveEvidence -or -not $timestampFresh) {
        $result.reason_code = 'missing_or_stale_evidence'
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($CheckpointId)) {
        $result.reason_code = 'missing_checkpoint'
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($ReceiptKey)) {
        $result.reason_code = 'missing_receipt_key'
        return $false
    }
    if ($ExternalEffectState -notin @('none', 'safe')) {
        $result.reason_code = 'external_effect_unproved'
        return $false
    }
    return $true
}

if ($OperatingMode -ceq 'supervisor_monitor_only') {
    $result.reason_code = 'monitor_only_policy'
}
elseif ($State -in @('resume_eligible', 'continuation_gap', 'recoverable_task_failure', 'strategy_drift', 'verification_failed')) {
    if ($GoalStatus -in @('paused', 'complete', 'blocked')) {
        $result.reason_code = 'goal_not_active'
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
    if ($AcceptanceVerified) {
        $result.task_action = 'stop_after_verification'
        $result.goal_action = if ($GoalStatus -ceq 'active') { 'mark_complete' } else { 'none' }
        $result.automation_action = 'request_supervisor_cleanup'
        $result.mutation_owner = 'target_thread'
        $result.requires_receipt = $true
        $result.reason_code = 'acceptance_verified'
    }
    else {
        $result.task_action = 'verify_goal_acceptance'
        $result.mutation_owner = 'target_thread'
        $result.reason_code = 'acceptance_unproved'
    }
}
elseif ($State -ceq 'needs_input') {
    $result.task_action = 'stop_for_user'
    $result.notification_action = 'notify_once'
    $result.reason_code = 'human_gate'
    if ($GoalStatus -ceq 'active' -and $ConsecutiveSameBlockCount -ge 3 -and
        $SameBlockingConditionConfirmed -and $NoMeaningfulProgressPossible) {
        $result.goal_action = 'mark_blocked'
        $result.reason_code = 'proved_repeated_impasse'
    }
}
elseif ($State -in @('non_transient_failure', 'unknown', 'soft_guard_only')) {
    $result.notification_action = 'notify_once'
    $result.reason_code = $State
}
elseif ($State -ceq 'complete') {
    $result.automation_action = 'request_supervisor_cleanup'
    $result.reason_code = 'already_complete'
}
elseif ($State -ceq 'peer_busy') {
    $result.reason_code = 'peer_busy_retry_later'
}
elseif ($State -ceq 'running') {
    $result.reason_code = 'already_running'
}
elseif ($State -ceq 'natural_pause') {
    $result.reason_code = 'user_pause_or_checkpoint'
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
