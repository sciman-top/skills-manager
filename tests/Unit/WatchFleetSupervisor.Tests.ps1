Describe 'watch-interrupted-task fleet supervisor revision-3 contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $generator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'
        $disposition = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\Get-WatchFleetShutdownDisposition.ps1'
        $script:prompt = & $generator -SupervisorThreadId 'supervisor-test'
        $script:shutdownPrompt = & $generator -SupervisorThreadId 'supervisor-test' -ShutdownWhenAllStopped
        $script:disposition = $disposition
        $script:supervisorAutomationId = 'automation-supervisor-test'
        $script:receiptA = 'watch-receipt:' + ('a' * 64)
        $script:receiptB = 'watch-receipt:' + ('b' * 64)
        $script:checkpointA = 'watch-checkpoint:' + ('c' * 64)
        $script:checkpointB = 'watch-checkpoint:' + ('d' * 64)
    }

    It 'continuously reconciles visible target heartbeats under the conditional recovery policy' {
        $script:prompt | Should Match 'watch-interrupted-task:fleet:v1 supervisor_thread_id=supervisor-test'
        $script:prompt | Should Match 'policy_revision=3'
        $script:prompt | Should Match 'operating_mode=conditional_recovery'
        $script:prompt | Should Match 'every scheduled run'
        $script:prompt | Should Match 'newly eligible'
        $script:prompt | Should Match 'at most 50'
        $script:prompt | Should Match 'create or update only the canonical target heartbeat'
    }

    It 'requires current native heartbeat provenance after compaction' {
        $script:prompt | Should Match 'current user input itself is the native fleet heartbeat envelope'
        $script:prompt | Should Match 'After any context compaction.*re-check'
        $script:prompt | Should Match 'direct user or business message'
        $script:prompt | Should Match 'do not emit heartbeat XML'
    }

    It 'recovers its own hosted task directly but never creates a duplicate heartbeat for itself' {
        $script:prompt | Should Match 'dual-role'
        $script:prompt | Should Match 'apply the target recovery contract to the supervisor thread itself'
        $script:prompt | Should Match 'Never create a separate target heartbeat for the supervisor thread'
        $script:prompt | Should Match 'cannot mutate its own automation'
    }

    It 'limits fleet writes to canonical provenance and verified cleanup' {
        $script:prompt | Should Match 'trusted canonical target body digest'
        $script:prompt | Should Match 'fresh host metadata'
        $script:prompt | Should Match 'proved stable stop'
        $script:prompt | Should Match 'never performs business work in another task'
    }

    It 'never injects a peer message and uses XML heartbeat output' {
        $script:prompt | Should Match 'Never call send_message_to_thread'
        $script:prompt | Should Match 'read-only list/read/wait'
        $script:prompt | Should Match '<heartbeat>'
        $script:prompt | Should Match '<decision>DONT_NOTIFY\|NOTIFY</decision>'
        $script:prompt | Should -Not -Match 'entire assistant output must be exactly DONT_NOTIFY'
    }

    It 'outputs real JSON in a fresh process' {
        $command = "& '$generator' -SupervisorThreadId 'json-supervisor' -AsJson"
        $raw = & pwsh -NoProfile -Command $command
        $json = (@($raw) -join "`n") | ConvertFrom-Json
        $json.supervisor_thread_id | Should Be 'json-supervisor'
        $json.policy_revision | Should Be 3
        $json.shutdown_when_all_stopped | Should Be $false
        $json.prompt | Should Match 'policy_revision=3'
    }

    It 'keeps shutdown opt-in and excludes every recoverable or unknown stop boundary' {
        $script:prompt | Should -Not -Match 'shutdown_when_all_stopped=true'
        $script:shutdownPrompt | Should Match 'shutdown_when_all_stopped=true'
        $script:shutdownPrompt | Should Match 'Goal presence does not change this rule'
        $script:shutdownPrompt | Should Match 'Do not use a finite allowlist of stop causes'
        $script:shutdownPrompt | Should Match 'task_stopped=true'
        $script:shutdownPrompt | Should Match 'recovery_pending=false'
        $script:shutdownPrompt | Should Match '408/429/502/503/504'
        $script:shutdownPrompt | Should Match 'two consecutive scheduled ticks'
        $script:shutdownPrompt | Should Match 'CurrentTickId'
        $script:shutdownPrompt | Should Match 'PreviousTickId'
        $script:shutdownPrompt | Should Match 'source_turn_id'
        $script:shutdownPrompt | Should Match 'shutdown_receipt_expires_at_utc'
        $script:shutdownPrompt | Should Match 'shutdown\.exe /s /t 120'
        $script:shutdownPrompt | Should Match 'Never add /f'
        $script:shutdownPrompt | Should Match 'shutdown /a'
        $script:shutdownPrompt | Should Match 'automation_action=request_supervisor_cleanup'
        $script:shutdownPrompt | Should Match 'delete the matching canonical target heartbeat'
        $script:shutdownPrompt | Should Match 'verify.*delete.*receipt'
        $script:shutdownPrompt | Should Match 'no canonical target heartbeat remains'
        $script:shutdownPrompt | Should Match 'delete this supervisor heartbeat'
        $script:shutdownPrompt | Should Match 'Only after the native supervisor delete receipt'
        $script:shutdownPrompt | Should Match 'visibility.*50'
        $script:shutdownPrompt | Should Match 'newly active eligible task.*enrolling its heartbeat.*canceling shutdown'
        $script:shutdownPrompt | Should Match 'UnmonitoredActiveTaskCount=0'

        $standardJson = ((& $generator -SupervisorThreadId 'json-supervisor' -AsJson) | ConvertFrom-Json)
        $shutdownJson = ((& $generator -SupervisorThreadId 'json-supervisor' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json)
        $shutdownJson.shutdown_when_all_stopped | Should Be $true
        $shutdownJson.prompt_sha256 | Should Not Be $standardJson.prompt_sha256
    }

    It 'requires a non-empty fresh all-stopped snapshot twice and deduplicates shutdown' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'dedupe-state.json'
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; VisibleCount=2; EligibleCount=2; MonitoredCount=2; BlockingUnmonitoredCount=0; GuardReady=$true }
        $firstTick = $now.AddMinutes(-1).ToString('o')
        $secondTick = $now.ToString('o')
        $thirdTick = $now.AddSeconds(1).ToString('o')
        $snapshot = @(
            [ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true },
            [ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-source-b'; state='needs_input'; task_stopped=$true; stop_reason='human_input_required'; recovery_pending=$false; receipt_key=$script:receiptB; checkpoint_id=$script:checkpointB; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='safe'; next_retry_at=''; no_active_turn=$true }
        ) | ConvertTo-Json -Depth 8 -Compress

        $first = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $firstTick -ShutdownArmed @coverage
        $first.power_action | Should Be 'observe_only'
        $first.reason_code | Should Be 'stability_confirmation_required'

        $second = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $secondTick -PreviousTickId $firstTick -PreviousSnapshotKey $first.snapshot_key -ShutdownArmed @coverage
        $second.power_action | Should Be 'schedule_shutdown'
        $second.reason_code | Should Be 'all_monitored_tasks_stopped'
        $second.shutdown_receipt_key | Should Match '^watch-fleet-shutdown:[0-9a-f]{64}$'
        $expires = [datetimeoffset]::Parse($second.shutdown_receipt_expires_at_utc)
        $expires | Should BeGreaterThan ([datetimeoffset]::UtcNow)
        $expires | Should BeLessThan ([datetimeoffset]::UtcNow.AddMinutes(3))

        $rechecked = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $secondTick -ShutdownArmed -FinalRecheck @coverage
        $rechecked.power_action | Should Be 'schedule_shutdown'
        $rechecked.shutdown_receipt_key | Should Be $second.shutdown_receipt_key

        $null = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $secondTick -ShutdownArmed -ConfirmedShutdownReceiptKey $second.shutdown_receipt_key @coverage
        $deduplicated = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $thirdTick -PreviousTickId $secondTick -PreviousSnapshotKey $first.snapshot_key -ShutdownArmed @coverage
        $deduplicated.power_action | Should Be 'observe_only'
        $deduplicated.reason_code | Should Be 'shutdown_already_scheduled'
    }

    It 'uses an internal clock and rejects a repeated scheduled tick outside final recheck' {
        (Get-Command $script:disposition).Parameters.Keys | Should Not Contain 'NowUtc'
        $now = [datetimeoffset]::UtcNow
        $tick = $now.ToString('o')
        $statePath = Join-Path $TestDrive 'same-tick-main-state.json'
        $coverage = @{ StateRoot=$TestDrive; StatePath=$statePath; GuardReady=$true; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1 }
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $first = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $tick -ShutdownArmed @coverage
        $sameTick = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $tick -ShutdownArmed @coverage

        $sameTick.power_action | Should Be 'observe_only'
        $sameTick.reason_code | Should Be 'tick_already_evaluated'
    }

    It 'binds stability to the supervisor automation and complete target provenance' {
        $now = [datetimeoffset]::UtcNow
        $firstTick = $now.AddMinutes(-1).ToString('o')
        $secondTick = $now.ToString('o')
        $statePath = Join-Path $TestDrive 'provenance-state.json'
        $coverage = @{ StateRoot=$TestDrive; StatePath=$statePath; GuardReady=$true; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1 }
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $first = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $firstTick -ShutdownArmed @coverage

        $otherAutomation = & $script:disposition -SnapshotJson $snapshot -AutomationId 'automation-other-supervisor' -CurrentTickId $secondTick -PreviousTickId $firstTick -PreviousSnapshotKey $first.snapshot_key -ShutdownArmed @coverage
        $otherAutomation.power_action | Should Be 'observe_only'
        $otherAutomation.reason_code | Should Be 'state_automation_mismatch'

        $missingSource = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id=''; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $invalid = & $script:disposition -SnapshotJson $missingSource -AutomationId $script:supervisorAutomationId -CurrentTickId $firstTick -ShutdownArmed @coverage
        $invalid.reason_code | Should Be 'target_provenance_invalid'
    }

    It 'rejects unstructured stop receipts and checkpoint identifiers' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'structured-receipt-state.json'
        $coverage = @{ StateRoot=$TestDrive; StatePath=$statePath; GuardReady=$true; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1 }
        foreach ($case in @(
            @{ Receipt='receipt'; Checkpoint=$script:checkpointA },
            @{ Receipt=$script:receiptA; Checkpoint='checkpoint' }
        )) {
            $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$case.Receipt; checkpoint_id=$case.Checkpoint; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
            $result = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed @coverage
            $result.reason_code | Should Be 'stop_receipt_invalid'
        }
    }

    It 'accepts any proved stop reason without depending on Goal presence or a finite state allowlist' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'custom-stop-state.json'
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; BlockingUnmonitoredCount=0; GuardReady=$true }
        $snapshot = @([ordered]@{
            target_thread_id='custom-stop'
            state='user_cancelled'
            task_stopped=$true
            stop_reason='user_cancelled'
            recovery_pending=$false
            automation_id='automation-target-custom'
            source_turn_id='turn-source-custom'
            receipt_key=$script:receiptA
            checkpoint_id=$script:checkpointA
            evidence_timestamp_utc=$now.ToString('o')
            external_effect_state='none'
            next_retry_at=''
            no_active_turn=$true
        }) | ConvertTo-Json -Compress

        $firstTick = $now.AddMinutes(-1).ToString('o')
        $secondTick = $now.ToString('o')
        $first = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $firstTick -ShutdownArmed @coverage
        $second = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $secondTick -PreviousTickId $firstTick -PreviousSnapshotKey $first.snapshot_key -ShutdownArmed @coverage
        $second.power_action | Should Be 'schedule_shutdown'
        $second.reason_code | Should Be 'all_monitored_tasks_stopped'
    }

    It 'blocks shutdown for transient recovery active retry unknown stale or empty snapshots' {
        $now = [datetimeoffset]::UtcNow
        $coverage = @{ StateRoot=$TestDrive; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; BlockingUnmonitoredCount=0; GuardReady=$true }
        $index = 0
        foreach ($case in @(
            @{ State='resume_eligible'; Retry=''; Expected='recovery_or_retry_pending' },
            @{ State='running'; Retry=''; Expected='target_running' },
            @{ State='unknown'; Retry=''; Expected='target_state_unproved' },
            @{ State='complete'; Retry=$now.AddMinutes(2).ToString('o'); Expected='retry_scheduled' }
        )) {
            $index++
            $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state=$case.State; task_stopped=$true; stop_reason='claimed_stop'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=$case.Retry; no_active_turn=$true }) | ConvertTo-Json -Compress
            $caseCoverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=(Join-Path $TestDrive "blocked-$index.json"); VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; GuardReady=$true }
            $result = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $now.ToString('o') -ShutdownArmed @caseCoverage
            $result.power_action | Should Be 'observe_only'
            $result.reason_code | Should Be $case.Expected
        }

        $emptyCoverage = @{ StateRoot=$TestDrive; StatePath=(Join-Path $TestDrive 'empty.json'); GuardReady=$true; VisibilityComplete=$true; VisibleCount=0; EligibleCount=0; MonitoredCount=0 }
        $empty = & $script:disposition -SnapshotJson '[]' -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed @emptyCoverage
        $empty.reason_code | Should Be 'monitored_set_empty'

        $staleSnapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.AddHours(-1).ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $staleCoverage = @{ StateRoot=$TestDrive; StatePath=(Join-Path $TestDrive 'stale.json'); GuardReady=$true; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1 }
        $stale = & $script:disposition -SnapshotJson $staleSnapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed @staleCoverage
        $stale.reason_code | Should Be 'stop_evidence_stale'
    }

    It 'requires explicit stopped and non-recovery proof even for otherwise terminal states' {
        $now = [datetimeoffset]::UtcNow
        $coverage = @{ StateRoot=$TestDrive; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; BlockingUnmonitoredCount=0; GuardReady=$true }
        $index = 0
        foreach ($case in @(
            @{ Stopped=$false; Recovery=$false; Reason='complete'; Expected='stop_decision_unproved' },
            @{ Stopped=$true; Recovery=$true; Reason='complete'; Expected='recovery_or_retry_pending' },
            @{ Stopped=$true; Recovery=$false; Reason=''; Expected='stop_reason_invalid' }
        )) {
            $index++
            $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$case.Stopped; stop_reason=$case.Reason; recovery_pending=$case.Recovery; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
            $caseCoverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=(Join-Path $TestDrive "proof-$index.json"); VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; GuardReady=$true }
            $result = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $now.ToString('o') -ShutdownArmed @caseCoverage
            $result.reason_code | Should Be $case.Expected
        }
    }

    It 'fails closed when visible-task coverage is incomplete or contains unmonitored blockers' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'coverage-state.json'
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $incomplete = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed -StateRoot $TestDrive -StatePath $statePath -GuardReady -VisibilityComplete -VisibleCount 2 -EligibleCount 2 -MonitoredCount 1 -BlockingUnmonitoredCount 1
        $incomplete.power_action | Should Be 'observe_only'
        $incomplete.reason_code | Should Be 'visibility_incomplete'

        $truncated = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed -StateRoot $TestDrive -StatePath $statePath -GuardReady -VisibilityComplete -ListLimitReached -VisibleCount 50 -EligibleCount 1 -MonitoredCount 1
        $truncated.power_action | Should Be 'observe_only'
        $truncated.reason_code | Should Be 'visibility_truncated'
    }

    It 'requires two distinct persisted ticks and rejects a second evaluation in the same tick' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'same-tick-state.json'
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; BlockingUnmonitoredCount=0; GuardReady=$true }
        $firstTick = $now.AddMinutes(-1).ToString('o')
        $secondTick = $now.ToString('o')

        $first = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -CurrentTickId $firstTick @coverage
        $first.reason_code | Should Be 'stability_confirmation_required'
        $second = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -CurrentTickId $secondTick @coverage
        $second.power_action | Should Be 'schedule_shutdown'

        $duplicate = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -CurrentTickId $secondTick @coverage
        $duplicate.power_action | Should Be 'observe_only'
        $duplicate.reason_code | Should Be 'tick_already_evaluated'
    }

    It 'persists successful shutdown receipt history across A to B to A snapshots' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'receipt-history-state.json'
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; BlockingUnmonitoredCount=0; GuardReady=$true }
        $snapshotA = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $snapshotB = @([ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-source-b'; state='needs_input'; task_stopped=$true; stop_reason='human_input_required'; recovery_pending=$false; receipt_key=$script:receiptB; checkpoint_id=$script:checkpointB; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $tickA1 = $now.AddMinutes(-1).ToString('o')
        $tickA2 = $now.AddSeconds(-30).ToString('o')
        $tickB1 = $now.AddSeconds(-20).ToString('o')
        $tickA3 = $now.AddSeconds(-10).ToString('o')
        $tickA4 = $now.ToString('o')

        $null = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA1 @coverage
        $scheduledA = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA2 @coverage
        $scheduledA.power_action | Should Be 'schedule_shutdown'
        $recorded = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA2 -ConfirmedShutdownReceiptKey $scheduledA.shutdown_receipt_key @coverage
        $recorded.successful_shutdown_receipt_count | Should Be 1

        $null = & $script:disposition -SnapshotJson $snapshotB -ShutdownArmed -CurrentTickId $tickB1 @coverage
        $null = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA3 @coverage
        $replayedA = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA4 @coverage
        $replayedA.power_action | Should Be 'observe_only'
        $replayedA.reason_code | Should Be 'shutdown_already_scheduled'
    }

    It 'publishes coverage and durable receipt fields in the shutdown heartbeat contract' {
        $script:shutdownPrompt | Should Match 'visibility_complete'
        $script:shutdownPrompt | Should Match 'blocking_unmonitored_count'
        $script:shutdownPrompt | Should Match 'current_tick_id'
        $script:shutdownPrompt | Should Match 'successful_shutdown_receipt_keys'
        $script:shutdownPrompt | Should Match 'snapshot_key=.*shutdown_receipt_key='
        $script:shutdownPrompt | Should Match 'soft_guard_only.*blocks shutdown'
    }

    It 'rejects a state journal outside the explicitly approved repo runtime root' {
        $now = [datetimeoffset]::UtcNow
        $approvedRoot = Join-Path $TestDrive 'approved-root'
        $null = New-Item -ItemType Directory -Path $approvedRoot
        $outsideState = Join-Path $TestDrive 'outside-state.json'
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $result = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed -StateRoot $approvedRoot -StatePath $outsideState -VisibilityComplete -GuardReady -VisibleCount 1 -EligibleCount 1 -MonitoredCount 1
        $result.power_action | Should Be 'observe_only'
        $result.reason_code | Should Be 'state_path_outside_root'
        Test-Path -LiteralPath $outsideState | Should Be $false
    }

    It 'does not let the deprecated single receipt argument poison durable state' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'legacy-receipt-state.json'
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $result = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed -StateRoot $TestDrive -StatePath $statePath -VisibilityComplete -GuardReady -VisibleCount 1 -EligibleCount 1 -MonitoredCount 1 -PriorShutdownReceiptKey 'not-a-valid-receipt'
        $result.power_action | Should Be 'observe_only'
        $result.reason_code | Should Be 'prior_receipt_invalid'
        Test-Path -LiteralPath $statePath | Should Be $false
    }

    It 'requires complete visibility and zero remaining target heartbeats before shutdown eligibility' {
        $now = [datetimeoffset]::UtcNow
        $snapshot = @([ordered]@{ target_thread_id='supervisor'; automation_id=$script:supervisorAutomationId; source_turn_id='turn-source-supervisor'; state='stopped'; task_stopped=$true; stop_reason='fleet_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $visibilityUnknown = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed
        $visibilityUnknown.reason_code | Should Be 'visibility_unproved'
        $visibilityUnknown.power_action | Should Be 'observe_only'

        $targetRemains = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed -VisibilityComplete -RemainingTargetHeartbeatCount 1
        $targetRemains.reason_code | Should Be 'target_heartbeats_remain'
        $targetRemains.power_action | Should Be 'observe_only'

        $newTask = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed -VisibilityComplete -UnmonitoredActiveTaskCount 1
        $newTask.reason_code | Should Be 'unmonitored_active_tasks'
        $newTask.power_action | Should Be 'observe_only'
    }
}
