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

    [string]$StateRoot = '',
    [string]$StatePath = '',
    [string]$ConfirmedShutdownReceiptKey = '',

    [switch]$VisibilityComplete,
    [switch]$ListLimitReached,
    [switch]$GuardReady,

    [ValidateRange(0, 100000)]
    [int]$VisibleCount = 0,

    [ValidateRange(0, 100000)]
    [int]$EligibleCount = 0,

    [ValidateRange(0, 100000)]
    [int]$MonitoredCount = 0,

    [ValidateRange(0, 100000)]
    [int]$BlockingUnmonitoredCount = 0,

    [ValidateRange(0, 100000)]
    [int]$ConflictCount = 0,

    [ValidateRange(0, 100000)]
    [int]$UnknownCount = 0,

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
    [switch]$FinalRecheck,
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

function New-WatchFleetSupervisorState {
    param([Parameter(Mandatory = $true)][string]$AutomationId)

    return [ordered]@{
        schema_version = 2
        automation_id = $AutomationId
        current_tick_id = ''
        previous_tick_id = ''
        snapshot_key = ''
        observed_at = ''
        successful_shutdown_receipt_keys = @()
    }
}

function Read-WatchFleetSupervisorState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedAutomationId
    )

    if (-not [IO.File]::Exists($Path)) {
        return (New-WatchFleetSupervisorState -AutomationId $ExpectedAutomationId)
    }

    try {
        $state = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    }
    catch {
        throw 'state_json_invalid'
    }

    if ([int](Get-WatchFleetProperty $state 'schema_version') -ne 2) { throw 'state_schema_invalid' }
    $stateAutomationId = [string](Get-WatchFleetProperty $state 'automation_id')
    if ($stateAutomationId -cne $ExpectedAutomationId) { throw 'state_automation_mismatch' }
    foreach ($field in @('current_tick_id', 'previous_tick_id')) {
        $value = Get-WatchFleetProperty $state $field
        if ($null -eq $value -or
            ($value -isnot [string] -and $value -isnot [datetime] -and $value -isnot [datetimeoffset])) {
            throw 'state_schema_invalid'
        }
    }
    $snapshotValue = Get-WatchFleetProperty $state 'snapshot_key'
    if ($null -eq $snapshotValue -or $snapshotValue -isnot [string]) { throw 'state_schema_invalid' }
    $observedAtProperty = $state.PSObject.Properties['observed_at']
    $observedAtValue = if ($null -eq $observedAtProperty) { $null } else { $observedAtProperty.Value }
    if ($null -eq $observedAtProperty -or
        ($observedAtValue -isnot [string] -and $observedAtValue -isnot [datetime] -and $observedAtValue -isnot [datetimeoffset])) {
        throw 'state_schema_invalid'
    }

    $receiptProperty = $state.PSObject.Properties['successful_shutdown_receipt_keys']
    if ($null -eq $receiptProperty) { throw 'state_schema_invalid' }
    $receipts = @($receiptProperty.Value)
    $normalizedReceipts = [System.Collections.Generic.List[string]]::new()
    foreach ($receipt in @($receipts)) {
        $text = [string]$receipt
        if ($text -notmatch '^watch-fleet-shutdown:[0-9a-f]{64}$') { throw 'state_schema_invalid' }
        if (-not $normalizedReceipts.Contains($text)) { $normalizedReceipts.Add($text) | Out-Null }
    }

    return [ordered]@{
        schema_version = 2
        automation_id = $stateAutomationId
        current_tick_id = if ($state.current_tick_id -is [string]) { [string]$state.current_tick_id } else { ([datetimeoffset]$state.current_tick_id).ToUniversalTime().ToString('o') }
        previous_tick_id = if ($state.previous_tick_id -is [string]) { [string]$state.previous_tick_id } else { ([datetimeoffset]$state.previous_tick_id).ToUniversalTime().ToString('o') }
        snapshot_key = [string]$snapshotValue
        observed_at = if ($observedAtValue -is [string]) { [string]$observedAtValue } else { ([datetimeoffset]$observedAtValue).ToString('o') }
        successful_shutdown_receipt_keys = @($normalizedReceipts.ToArray())
    }
}

function Write-WatchFleetSupervisorState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$State
    )

    $parent = [IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) {
        throw 'state_parent_missing'
    }

    $tempPath = Join-Path $parent ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($Path), [guid]::NewGuid().ToString('N'))
    $backupPath = $tempPath + '.bak'
    try {
        $json = $State | ConvertTo-Json -Depth 10 -Compress
        [IO.File]::WriteAllText($tempPath, $json, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($tempPath, $Path, $backupPath)
        }
        else {
            [IO.File]::Move($tempPath, $Path)
        }
    }
    finally {
        if ([IO.File]::Exists($tempPath)) { [IO.File]::Delete($tempPath) }
        if ([IO.File]::Exists($backupPath)) { [IO.File]::Delete($backupPath) }
    }
}

