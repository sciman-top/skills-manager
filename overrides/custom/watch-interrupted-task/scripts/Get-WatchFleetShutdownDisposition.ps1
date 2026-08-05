[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SnapshotJson,

    [string]$StateRoot = '',
    [string]$StatePath = '',
    [string]$TickId = '',
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

    [string]$PreviousSnapshotKey = '',
    [string]$PriorShutdownReceiptKey = '',

    [string]$NowUtc = ([datetimeoffset]::UtcNow.ToString('o')),

    [ValidateRange(1, 60)]
    [int]$FreshnessMinutes = 15,

    [ValidateRange(30, 3600)]
    [int]$ShutdownDelaySeconds = 120,

    [switch]$ShutdownArmed,
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
    return [ordered]@{
        schema_version = 1
        current_tick_id = ''
        previous_tick_id = ''
        snapshot_key = ''
        observed_at = ''
        successful_shutdown_receipt_keys = @()
    }
}

function Read-WatchFleetSupervisorState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [IO.File]::Exists($Path)) {
        return (New-WatchFleetSupervisorState)
    }

    try {
        $state = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    }
    catch {
        throw 'state_json_invalid'
    }

    if ([int](Get-WatchFleetProperty $state 'schema_version') -ne 1) { throw 'state_schema_invalid' }
    foreach ($field in @('current_tick_id', 'previous_tick_id', 'snapshot_key')) {
        $value = Get-WatchFleetProperty $state $field
        if ($null -eq $value -or $value -isnot [string]) { throw 'state_schema_invalid' }
    }
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
        schema_version = 1
        current_tick_id = [string]$state.current_tick_id
        previous_tick_id = [string]$state.previous_tick_id
        snapshot_key = [string]$state.snapshot_key
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
    tick_id = $TickId
    previous_tick_id = ''
    snapshot_key = ''
    shutdown_receipt_key = ''
    successful_shutdown_receipt_count = 0
    state_error_type = ''
    state_root = $StateRoot
    state_path = $StatePath
    shutdown_delay_seconds = $ShutdownDelaySeconds
    requires_fresh_recheck = $true
}

$statePathFull = ''
if ($ShutdownArmed) {
    $now = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($NowUtc, [ref]$now)) {
        $result.reason_code = 'evaluation_time_invalid'
    }
    elseif (-not $GuardReady) {
        $result.reason_code = 'guard_not_ready'
    }
    elseif ($ListLimitReached) {
        $result.reason_code = 'visibility_truncated'
    }
    elseif (-not $VisibilityComplete) {
        $result.reason_code = 'visibility_incomplete'
    }
    elseif ([string]::IsNullOrWhiteSpace($StateRoot)) {
        $result.reason_code = 'state_root_invalid'
    }
    elseif (-not [string]::IsNullOrWhiteSpace(($statePathFinding = Test-WatchFleetStatePath -Root $StateRoot -Path $StatePath))) {
        $result.reason_code = $statePathFinding
    }
    elseif ([string]::IsNullOrWhiteSpace($TickId) -or $TickId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') {
        $result.reason_code = 'tick_identity_invalid'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PriorShutdownReceiptKey) -and $PriorShutdownReceiptKey -notmatch '^watch-fleet-shutdown:[0-9a-f]{64}$') {
        $result.reason_code = 'prior_receipt_invalid'
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
                $canonicalRows = [System.Collections.Generic.List[string]]::new()
                $finding = $null

                foreach ($record in @($records | Sort-Object { [string](Get-WatchFleetProperty $_ 'target_thread_id') })) {
                    $targetThreadId = [string](Get-WatchFleetProperty $record 'target_thread_id')
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
                    if ($state -eq 'running') { $finding = 'target_running'; break }
                    if ($state -in $recoveryOrRetryStates) { $finding = 'recovery_or_retry_pending'; break }
                    if ($state -in $unprovedStates -or [string]::IsNullOrWhiteSpace($state)) { $finding = 'target_state_unproved'; break }
                    if ($recoveryPending -isnot [bool]) { $finding = 'recovery_status_unproved'; break }
                    if ([bool]$recoveryPending) { $finding = 'recovery_or_retry_pending'; break }
                    if ($taskStopped -isnot [bool] -or -not [bool]$taskStopped) { $finding = 'stop_decision_unproved'; break }
                    if ([string]::IsNullOrWhiteSpace($stopReason) -or $stopReason -notmatch '^[a-z0-9][a-z0-9._:-]{0,127}$') { $finding = 'stop_reason_invalid'; break }
                    if ($noActiveTurn -isnot [bool] -or -not [bool]$noActiveTurn) { $finding = 'active_turn_present_or_unproved'; break }
                    if (-not [string]::IsNullOrWhiteSpace($nextRetryAt)) { $finding = 'retry_scheduled'; break }
                    if ($externalEffectState -notin @('none', 'safe')) { $finding = 'external_effect_state_unproved'; break }
                    if ([string]::IsNullOrWhiteSpace($receiptKey) -or [string]::IsNullOrWhiteSpace($checkpointId)) { $finding = 'stop_receipt_incomplete'; break }

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
                        state = $state
                        task_stopped = $true
                        stop_reason = $stopReason
                        recovery_pending = $false
                        checkpoint_id = $checkpointId
                        receipt_key = $receiptKey
                    } | ConvertTo-Json -Compress)) | Out-Null
                }

                if ($null -ne $finding) {
                    $result.reason_code = $finding
                }
                else {
                    $snapshotHash = Get-WatchFleetSha256 -Text ([string]::Join("`n", $canonicalRows.ToArray()))
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
                                $supervisorState = Read-WatchFleetSupervisorState -Path $statePathFull
                                $result.previous_tick_id = [string]$supervisorState.current_tick_id
                                $receiptSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                                foreach ($receipt in @($supervisorState.successful_shutdown_receipt_keys)) { $receiptSet.Add([string]$receipt) | Out-Null }

                                if (-not [string]::IsNullOrWhiteSpace($PriorShutdownReceiptKey)) {
                                    $receiptSet.Add($PriorShutdownReceiptKey) | Out-Null
                                }
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
                                elseif ([string]$supervisorState.current_tick_id -ceq $TickId) {
                                    $result.reason_code = 'tick_already_evaluated'
                                }
                                else {
                                    $stableAcrossDistinctTicks = -not [string]::IsNullOrWhiteSpace([string]$supervisorState.current_tick_id) -and
                                        [string]$supervisorState.snapshot_key -ceq $snapshotKey

                                    $previousTick = [string]$supervisorState.current_tick_id
                                    $supervisorState.previous_tick_id = $previousTick
                                    $supervisorState.current_tick_id = $TickId
                                    $supervisorState.snapshot_key = $snapshotKey
                                    $supervisorState.observed_at = $now.ToString('o')
                                    $supervisorState.successful_shutdown_receipt_keys = @($receiptSet | Sort-Object)
                                    Write-WatchFleetSupervisorState -Path $statePathFull -State $supervisorState

                                    if ($receiptSet.Contains($shutdownReceiptKey)) {
                                        $result.reason_code = 'shutdown_already_scheduled'
                                    }
                                    elseif (-not $stableAcrossDistinctTicks) {
                                        $result.reason_code = 'stability_confirmation_required'
                                    }
                                    else {
                                        $result.power_action = 'schedule_shutdown'
                                        $result.reason_code = 'all_visible_eligible_tasks_stopped'
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
