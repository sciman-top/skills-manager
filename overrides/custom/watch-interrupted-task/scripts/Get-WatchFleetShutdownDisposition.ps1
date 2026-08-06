[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SnapshotJson,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$')][string]$AutomationId,
    [Parameter(Mandatory = $true)][string]$CurrentTickId,
    [string]$PreviousTickId = '',
    [string]$PreviousSnapshotKey = '',
    [string]$PriorShutdownReceiptKey = '',
    [ValidatePattern('^$|^watch-fleet-shutdown:[0-9a-f]{64}$')][string]$ConfirmedShutdownReceiptKey = '',
    [ValidatePattern('^$|^watch-runtime-generation:[0-9a-f]{64}$')][string]$WatchRuntimeGenerationId = '',
    [string]$StateRoot = '',
    [string]$StatePath = '',
    [AllowEmptyString()][string]$MembershipJson = '',
    [switch]$VisibilityComplete,
    [switch]$ListLimitReached,
    [switch]$GuardReady,
    [ValidateRange(0, 100000)][int]$VisibleCount = 0,
    [ValidateRange(0, 100000)][int]$EligibleCount = 0,
    [ValidateRange(0, 100000)][int]$MonitoredCount = 0,
    [ValidateRange(0, 100000)][int]$BlockingUnmonitoredCount = 0,
    [ValidateRange(0, 100000)][int]$ConflictCount = 0,
    [ValidateRange(0, 100000)][int]$UnknownCount = 0,
    [ValidateRange(0, 1000)][int]$UnavailableHostCount = 0,
    [ValidateRange(0, 1000)][int]$UnavailableSourceCount = 0,
    [ValidateRange(1, 60)][int]$FreshnessMinutes = 15,
    [ValidateRange(30, 3600)][int]$ShutdownDelaySeconds = 120,
    [ValidateRange(30, 300)][int]$ShutdownReceiptTtlSeconds = 120,
    [ValidateRange(0, 1000)][int]$RemainingTargetHeartbeatCount = 0,
    [ValidateRange(0, 1000)][int]$UnmonitoredActiveTaskCount = 0,
    [switch]$ShutdownArmed,
    [switch]$FinalRecheck,
    [switch]$ConfirmSupervisorDeleted,
    [string]$AutomationRoot = '',
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')
$effectiveGenerationId = if ([string]::IsNullOrWhiteSpace($WatchRuntimeGenerationId)) { Get-WatchRuntimeGenerationId -CommittedOnly } else { $WatchRuntimeGenerationId }

function Get-WatchFleetProperty {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [Collections.IDictionary] -and $InputObject.Contains($Name)) { return $InputObject[$Name] }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-WatchFleetSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-WatchFleetTimestampText {
    param([AllowNull()][object]$Value)
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).ToUniversalTime().ToString('o') }
    if ($Value -is [datetime]) { return ([datetimeoffset]([datetime]$Value)).ToUniversalTime().ToString('o') }
    return [string]$Value
}

function New-WatchFleetSupervisorState {
    param([string]$ExpectedAutomationId, [string]$ExpectedGenerationId)
    return [ordered]@{
        schema_version = 4
        automation_id = $ExpectedAutomationId
        watch_runtime_generation_id = $ExpectedGenerationId
        membership_epoch = 0
        current_tick_id = ''
        previous_tick_id = ''
        snapshot_key = ''
        observed_at = ''
        membership = @()
        candidate = $null
        successful_shutdown_receipt_keys = @()
    }
}

function ConvertTo-WatchFleetMember {
    param([Parameter(Mandatory = $true)][object]$Member)
    return [pscustomobject][ordered]@{
        target_thread_id = [string](Get-WatchFleetProperty $Member 'target_thread_id')
        automation_id = [string](Get-WatchFleetProperty $Member 'automation_id')
        source_turn_id = [string](Get-WatchFleetProperty $Member 'source_turn_id')
        last_stop_receipt_key = [string](Get-WatchFleetProperty $Member 'last_stop_receipt_key')
        last_notification_receipt_key = [string](Get-WatchFleetProperty $Member 'last_notification_receipt_key')
        last_cleanup_receipt_key = [string](Get-WatchFleetProperty $Member 'last_cleanup_receipt_key')
        last_checkpoint_id = [string](Get-WatchFleetProperty $Member 'last_checkpoint_id')
        last_stop_reason = [string](Get-WatchFleetProperty $Member 'last_stop_reason')
        last_evidence_timestamp_utc = [string](Get-WatchFleetProperty $Member 'last_evidence_timestamp_utc')
    }
}