function Test-WatchFleetStatePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not [IO.Path]::IsPathRooted($Root) -or -not [IO.Directory]::Exists($Root)) {
        return 'state_root_invalid'
    }
    if (-not [IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetExtension($Path) -ne '.json') {
        return 'state_path_invalid'
    }

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $pathFull = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $pathFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return 'state_path_outside_root'
    }

    $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($pathFull))
    while ($null -ne $cursor -and $cursor.FullName.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        if ($cursor.Exists -and (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            return 'state_path_reparse_unsafe'
        }
        if ([string]::Equals($cursor.FullName.TrimEnd('\', '/'), $rootFull, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $cursor.Parent
    }
    if ([IO.File]::Exists($pathFull) -and (([IO.File]::GetAttributes($pathFull) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        return 'state_path_reparse_unsafe'
    }
    return ''
}

$result = [ordered]@{
    schema_version = 3
    automation_id = $AutomationId
    current_tick_id = $CurrentTickId
    previous_tick_id = ''
    power_action = 'observe_only'
    reason_code = 'shutdown_not_armed'
    visibility_complete = [bool]$VisibilityComplete
    list_limit_reached = [bool]$ListLimitReached
    visible_count = $VisibleCount
    eligible_count = $EligibleCount
    monitored_count = $MonitoredCount
    blocking_unmonitored_count = $BlockingUnmonitoredCount
    conflict_count = $ConflictCount
    unknown_count = $UnknownCount
    stopped_count = 0
    tick_id = $CurrentTickId
    snapshot_key = ''
    shutdown_receipt_key = ''
    successful_shutdown_receipt_count = 0
    state_error_type = ''
    state_root = $StateRoot
    state_path = $StatePath
    shutdown_receipt_expires_at_utc = ''
    shutdown_delay_seconds = $ShutdownDelaySeconds
    remaining_target_heartbeat_count = $RemainingTargetHeartbeatCount
    unmonitored_active_task_count = $UnmonitoredActiveTaskCount
    requires_fresh_recheck = $true
}

$statePathFull = ''
if ($ShutdownArmed) {
    $now = [datetimeoffset]::UtcNow
    $currentTick = [datetimeoffset]::MinValue
    $callerPreviousTick = [datetimeoffset]::MinValue
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
    elseif (-not [string]::IsNullOrWhiteSpace($PreviousTickId) -and
            -not [datetimeoffset]::TryParse($PreviousTickId, [ref]$callerPreviousTick)) {
        $result.reason_code = 'previous_tick_invalid'
    }
    elseif (-not $GuardReady) {
        $result.reason_code = 'guard_not_ready'
    }
    elseif ($ListLimitReached) {
        $result.reason_code = 'visibility_truncated'
    }
    elseif ([string]::IsNullOrWhiteSpace($StateRoot)) {
        $result.reason_code = 'state_root_invalid'
    }
    elseif (-not [string]::IsNullOrWhiteSpace(($statePathFinding = Test-WatchFleetStatePath -Root $StateRoot -Path $StatePath))) {
        $result.reason_code = $statePathFinding
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PriorShutdownReceiptKey) -and $PriorShutdownReceiptKey -notmatch '^watch-fleet-shutdown:[0-9a-f]{64}$') {
        $result.reason_code = 'prior_receipt_invalid'
    }
    else {
        $canonicalCurrentTickId = $currentTick.ToUniversalTime().ToString('o')
        $canonicalPreviousTickId = if ([string]::IsNullOrWhiteSpace($PreviousTickId)) { '' } else { $callerPreviousTick.ToUniversalTime().ToString('o') }
        $result.current_tick_id = $canonicalCurrentTickId
        $result.tick_id = $canonicalCurrentTickId
        try {
            $parsed = $SnapshotJson | ConvertFrom-Json -Depth 20 -ErrorAction Stop
            $records = @($parsed)
        }
        catch {
            $records = @()
            $result.reason_code = 'snapshot_json_invalid'
        }

        if ($result.reason_code -ne 'snapshot_json_invalid') {
            if ($records.Count -eq 0) {
                $result.reason_code = 'monitored_set_empty'
            }
            elseif ($VisibleCount -lt $EligibleCount -or
                $EligibleCount -ne $records.Count -or
                $MonitoredCount -ne $records.Count -or
                $BlockingUnmonitoredCount -ne 0 -or
                $ConflictCount -ne 0 -or
                $UnknownCount -ne 0) {
                $result.reason_code = 'visibility_incomplete'
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

                    $statePathFull = [IO.Path]::GetFullPath($StatePath)
                    $lockPath = $statePathFull + '.lock'
                    $lockStream = $null
                    try {
                        try {
                            $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                        }
                        catch [IO.IOException] {
                            $result.reason_code = 'state_lock_busy'
                        }

                        if ($null -ne $lockStream) {
                            try {
                                $supervisorState = Read-WatchFleetSupervisorState -Path $statePathFull -ExpectedAutomationId $AutomationId
                                $result.previous_tick_id = [string]$supervisorState.current_tick_id
                                $receiptSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                                foreach ($receipt in @($supervisorState.successful_shutdown_receipt_keys)) { $receiptSet.Add([string]$receipt) | Out-Null }

                                if (-not [string]::IsNullOrWhiteSpace($ConfirmedShutdownReceiptKey)) {
                                    if ($ConfirmedShutdownReceiptKey -cne $shutdownReceiptKey) {
                                        $result.reason_code = 'confirmed_receipt_mismatch'
                                    }
                                    else {
                                        $receiptSet.Add($ConfirmedShutdownReceiptKey) | Out-Null
                                        $supervisorState.successful_shutdown_receipt_keys = @($receiptSet | Sort-Object)
                                        Write-WatchFleetSupervisorState -Path $statePathFull -State $supervisorState
                                        $result.reason_code = 'shutdown_receipt_recorded'
                                    }
                                }
                                elseif (-not [string]::IsNullOrWhiteSpace($PriorShutdownReceiptKey) -and
                                        $PriorShutdownReceiptKey -cne $shutdownReceiptKey) {
                                    $result.reason_code = 'prior_receipt_mismatch'
                                }
                                elseif ($receiptSet.Contains($shutdownReceiptKey) -or
                                        $PriorShutdownReceiptKey -ceq $shutdownReceiptKey) {
                                    $result.reason_code = 'shutdown_already_scheduled'
                                }
                                elseif ($FinalRecheck) {
                                    if ([string]$supervisorState.current_tick_id -cne $canonicalCurrentTickId -or
                                        [string]$supervisorState.snapshot_key -cne $snapshotKey) {
                                        $result.reason_code = 'final_recheck_state_mismatch'
                                    }
                                    else {
                                        $result.power_action = 'schedule_shutdown'
                                        $result.reason_code = 'all_monitored_tasks_stopped'
                                        $result.shutdown_receipt_expires_at_utc = $now.AddSeconds($ShutdownReceiptTtlSeconds).ToString('o')
                                    }
                                }
                                elseif ([string]$supervisorState.current_tick_id -ceq $canonicalCurrentTickId) {
                                    $result.reason_code = 'tick_already_evaluated'
                                }
                                else {
                                    if ((-not [string]::IsNullOrWhiteSpace($canonicalPreviousTickId) -and
                                            $canonicalPreviousTickId -cne [string]$supervisorState.current_tick_id) -or
                                        (-not [string]::IsNullOrWhiteSpace($PreviousSnapshotKey) -and
                                            $PreviousSnapshotKey -cne [string]$supervisorState.snapshot_key)) {
                                        $result.reason_code = 'caller_state_mismatch'
                                    }
                                    else {
                                        $previousTickText = [string]$supervisorState.current_tick_id
                                        $persistedPreviousTick = [datetimeoffset]::MinValue
                                        $stableAcrossDistinctTicks = -not [string]::IsNullOrWhiteSpace($previousTickText) -and
                                            [string]$supervisorState.snapshot_key -ceq $snapshotKey -and
                                            [datetimeoffset]::TryParse($previousTickText, [ref]$persistedPreviousTick) -and
                                            $persistedPreviousTick -lt $currentTick

                                        $supervisorState.previous_tick_id = $previousTickText
                                        $supervisorState.current_tick_id = $canonicalCurrentTickId
                                        $supervisorState.snapshot_key = $snapshotKey
                                        $supervisorState.observed_at = $now.ToString('o')
                                        $supervisorState.successful_shutdown_receipt_keys = @($receiptSet | Sort-Object)
                                        Write-WatchFleetSupervisorState -Path $statePathFull -State $supervisorState

                                        if (-not $stableAcrossDistinctTicks) {
                                            $result.reason_code = 'stability_confirmation_required'
                                        }
                                        else {
                                            $result.power_action = 'schedule_shutdown'
                                            $result.reason_code = 'all_monitored_tasks_stopped'
                                            $result.shutdown_receipt_expires_at_utc = $now.AddSeconds($ShutdownReceiptTtlSeconds).ToString('o')
                                        }
                                    }
                                }

                                $result.successful_shutdown_receipt_count = $receiptSet.Count
                            }
                            catch {
                                $reason = [string]$_.Exception.Message
                                $stateException = $_.Exception
                                $result.state_error_type = if ($null -ne $stateException.InnerException) { $stateException.InnerException.GetType().FullName } else { $stateException.GetType().FullName }
                                $result.reason_code = if ($reason -match '^state_[a-z_]+$') { $reason } else { 'state_update_failed' }
                            }
                        }
                    }
                    finally {
                        if ($null -ne $lockStream) {
                            $lockStream.Dispose()
                            if ([IO.File]::Exists($lockPath)) { [IO.File]::Delete($lockPath) }
                        }
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
