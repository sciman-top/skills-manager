[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SnapshotJson,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$')]
    [string]$AutomationId,

    [Parameter(Mandatory = $true)]
    [string]$CurrentTickId,

    [string]$PreviousTickId = '',

    [string]$PreviousSnapshotKey = '',
    [string]$PriorShutdownReceiptKey = '',

    [ValidateRange(1, 60)]
    [int]$FreshnessMinutes = 15,

    [ValidateRange(30, 3600)]
    [int]$ShutdownDelaySeconds = 120,

    [ValidateRange(30, 300)]
    [int]$ShutdownReceiptTtlSeconds = 120,

    [ValidateRange(0, 1000)]
    [int]$RemainingTargetHeartbeatCount = 0,

    [ValidateRange(0, 1000)]
    [int]$UnmonitoredActiveTaskCount = 0,

    [switch]$ShutdownArmed,
    [switch]$VisibilityComplete,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WatchFleetProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-WatchFleetSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

$result = [ordered]@{
    schema_version = 3
    automation_id = $AutomationId
    current_tick_id = $CurrentTickId
    previous_tick_id = $PreviousTickId
    power_action = 'observe_only'
    reason_code = 'shutdown_not_armed'
    monitored_count = 0
    stopped_count = 0
    snapshot_key = ''
    shutdown_receipt_key = ''
    shutdown_receipt_expires_at_utc = ''
    shutdown_delay_seconds = $ShutdownDelaySeconds
    remaining_target_heartbeat_count = $RemainingTargetHeartbeatCount
    unmonitored_active_task_count = $UnmonitoredActiveTaskCount
    requires_fresh_recheck = $true
}

if ($ShutdownArmed) {
    $now = [datetimeoffset]::UtcNow
    $currentTick = [datetimeoffset]::MinValue
    $previousTick = [datetimeoffset]::MinValue
    if (-not $VisibilityComplete) {
        $result.reason_code = 'visibility_unproved'
    }
    elseif ($UnmonitoredActiveTaskCount -ne 0) {
        $result.reason_code = 'unmonitored_active_tasks'
    }
    elseif ($RemainingTargetHeartbeatCount -ne 0) {
        $result.reason_code = 'target_heartbeats_remain'
    }
    elseif (-not [datetimeoffset]::TryParse($CurrentTickId, [ref]$currentTick)) {
        $result.reason_code = 'current_tick_invalid'
    }
    elseif ($currentTick -gt $now.AddMinutes(1) -or $currentTick -lt $now.AddMinutes(-$FreshnessMinutes)) {
        $result.reason_code = 'current_tick_stale'
    }
    else {
        try {
            $parsed = $SnapshotJson | ConvertFrom-Json -Depth 20 -ErrorAction Stop
            $records = @($parsed)
        }
        catch {
            $records = @()
            $result.reason_code = 'snapshot_json_invalid'
        }

        if ($result.reason_code -ne 'snapshot_json_invalid') {
            $result.monitored_count = $records.Count
            if ($records.Count -eq 0) {
                $result.reason_code = 'monitored_set_empty'
            }
            else {
                $recoveryOrRetryStates = @('resume_eligible', 'continuation_gap', 'recoverable_task_failure', 'strategy_drift', 'verification_failed', 'peer_busy', 'stale_policy_running')
                $unprovedStates = @('unknown', 'soft_guard_only', 'goal_satisfied')
                $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                $automationIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                $canonicalRows = [System.Collections.Generic.List[string]]::new()
                $finding = $null

                foreach ($record in @($records | Sort-Object { [string](Get-WatchFleetProperty $_ 'target_thread_id') })) {
                    $targetThreadId = [string](Get-WatchFleetProperty $record 'target_thread_id')
                    $targetAutomationId = [string](Get-WatchFleetProperty $record 'automation_id')
                    $sourceTurnId = [string](Get-WatchFleetProperty $record 'source_turn_id')
                    $state = [string](Get-WatchFleetProperty $record 'state')
                    $taskStopped = Get-WatchFleetProperty $record 'task_stopped'
                    $stopReason = [string](Get-WatchFleetProperty $record 'stop_reason')
                    $recoveryPending = Get-WatchFleetProperty $record 'recovery_pending'
                    $receiptKey = [string](Get-WatchFleetProperty $record 'receipt_key')
                    $checkpointId = [string](Get-WatchFleetProperty $record 'checkpoint_id')
                    $evidenceTimestampText = [string](Get-WatchFleetProperty $record 'evidence_timestamp_utc')
                    $externalEffectState = [string](Get-WatchFleetProperty $record 'external_effect_state')
                    $nextRetryAt = [string](Get-WatchFleetProperty $record 'next_retry_at')
                    $noActiveTurn = Get-WatchFleetProperty $record 'no_active_turn'

                    if ([string]::IsNullOrWhiteSpace($targetThreadId) -or
                        $targetThreadId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or
                        -not $ids.Add($targetThreadId)) {
                        $finding = 'target_identity_invalid'
                        break
                    }
                    if ([string]::IsNullOrWhiteSpace($targetAutomationId) -or
                        $targetAutomationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or
                        -not $automationIds.Add($targetAutomationId) -or
                        [string]::IsNullOrWhiteSpace($sourceTurnId) -or
                        $sourceTurnId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') {
                        $finding = 'target_provenance_invalid'
                        break
                    }
                    if ($state -eq 'running') {
                        $finding = 'target_running'
                        break
                    }
                    if ($state -in $recoveryOrRetryStates) {
                        $finding = 'recovery_or_retry_pending'
                        break
                    }
                    if ($state -in $unprovedStates -or [string]::IsNullOrWhiteSpace($state)) {
                        $finding = 'target_state_unproved'
                        break
                    }
                    if ($recoveryPending -isnot [bool]) {
                        $finding = 'recovery_status_unproved'
                        break
                    }
                    if ([bool]$recoveryPending) {
                        $finding = 'recovery_or_retry_pending'
                        break
                    }
                    if ($taskStopped -isnot [bool] -or -not [bool]$taskStopped) {
                        $finding = 'stop_decision_unproved'
                        break
                    }
                    if ([string]::IsNullOrWhiteSpace($stopReason) -or $stopReason -notmatch '^[a-z0-9][a-z0-9._:-]{0,127}$') {
                        $finding = 'stop_reason_invalid'
                        break
                    }
                    if ($noActiveTurn -isnot [bool] -or -not [bool]$noActiveTurn) {
                        $finding = 'active_turn_present_or_unproved'
                        break
                    }
                    if (-not [string]::IsNullOrWhiteSpace($nextRetryAt)) {
                        $finding = 'retry_scheduled'
                        break
                    }
                    if ($externalEffectState -notin @('none', 'safe')) {
                        $finding = 'external_effect_state_unproved'
                        break
                    }
                    if ($receiptKey -notmatch '^watch-receipt:[0-9a-f]{64}$' -or
                        $checkpointId -notmatch '^watch-checkpoint:[0-9a-f]{64}$') {
                        $finding = 'stop_receipt_invalid'
                        break
                    }

                    $evidenceTimestamp = [datetimeoffset]::MinValue
                    if (-not [datetimeoffset]::TryParse($evidenceTimestampText, [ref]$evidenceTimestamp) -or
                        $evidenceTimestamp -gt $now.AddMinutes(1) -or
                        $evidenceTimestamp -lt $now.AddMinutes(-$FreshnessMinutes)) {
                        $finding = 'stop_evidence_stale'
                        break
                    }

                    $result.stopped_count++
                    $canonicalRows.Add(([ordered]@{
                        target_thread_id = $targetThreadId
                        automation_id = $targetAutomationId
                        source_turn_id = $sourceTurnId
                        state = $state
                        task_stopped = $true
                        stop_reason = $stopReason
                        recovery_pending = $false
                        checkpoint_id = $checkpointId
                        receipt_key = $receiptKey
                        evidence_timestamp_utc = $evidenceTimestamp.ToUniversalTime().ToString('o')
                        external_effect_state = $externalEffectState
                        next_retry_at = $nextRetryAt
                        no_active_turn = $true
                    } | ConvertTo-Json -Compress)) | Out-Null
                }

                if ($null -ne $finding) {
                    $result.reason_code = $finding
                }
                else {
                    $snapshotHash = Get-WatchFleetSha256 -Text ("supervisor_automation_id={0}`n{1}" -f $AutomationId, [string]::Join("`n", $canonicalRows.ToArray()))
                    $snapshotKey = 'watch-fleet-stopped:' + $snapshotHash
                    $shutdownReceiptKey = 'watch-fleet-shutdown:' + $snapshotHash
                    $result.snapshot_key = $snapshotKey
                    $result.shutdown_receipt_key = $shutdownReceiptKey

                    if ($PriorShutdownReceiptKey -ceq $shutdownReceiptKey) {
                        $result.reason_code = 'shutdown_already_scheduled'
                    }
                    elseif ($PreviousSnapshotKey -cne $snapshotKey) {
                        $result.reason_code = 'stability_confirmation_required'
                    }
                    elseif ([string]::IsNullOrWhiteSpace($PreviousTickId) -or
                            -not [datetimeoffset]::TryParse($PreviousTickId, [ref]$previousTick) -or
                            $previousTick -ge $currentTick) {
                        $result.reason_code = 'distinct_scheduled_tick_required'
                    }
                    else {
                        $result.power_action = 'schedule_shutdown'
                        $result.reason_code = 'all_monitored_tasks_stopped'
                        $result.shutdown_receipt_expires_at_utc = $now.AddSeconds($ShutdownReceiptTtlSeconds).ToString('o')
                        $result.requires_fresh_recheck = $true
                    }
                }
            }
        }
    }
}

$output = [pscustomobject]$result
if ($AsJson) {
    $output | ConvertTo-Json -Depth 8 -Compress
}
else {
    $output
}