function Read-WatchFleetSupervisorState {
    param([string]$Path, [string]$ExpectedAutomationId, [string]$ExpectedGenerationId)
    if (-not [IO.File]::Exists($Path)) { return (New-WatchFleetSupervisorState $ExpectedAutomationId $ExpectedGenerationId) }
    try { $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -Depth 20 -ErrorAction Stop }
    catch { throw 'state_json_invalid' }

    $schema = [int](Get-WatchFleetProperty $raw 'schema_version')
    if ($schema -notin @(2, 3, 4)) { throw 'state_schema_invalid' }
    if ([string](Get-WatchFleetProperty $raw 'automation_id') -cne $ExpectedAutomationId) { throw 'state_automation_mismatch' }
    $generation = if ($schema -eq 2) { $ExpectedGenerationId } else { [string](Get-WatchFleetProperty $raw 'watch_runtime_generation_id') }
    if ($generation -cne $ExpectedGenerationId) { throw 'state_generation_mismatch' }

    $members = [System.Collections.Generic.List[object]]::new()
    foreach ($member in @((Get-WatchFleetProperty $raw 'membership'))) {
        $normalized = ConvertTo-WatchFleetMember $member
        if ($normalized.target_thread_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or
            $normalized.automation_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or
            $normalized.source_turn_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') { throw 'state_schema_invalid' }
        $members.Add($normalized) | Out-Null
    }

    $receipts = [System.Collections.Generic.List[string]]::new()
    foreach ($receipt in @((Get-WatchFleetProperty $raw 'successful_shutdown_receipt_keys'))) {
        $text = [string]$receipt
        if ($text -notmatch '^watch-fleet-shutdown:[0-9a-f]{64}$') { throw 'state_schema_invalid' }
        if (-not $receipts.Contains($text)) { $receipts.Add($text) | Out-Null }
    }

    return [ordered]@{
        schema_version = 4
        automation_id = $ExpectedAutomationId
        watch_runtime_generation_id = $generation
        membership_epoch = if ($schema -eq 4) { [int](Get-WatchFleetProperty $raw 'membership_epoch') } else { 0 }
        current_tick_id = ConvertTo-WatchFleetTimestampText (Get-WatchFleetProperty $raw 'current_tick_id')
        previous_tick_id = ConvertTo-WatchFleetTimestampText (Get-WatchFleetProperty $raw 'previous_tick_id')
        snapshot_key = [string](Get-WatchFleetProperty $raw 'snapshot_key')
        observed_at = [string](Get-WatchFleetProperty $raw 'observed_at')
        membership = @($members.ToArray())
        candidate = if ($schema -eq 4) { Get-WatchFleetProperty $raw 'candidate' } else { $null }
        successful_shutdown_receipt_keys = @($receipts.ToArray())
    }
}

function Write-WatchFleetSupervisorState {
    param([string]$Path, [object]$State)
    $parent = [IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not [IO.Directory]::Exists($parent)) { throw 'state_parent_missing' }
    $temp = Join-Path $parent ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($Path), [guid]::NewGuid().ToString('N'))
    $backup = $temp + '.bak'
    try {
        [IO.File]::WriteAllText($temp, ($State | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, $backup) } else { [IO.File]::Move($temp, $Path) }
    }
    finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}

function Test-WatchFleetStatePath {
    param([string]$Root, [string]$Path)
    if (-not [IO.Path]::IsPathRooted($Root) -or -not [IO.Directory]::Exists($Root)) { return 'state_root_invalid' }
    if (-not [IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetExtension($Path) -ne '.json') { return 'state_path_invalid' }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return 'state_path_outside_root' }
    $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($pathFull))
    while ($null -ne $cursor -and $cursor.FullName.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        if ($cursor.Exists -and (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return 'state_path_reparse_unsafe' }
        if ([string]::Equals($cursor.FullName.TrimEnd('\', '/'), $rootFull, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $cursor.Parent
    }
    if ([IO.File]::Exists($pathFull) -and (([IO.File]::GetAttributes($pathFull) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return 'state_path_reparse_unsafe' }
    return ''
}

function Reset-WatchFleetCandidate {
    param([Parameter(Mandatory = $true)][Collections.IDictionary]$State)
    $State.previous_tick_id = ''
    $State.current_tick_id = ''
    $State.snapshot_key = ''
    $State.candidate = $null
}

function Test-WatchSupervisorAutomationAbsent {
    param([Parameter(Mandatory = $true)][string]$Root,[Parameter(Mandatory = $true)][string]$ExpectedAutomationId)
    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $fullRoot = [IO.Path]::GetFullPath($Root)
        $metadataPath = [IO.Path]::GetFullPath((Join-Path (Join-Path $fullRoot $ExpectedAutomationId) 'automation.toml'))
        if (-not $metadataPath.StartsWith($fullRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { return $false }
        return -not [IO.File]::Exists($metadataPath)
    }
    catch { return $false }
}

function ConvertTo-WatchFleetMembershipRows {
    param([Parameter(Mandatory = $true)][object[]]$Rows)
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $automationIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $result = [Collections.Generic.List[object]]::new()
    foreach ($row in @($Rows | Sort-Object { [string](Get-WatchFleetProperty $_ 'target_thread_id') })) {
        $member = ConvertTo-WatchFleetMember $row
        if ($member.target_thread_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or -not $ids.Add($member.target_thread_id) -or
            $member.automation_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or -not $automationIds.Add($member.automation_id) -or
            $member.source_turn_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') { throw 'membership_identity_invalid' }
        $result.Add($member) | Out-Null
    }
    if ($result.Count -eq 0) { throw 'membership_empty' }
    return @($result.ToArray())
}

function Update-WatchFleetMembershipOnly {
    param(
        [string]$Path,
        [string]$ExpectedAutomationId,
        [string]$ExpectedGenerationId,
        [Parameter(Mandatory = $true)][object[]]$Incoming,
        [datetimeoffset]$ObservedAt
    )

    $lockPath = $Path + '.lock'
    $lock = $null
    try {
        try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) }
        catch [IO.IOException] { return [pscustomobject]@{ reason_code='state_lock_busy'; membership_count=0; membership_epoch=0 } }
        $state = Read-WatchFleetSupervisorState $Path $ExpectedAutomationId $ExpectedGenerationId
        $existing = @{}
        foreach ($member in @($state.membership)) { $existing[[string]$member.target_thread_id] = $member }
        $incomingById = @{}
        foreach ($member in @($Incoming)) { $incomingById[[string]$member.target_thread_id] = $member }
        if (@($existing.Keys | Where-Object { -not $incomingById.ContainsKey($_) }).Count -gt 0) {
            Reset-WatchFleetCandidate $state
            $state.observed_at = $ObservedAt.ToString('o')
            Write-WatchFleetSupervisorState $Path $state
            return [pscustomobject]@{ reason_code='membership_shrink_detected'; membership_count=$state.membership.Count; membership_epoch=[int]$state.membership_epoch }
        }
        $changed = $false
        foreach ($id in @($incomingById.Keys)) {
            $member = $incomingById[$id]
            if ($existing.ContainsKey($id)) {
                if ([string]$existing[$id].automation_id -cne [string]$member.automation_id -or [string]$existing[$id].source_turn_id -cne [string]$member.source_turn_id) { throw 'membership_identity_conflict' }
            }
            else { $existing[$id] = $member; $changed = $true }
        }
        if ($changed) { $state.membership_epoch = [int]$state.membership_epoch + 1; Reset-WatchFleetCandidate $state }
        $state.membership = @($existing.Keys | Sort-Object | ForEach-Object { ConvertTo-WatchFleetMember $existing[$_] })
        $state.observed_at = $ObservedAt.ToString('o')
        Write-WatchFleetSupervisorState $Path $state
        return [pscustomobject]@{ reason_code=''; membership_count=$state.membership.Count; membership_epoch=[int]$state.membership_epoch }
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose(); if ([IO.File]::Exists($lockPath)) { [IO.File]::Delete($lockPath) } }
    }
}

$result = [ordered]@{
    schema_version = 4
    automation_id = $AutomationId
    watch_runtime_generation_id = $effectiveGenerationId
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
    unavailable_host_count = $UnavailableHostCount
    unavailable_source_count = $UnavailableSourceCount
    stopped_count = 0
    tick_id = $CurrentTickId
    snapshot_key = ''
    shutdown_receipt_key = ''
    supervisor_delete_receipt_key = ''
    candidate_receipt_key = ''
    candidate_receipt_expires_at_utc = ''
    successful_shutdown_receipt_count = 0
    state_error_type = ''
    state_root = $StateRoot
    state_path = $StatePath
    shutdown_receipt_expires_at_utc = ''
    shutdown_delay_seconds = $ShutdownDelaySeconds
    remaining_target_heartbeat_count = $RemainingTargetHeartbeatCount
    unmonitored_active_task_count = $UnmonitoredActiveTaskCount
    requires_fresh_recheck = $true
    membership_count = 0
    membership_epoch = 0
}

if ($ShutdownArmed) {
    $now = [datetimeoffset]::UtcNow
    $currentTick = [datetimeoffset]::MinValue
    $callerPreviousTick = [datetimeoffset]::MinValue
    $pathFinding = if ([string]::IsNullOrWhiteSpace($StateRoot)) { 'state_root_invalid' } else { Test-WatchFleetStatePath $StateRoot $StatePath }
    if (-not $VisibilityComplete) { $result.reason_code = 'visibility_unproved' }
    elseif ($UnmonitoredActiveTaskCount -ne 0) { $result.reason_code = 'unmonitored_active_tasks' }
    elseif ($RemainingTargetHeartbeatCount -ne 0) { $result.reason_code = 'target_heartbeats_remain' }
    elseif ($UnavailableHostCount -ne 0) { $result.reason_code = 'host_visibility_unavailable' }
    elseif ($UnavailableSourceCount -ne 0) { $result.reason_code = 'source_visibility_unavailable' }
    elseif (-not [datetimeoffset]::TryParse($CurrentTickId, [ref]$currentTick)) { $result.reason_code = 'current_tick_invalid' }
    elseif ($currentTick -gt $now.AddMinutes(1) -or $currentTick -lt $now.AddMinutes(-$FreshnessMinutes)) { $result.reason_code = 'current_tick_stale' }
    elseif (-not [string]::IsNullOrWhiteSpace($PreviousTickId) -and -not [datetimeoffset]::TryParse($PreviousTickId, [ref]$callerPreviousTick)) { $result.reason_code = 'previous_tick_invalid' }
    elseif (-not $GuardReady) { $result.reason_code = 'guard_not_ready' }
    elseif (-not [string]::IsNullOrWhiteSpace($pathFinding)) { $result.reason_code = $pathFinding }
    elseif (-not [string]::IsNullOrWhiteSpace($PriorShutdownReceiptKey) -and $PriorShutdownReceiptKey -notmatch '^watch-fleet-shutdown:[0-9a-f]{64}$') { $result.reason_code = 'prior_receipt_invalid' }
    else {
        $canonicalCurrentTick = $currentTick.ToUniversalTime().ToString('o')
        $canonicalCallerPreviousTick = if ([string]::IsNullOrWhiteSpace($PreviousTickId)) { '' } else { $callerPreviousTick.ToUniversalTime().ToString('o') }
        $result.current_tick_id = $canonicalCurrentTick
        $result.tick_id = $canonicalCurrentTick

        if (-not [string]::IsNullOrWhiteSpace($MembershipJson)) {
            try {
                $membershipRows = ConvertTo-WatchFleetMembershipRows @($MembershipJson | ConvertFrom-Json -Depth 20 -ErrorAction Stop)
                $membershipUpdate = Update-WatchFleetMembershipOnly -Path ([IO.Path]::GetFullPath($StatePath)) -ExpectedAutomationId $AutomationId -ExpectedGenerationId $effectiveGenerationId -Incoming $membershipRows -ObservedAt $now
                $result.membership_count = $membershipUpdate.membership_count
                $result.membership_epoch = $membershipUpdate.membership_epoch
                if (-not [string]::IsNullOrWhiteSpace($membershipUpdate.reason_code)) { $result.reason_code = $membershipUpdate.reason_code }
            }
            catch {
                $membershipMessage = [string]$_.Exception.Message
                $result.reason_code = if ($membershipMessage -match '^membership_[a-z_]+$') { $membershipMessage } else { 'membership_json_invalid' }
            }
        }

        try { $records = @($SnapshotJson | ConvertFrom-Json -Depth 20 -ErrorAction Stop) }
        catch { $records = @(); if ($result.reason_code -eq 'shutdown_not_armed') { $result.reason_code = 'snapshot_json_invalid' } }
        if ($result.reason_code -eq 'shutdown_not_armed') {
            if ($records.Count -eq 0) { $result.reason_code = 'monitored_set_empty' }
            elseif ($VisibleCount -lt $EligibleCount -or $EligibleCount -ne $records.Count -or $MonitoredCount -ne $records.Count -or
                $BlockingUnmonitoredCount -ne 0 -or $ConflictCount -ne 0 -or $UnknownCount -ne 0) { $result.reason_code = 'visibility_incomplete' }
        }

        $canonicalRows = [Collections.Generic.List[string]]::new()
        $receiptRows = [Collections.Generic.List[object]]::new()
        $recordMembers = [Collections.Generic.List[object]]::new()
        if ($result.reason_code -eq 'shutdown_not_armed') {
            $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $automationIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $recoveryStates = @('resume_eligible','continuation_gap','recoverable_task_failure','strategy_drift','verification_failed','peer_busy','stale_policy_running')
            $unprovedStates = @('unknown','soft_guard_only','goal_satisfied')
            foreach ($record in @($records | Sort-Object { [string](Get-WatchFleetProperty $_ 'target_thread_id') })) {
                $targetId = [string](Get-WatchFleetProperty $record 'target_thread_id')
                $targetAutomation = [string](Get-WatchFleetProperty $record 'automation_id')
                $sourceTurn = [string](Get-WatchFleetProperty $record 'source_turn_id')
                $state = [string](Get-WatchFleetProperty $record 'state')
                $taskStopped = Get-WatchFleetProperty $record 'task_stopped'
                $stopReason = [string](Get-WatchFleetProperty $record 'stop_reason')
                $recoveryPending = Get-WatchFleetProperty $record 'recovery_pending'
                $receipt = [string](Get-WatchFleetProperty $record 'receipt_key')
                $checkpoint = [string](Get-WatchFleetProperty $record 'checkpoint_id')
                $notificationReceipt = [string](Get-WatchFleetProperty $record 'notification_receipt_key')
                $cleanupReceipt = [string](Get-WatchFleetProperty $record 'cleanup_receipt_key')
                $evidenceText = [string](Get-WatchFleetProperty $record 'evidence_timestamp_utc')
                $external = [string](Get-WatchFleetProperty $record 'external_effect_state')
                $retry = [string](Get-WatchFleetProperty $record 'next_retry_at')
                $noActive = Get-WatchFleetProperty $record 'no_active_turn'
                $finding = ''
                if ($targetId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or -not $ids.Add($targetId)) { $finding = 'target_identity_invalid' }
                elseif ($targetAutomation -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -or -not $automationIds.Add($targetAutomation) -or $sourceTurn -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') { $finding = 'target_provenance_invalid' }
                elseif ($state -eq 'running') { $finding = 'target_running' }
                elseif ($state -in $recoveryStates -or [bool]$recoveryPending) { $finding = 'recovery_or_retry_pending' }
                elseif ($state -in $unprovedStates -or [string]::IsNullOrWhiteSpace($state)) { $finding = 'target_state_unproved' }
                elseif ($recoveryPending -isnot [bool]) { $finding = 'recovery_status_unproved' }
                elseif ($taskStopped -isnot [bool] -or -not [bool]$taskStopped) { $finding = 'stop_decision_unproved' }
                elseif ($stopReason -notmatch '^[a-z0-9][a-z0-9._:-]{0,127}$') { $finding = 'stop_reason_invalid' }
                elseif ($noActive -isnot [bool] -or -not [bool]$noActive) { $finding = 'active_turn_present_or_unproved' }
                elseif (-not [string]::IsNullOrWhiteSpace($retry)) { $finding = 'retry_scheduled' }
                elseif ($external -notin @('none','safe')) { $finding = 'external_effect_state_unproved' }
                elseif ($receipt -notmatch '^watch-receipt:[0-9a-f]{64}$' -or $checkpoint -notmatch '^watch-checkpoint:[0-9a-f]{64}$') { $finding = 'stop_receipt_invalid' }
                elseif (-not [string]::IsNullOrWhiteSpace($notificationReceipt) -and $notificationReceipt -notmatch '^watch-receipt:[0-9a-f]{64}$') { $finding = 'notification_receipt_invalid' }
                elseif (-not [string]::IsNullOrWhiteSpace($cleanupReceipt) -and $cleanupReceipt -notmatch '^watch-cleanup:[0-9a-f]{64}$') { $finding = 'cleanup_receipt_invalid' }
                $evidence = [datetimeoffset]::MinValue
                if ([string]::IsNullOrWhiteSpace($finding) -and (-not [datetimeoffset]::TryParse($evidenceText, [ref]$evidence) -or $evidence -gt $now.AddMinutes(1) -or $evidence -lt $now.AddMinutes(-$FreshnessMinutes))) { $finding = 'stop_evidence_stale' }
                if (-not [string]::IsNullOrWhiteSpace($finding)) { $result.reason_code = $finding; break }

                $canonical = [ordered]@{ target_thread_id=$targetId; automation_id=$targetAutomation; source_turn_id=$sourceTurn; state=$state; task_stopped=$true; stop_reason=$stopReason; recovery_pending=$false; checkpoint_id=$checkpoint; receipt_key=$receipt; evidence_timestamp_utc=$evidence.ToUniversalTime().ToString('o'); external_effect_state=$external; next_retry_at=''; no_active_turn=$true }
                $canonicalRows.Add(($canonical | ConvertTo-Json -Compress)) | Out-Null
                $receiptRows.Add([pscustomobject][ordered]@{ target_thread_id=$targetId; automation_id=$targetAutomation; source_turn_id=$sourceTurn; checkpoint_id=$checkpoint; stop_receipt_key=$receipt; cleanup_receipt_key=$cleanupReceipt; evidence_timestamp_utc=$evidence.ToUniversalTime().ToString('o') }) | Out-Null
                $recordMembers.Add([pscustomobject][ordered]@{ target_thread_id=$targetId; automation_id=$targetAutomation; source_turn_id=$sourceTurn; last_stop_receipt_key=$receipt; last_notification_receipt_key=$notificationReceipt; last_cleanup_receipt_key=$cleanupReceipt; last_checkpoint_id=$checkpoint; last_stop_reason=$stopReason; last_evidence_timestamp_utc=$evidence.ToUniversalTime().ToString('o') }) | Out-Null
                $result.stopped_count++
            }
        }

        if ($result.reason_code -eq 'shutdown_not_armed') {
            $statePathFull = [IO.Path]::GetFullPath($StatePath)
            $lockPath = $statePathFull + '.lock'
            $lock = $null
            try {
                try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) }
                catch [IO.IOException] { $result.reason_code = 'state_lock_busy' }
                if ($null -ne $lock) {
                    try {
                        $state = Read-WatchFleetSupervisorState $statePathFull $AutomationId $effectiveGenerationId
                        $result.previous_tick_id = [string]$state.current_tick_id
                        $incoming = if (-not [string]::IsNullOrWhiteSpace($MembershipJson)) {
                            ConvertTo-WatchFleetMembershipRows @($MembershipJson | ConvertFrom-Json -Depth 20 -ErrorAction Stop)
                        } else { ConvertTo-WatchFleetMembershipRows @($recordMembers.ToArray()) }

                        $existingById = @{}
                        foreach ($member in @($state.membership)) { $existingById[[string]$member.target_thread_id] = $member }
                        $incomingById = @{}
                        foreach ($member in @($incoming)) { $incomingById[[string]$member.target_thread_id] = $member }
                        $missingExisting = @($existingById.Keys | Where-Object { -not $incomingById.ContainsKey($_) })
                        if ($missingExisting.Count -gt 0) {
                            Reset-WatchFleetCandidate $state
                            $state.observed_at = $now.ToString('o')
                            Write-WatchFleetSupervisorState $statePathFull $state
                            $result.reason_code = 'membership_shrink_detected'
                        }
                        else {
                            $membershipChanged = $false
                            foreach ($id in @($incomingById.Keys)) {
                                $incomingMember = $incomingById[$id]
                                if ($existingById.ContainsKey($id)) {
                                    $existing = $existingById[$id]
                                    if ([string]$existing.automation_id -cne [string]$incomingMember.automation_id -or [string]$existing.source_turn_id -cne [string]$incomingMember.source_turn_id) { throw 'membership_identity_conflict' }
                                }
                                else { $existingById[$id] = $incomingMember; $membershipChanged = $true }
                            }
                            if ($membershipChanged) { $state.membership_epoch = [int]$state.membership_epoch + 1; Reset-WatchFleetCandidate $state }

                            $recordById = @{}
                            foreach ($row in @($recordMembers.ToArray())) { $recordById[[string]$row.target_thread_id] = $row }
                            $merged = [Collections.Generic.List[object]]::new()
                            foreach ($id in @($existingById.Keys | Sort-Object)) {
                                $member = $existingById[$id]
                                if ($recordById.ContainsKey($id)) { $member = $recordById[$id] }
                                $merged.Add((ConvertTo-WatchFleetMember $member)) | Out-Null
                            }
                            $state.membership = @($merged.ToArray())
                            $result.membership_count = $state.membership.Count
                            $result.membership_epoch = [int]$state.membership_epoch

                            $recordIds = @($recordById.Keys | Sort-Object)
                            $memberIds = @($existingById.Keys | Sort-Object)
                            if (($recordIds -join "`n") -cne ($memberIds -join "`n")) {
                                Reset-WatchFleetCandidate $state
                                $state.observed_at = $now.ToString('o')
                                Write-WatchFleetSupervisorState $statePathFull $state
                                $result.reason_code = 'membership_shrink_detected'
                            }
                            else {
                                $snapshotHash = Get-WatchFleetSha256 ("generation={0}`nsupervisor={1}`nmembership_epoch={2}`n{3}" -f $effectiveGenerationId, $AutomationId, $state.membership_epoch, [string]::Join("`n", $canonicalRows.ToArray()))
                                $snapshotKey = 'watch-fleet-stopped:' + $snapshotHash
                                $shutdownReceiptKey = 'watch-fleet-shutdown:' + $snapshotHash
                                $result.snapshot_key = $snapshotKey
                                $result.shutdown_receipt_key = $shutdownReceiptKey
                                if (-not [string]::IsNullOrWhiteSpace($canonicalCallerPreviousTick) -and $canonicalCallerPreviousTick -cne [string]$state.current_tick_id) { $result.reason_code = 'caller_state_mismatch' }
                                elseif (-not [string]::IsNullOrWhiteSpace($PreviousSnapshotKey) -and $PreviousSnapshotKey -cne [string]$state.snapshot_key) { $result.reason_code = 'caller_state_mismatch' }
                                elseif ($FinalRecheck) {
                                    $candidate = $state.candidate
                                    $expiry = [datetimeoffset]::MinValue
                                    if ($null -eq $candidate -or (ConvertTo-WatchFleetTimestampText (Get-WatchFleetProperty $candidate 'current_tick_id')) -cne $canonicalCurrentTick -or [string](Get-WatchFleetProperty $candidate 'snapshot_key') -cne $snapshotKey -or [int](Get-WatchFleetProperty $candidate 'membership_epoch') -ne [int]$state.membership_epoch) { $result.reason_code = 'final_recheck_state_mismatch' }
                                    elseif (-not [datetimeoffset]::TryParse([string](Get-WatchFleetProperty $candidate 'expires_at_utc'), [ref]$expiry) -or $expiry -le $now) { $result.reason_code = 'candidate_receipt_expired' }
                                    elseif (@($state.successful_shutdown_receipt_keys) -contains $shutdownReceiptKey -or $PriorShutdownReceiptKey -ceq $shutdownReceiptKey) {
                                        $result.reason_code = 'shutdown_already_scheduled'
                                    }
                                    elseif ($ConfirmSupervisorDeleted) {
                                        if (-not [bool](Get-WatchFleetProperty $candidate 'final_recheck_completed') -or
                                            -not [bool](Get-WatchFleetProperty $candidate 'supervisor_delete_requested')) {
                                            $result.reason_code = 'supervisor_delete_not_requested'
                                        }
                                        elseif (-not (Test-WatchSupervisorAutomationAbsent -Root $AutomationRoot -ExpectedAutomationId $AutomationId)) {
                                            $result.reason_code = 'supervisor_delete_unproved'
                                        }
                                        else {
                                            $deleteReceipt = 'watch-supervisor-delete:' + (Get-WatchFleetSha256 ("candidate={0}`nautomation_id={1}`nmetadata_absent=true" -f [string]$candidate.receipt_key,$AutomationId))
                                            $candidate | Add-Member -NotePropertyName supervisor_deleted -NotePropertyValue $true -Force
                                            $candidate | Add-Member -NotePropertyName supervisor_deleted_at_utc -NotePropertyValue $now.ToString('o') -Force
                                            $candidate | Add-Member -NotePropertyName supervisor_delete_receipt_key -NotePropertyValue $deleteReceipt -Force
                                            $state.candidate = $candidate
                                            $result.supervisor_delete_receipt_key = $deleteReceipt
                                            if (-not [string]::IsNullOrWhiteSpace($ConfirmedShutdownReceiptKey)) {
                                                if ($ConfirmedShutdownReceiptKey -cne $shutdownReceiptKey) {
                                                    $result.reason_code = 'confirmed_receipt_mismatch'
                                                }
                                                else {
                                                    $state.successful_shutdown_receipt_keys = @(@($state.successful_shutdown_receipt_keys) + $shutdownReceiptKey | Sort-Object -Unique)
                                                    $candidate | Add-Member -NotePropertyName shutdown_scheduled -NotePropertyValue $true -Force
                                                    $candidate | Add-Member -NotePropertyName shutdown_scheduled_at_utc -NotePropertyValue $now.ToString('o') -Force
                                                    $state.candidate = $candidate
                                                    $result.reason_code = 'shutdown_receipt_recorded'
                                                }
                                            }
                                            else {
                                                $result.power_action = 'schedule_shutdown'
                                                $result.reason_code = 'supervisor_deleted_schedule_shutdown'
                                                $result.shutdown_receipt_expires_at_utc = [string]$candidate.expires_at_utc
                                            }
                                            $state.observed_at = $now.ToString('o')
                                            Write-WatchFleetSupervisorState $statePathFull $state
                                        }
                                    }
                                    else {
                                        if ([bool](Get-WatchFleetProperty $candidate 'supervisor_delete_requested')) {
                                            $result.reason_code = 'supervisor_delete_receipt_pending'
                                        }
                                        else {
                                            $candidate | Add-Member -NotePropertyName final_recheck_completed -NotePropertyValue $true -Force
                                            $candidate | Add-Member -NotePropertyName final_rechecked_at_utc -NotePropertyValue $now.ToString('o') -Force
                                            $candidate | Add-Member -NotePropertyName supervisor_delete_requested -NotePropertyValue $true -Force
                                            $candidate | Add-Member -NotePropertyName supervisor_deleted -NotePropertyValue $false -Force
                                            $candidate | Add-Member -NotePropertyName supervisor_delete_receipt_key -NotePropertyValue '' -Force
                                            $state.candidate = $candidate
                                            $state.observed_at = $now.ToString('o')
                                            Write-WatchFleetSupervisorState $statePathFull $state
                                            $result.power_action = 'delete_supervisor'
                                            $result.reason_code = 'final_candidate_delete_supervisor'
                                        }
                                        $result.candidate_receipt_key = [string]$candidate.receipt_key
                                        $result.candidate_receipt_expires_at_utc = [string]$candidate.expires_at_utc
                                    }
                                }
                                elseif ([string]$state.current_tick_id -ceq $canonicalCurrentTick) { $result.reason_code = 'tick_already_evaluated' }
                                else {
                                    $previousTick = [datetimeoffset]::MinValue
                                    $stable = -not [string]::IsNullOrWhiteSpace([string]$state.current_tick_id) -and [string]$state.snapshot_key -ceq $snapshotKey -and [datetimeoffset]::TryParse([string]$state.current_tick_id, [ref]$previousTick) -and $previousTick -lt $currentTick
                                    $oldCurrent = [string]$state.current_tick_id
                                    $state.previous_tick_id = $oldCurrent
                                    $state.current_tick_id = $canonicalCurrentTick
                                    $state.snapshot_key = $snapshotKey
                                    $state.observed_at = $now.ToString('o')
                                    if ($stable) {
                                        $expiryText = $now.AddSeconds($ShutdownReceiptTtlSeconds).ToString('o')
                                        $candidateBinding = [ordered]@{ schema_version=1; watch_runtime_generation_id=$effectiveGenerationId; supervisor_automation_id=$AutomationId; membership_epoch=[int]$state.membership_epoch; previous_tick_id=$oldCurrent; current_tick_id=$canonicalCurrentTick; snapshot_key=$snapshotKey; expires_at_utc=$expiryText; member_receipts=@($receiptRows.ToArray()) }
                                        $candidateReceipt = 'watch-fleet-candidate:' + (Get-WatchFleetSha256 ($candidateBinding | ConvertTo-Json -Depth 20 -Compress))
                                        $state.candidate = [pscustomobject][ordered]@{ schema_version=1; receipt_key=$candidateReceipt; watch_runtime_generation_id=$effectiveGenerationId; supervisor_automation_id=$AutomationId; membership_epoch=[int]$state.membership_epoch; previous_tick_id=$oldCurrent; current_tick_id=$canonicalCurrentTick; snapshot_key=$snapshotKey; expires_at_utc=$expiryText; final_recheck_completed=$false; final_rechecked_at_utc=''; supervisor_delete_requested=$false; supervisor_deleted=$false; supervisor_deleted_at_utc=''; supervisor_delete_receipt_key=''; shutdown_scheduled=$false; shutdown_scheduled_at_utc=''; member_receipts=@($receiptRows.ToArray()) }
                                        $result.power_action = 'await_final_recheck'
                                        $result.reason_code = 'candidate_receipt_ready'
                                        $result.candidate_receipt_key = $candidateReceipt
                                        $result.candidate_receipt_expires_at_utc = $expiryText
                                    }
                                    else { $state.candidate = $null; $result.reason_code = 'stability_confirmation_required' }
                                    Write-WatchFleetSupervisorState $statePathFull $state
                                }
                            }
                        }
                        $result.successful_shutdown_receipt_count = @($state.successful_shutdown_receipt_keys).Count
                    }
                    catch {
                        $message = [string]$_.Exception.Message
                        $result.state_error_type = $_.Exception.GetType().FullName
                        $result.reason_code = if ($message -match '^(state|membership)_[a-z_]+$') { $message } else { 'state_update_failed' }
                    }
                }
            }
            finally {
                if ($null -ne $lock) { $lock.Dispose(); if ([IO.File]::Exists($lockPath)) { [IO.File]::Delete($lockPath) } }
            }
        }
    }
}

$output = [pscustomobject]$result
if ($AsJson) { $output | ConvertTo-Json -Depth 12 -Compress } else { $output }
