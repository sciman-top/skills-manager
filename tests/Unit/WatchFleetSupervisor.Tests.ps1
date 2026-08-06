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

    It 'keeps the fleet scheduled prompt self contained and uses the twelve-minute cadence contract' {
        $script:prompt | Should -Not -Match 'Use \$watch-interrupted-task'
        $script:shutdownPrompt | Should -Not -Match 'Use \$watch-interrupted-task'
        $script:shutdownPrompt | Should Match 'watch_runtime_generation_id=watch-runtime-generation:[0-9a-f]{64}'
        $script:shutdownPrompt | Should Match 'supervisor_cadence_minutes=12'
        $script:shutdownPrompt | Should Match 'target_cadence_minutes=12'
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
        $script:shutdownPrompt | Should Match 'Goal and non-Goal'
        $script:shutdownPrompt | Should Match 'stable stop'
        $script:shutdownPrompt | Should Match 'generation'
        $script:shutdownPrompt | Should Match 'two distinct ordered scheduled ticks'
        $script:shutdownPrompt | Should Match 'source_turn_id'
        $script:shutdownPrompt | Should Match 'candidate_receipt_expires_at_utc'
        $script:shutdownPrompt | Should Match 'power_action=schedule_shutdown'
        $script:shutdownPrompt | Should Match 'shutdown /a'
        $script:shutdownPrompt | Should Match 'Then execute exactly shutdown\.exe'
        $script:shutdownPrompt | Should Match 'delete a matching target heartbeat only when it is PAUSED'
        $script:shutdownPrompt | Should Match 'preflight is not shutdown_armed.*roll back'
        $script:shutdownPrompt | Should Match 'Membership is monotonic'
        $script:shutdownPrompt | Should Match 'membership_shrink_detected'
        $script:shutdownPrompt | Should Match 'FinalRecheck.*final_recheck_completed'
        $script:shutdownPrompt | Should Match 'delete this supervisor heartbeat'

        $standardJson = ((& $generator -SupervisorThreadId 'json-supervisor' -AsJson) | ConvertFrom-Json)
        $shutdownJson = ((& $generator -SupervisorThreadId 'json-supervisor' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json)
        $shutdownJson.shutdown_when_all_stopped | Should Be $true
        $shutdownJson.prompt_sha256 | Should Not Be $standardJson.prompt_sha256
    }

    It 'requires a non-empty fresh all-stopped snapshot twice and then a final candidate recheck' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'dedupe-state.json'
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; VisibleCount=2; EligibleCount=2; MonitoredCount=2; BlockingUnmonitoredCount=0; GuardReady=$true }
        $firstTick = $now.AddMinutes(-1).ToString('o')
        $secondTick = $now.ToString('o')
        $snapshot = @(
            [ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true },
            [ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-source-b'; state='needs_input'; task_stopped=$true; stop_reason='human_input_required'; recovery_pending=$false; receipt_key=$script:receiptB; checkpoint_id=$script:checkpointB; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='safe'; next_retry_at=''; no_active_turn=$true }
        ) | ConvertTo-Json -Depth 8 -Compress

        $first = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $firstTick -ShutdownArmed @coverage
        $first.power_action | Should Be 'observe_only'
        $first.reason_code | Should Be 'stability_confirmation_required'

        $second = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $secondTick -PreviousTickId $firstTick -PreviousSnapshotKey $first.snapshot_key -ShutdownArmed @coverage
        $second.power_action | Should Be 'await_final_recheck'
        $second.reason_code | Should Be 'candidate_receipt_ready'
        $second.candidate_receipt_key | Should Match '^watch-fleet-candidate:[0-9a-f]{64}$'
        $expires = [datetimeoffset]::Parse($second.candidate_receipt_expires_at_utc)
        $expires | Should BeGreaterThan ([datetimeoffset]::UtcNow)
        $expires | Should BeLessThan ([datetimeoffset]::UtcNow.AddMinutes(3))

        $rechecked = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $secondTick -ShutdownArmed -FinalRecheck @coverage
        $rechecked.power_action | Should Be 'delete_supervisor'
        $rechecked.reason_code | Should Be 'final_candidate_delete_supervisor'
        $rechecked.candidate_receipt_key | Should Be $second.candidate_receipt_key
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
        $second.power_action | Should Be 'await_final_recheck'
        $second.reason_code | Should Be 'candidate_receipt_ready'
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
        $truncated.reason_code | Should Be 'stability_confirmation_required'
    }

    It 'does not let inactive history saturation block an enrolled active set but blocks unavailable sources' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'membership-coverage-state.json'
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; ListLimitReached=$true; VisibleCount=50; EligibleCount=1; MonitoredCount=1; GuardReady=$true }

        $historyOnly = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $now.ToString('o') -ShutdownArmed @coverage
        $historyOnly.reason_code | Should Be 'stability_confirmation_required'

        $unavailable = & $script:disposition -SnapshotJson $snapshot -CurrentTickId $now.AddSeconds(1).ToString('o') -ShutdownArmed -UnavailableSourceCount 1 @coverage
        $unavailable.power_action | Should Be 'observe_only'
        $unavailable.reason_code | Should Be 'source_visibility_unavailable'
    }

    It 'persists runtime generation membership and target receipts in the fleet journal' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'generation-membership-state.json'
        $generation = 'watch-runtime-generation:' + ('e' * 64)
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; notification_receipt_key=$script:receiptA; cleanup_receipt_key=('watch-cleanup:' + ('f' * 64)); evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $null = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ShutdownArmed -GuardReady -VisibilityComplete -VisibleCount 1 -EligibleCount 1 -MonitoredCount 1 -StateRoot $TestDrive -StatePath $statePath -WatchRuntimeGenerationId $generation
        $journal = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $journal.schema_version | Should Be 4
        $journal.watch_runtime_generation_id | Should Be $generation
        @($journal.membership).Count | Should Be 1
        $journal.membership[0].target_thread_id | Should Be 'a'
        $journal.membership[0].last_notification_receipt_key | Should Be $script:receiptA
        $journal.membership[0].last_cleanup_receipt_key | Should Match '^watch-cleanup:[0-9a-f]{64}$'
    }

    It 'persists a newly active enrolled member and resets shutdown stability' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'dynamic-membership-state.json'
        $generation = 'watch-runtime-generation:' + ('e' * 64)
        $coverageA = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; WatchRuntimeGenerationId=$generation; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; GuardReady=$true }
        $snapshotA = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $memberA = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a' }) | ConvertTo-Json -Compress
        $first = & $script:disposition -SnapshotJson $snapshotA -MembershipJson $memberA -CurrentTickId $now.AddMinutes(-2).ToString('o') -ShutdownArmed @coverageA
        $first.reason_code | Should Be 'stability_confirmation_required'

        $snapshotRunning = @(
            [ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true },
            [ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-b'; state='running'; task_stopped=$false; stop_reason=''; recovery_pending=$false; receipt_key=$script:receiptB; checkpoint_id=$script:checkpointB; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$false }
        ) | ConvertTo-Json -Compress
        $membersAB = @(
            [ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a' },
            [ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-b' }
        ) | ConvertTo-Json -Compress
        $coverageAB = $coverageA.Clone(); $coverageAB.VisibleCount=2; $coverageAB.EligibleCount=2; $coverageAB.MonitoredCount=2
        $running = & $script:disposition -SnapshotJson $snapshotRunning -MembershipJson $membersAB -CurrentTickId $now.AddMinutes(-1).ToString('o') -ShutdownArmed @coverageAB
        $running.reason_code | Should Be 'target_running'
        @((Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).membership).Count | Should Be 2

        $snapshotStopped = @(
            [ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true },
            [ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-b'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptB; checkpoint_id=$script:checkpointB; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }
        ) | ConvertTo-Json -Compress
        $restabilize = & $script:disposition -SnapshotJson $snapshotStopped -MembershipJson $membersAB -CurrentTickId $now.ToString('o') -ShutdownArmed @coverageAB
        $restabilize.reason_code | Should Be 'stability_confirmation_required'
        $restabilize.snapshot_key | Should Not Be $first.snapshot_key
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
        $second.power_action | Should Be 'await_final_recheck'

        $duplicate = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -CurrentTickId $secondTick @coverage
        $duplicate.power_action | Should Be 'observe_only'
        $duplicate.reason_code | Should Be 'tick_already_evaluated'
    }

    It 'never converts A to B to A candidate observations into a repository power authorization' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'receipt-history-state.json'
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; BlockingUnmonitoredCount=0; GuardReady=$true }
        $snapshotA = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $snapshotB = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='needs_input'; task_stopped=$true; stop_reason='human_input_required'; recovery_pending=$false; receipt_key=$script:receiptB; checkpoint_id=$script:checkpointB; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $tickA1 = $now.AddMinutes(-1).ToString('o')
        $tickA2 = $now.AddSeconds(-30).ToString('o')
        $tickB1 = $now.AddSeconds(-20).ToString('o')
        $tickA3 = $now.AddSeconds(-10).ToString('o')
        $tickA4 = $now.ToString('o')

        $null = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA1 @coverage
        $scheduledA = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA2 @coverage
        $scheduledA.power_action | Should Be 'await_final_recheck'

        $null = & $script:disposition -SnapshotJson $snapshotB -ShutdownArmed -CurrentTickId $tickB1 @coverage
        $null = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA3 @coverage
        $replayedA = & $script:disposition -SnapshotJson $snapshotA -ShutdownArmed -CurrentTickId $tickA4 @coverage
        $replayedA.power_action | Should Be 'await_final_recheck'
        $replayedA.reason_code | Should Be 'candidate_receipt_ready'
        $replayedA.successful_shutdown_receipt_count | Should Be 0
    }

    It 'publishes coverage and durable receipt fields in the shutdown heartbeat contract' {
        $script:shutdownPrompt | Should Match 'visibility_complete'
        $script:shutdownPrompt | Should Match 'blocking_unmonitored_count'
        $script:shutdownPrompt | Should Match 'current_tick_id'
        $script:shutdownPrompt | Should Match 'membership_epoch'
        $script:shutdownPrompt | Should Match 'snapshot_key=.*candidate_receipt_key='
        $script:shutdownPrompt | Should Match 'soft_guard_only.*blocks shutdown'
        $script:shutdownPrompt | Should Match 'checkout_identity'
        $script:shutdownPrompt | Should Match 'operation_state=read_only\|external_wait\|write_planning\|writing\|git_ref_mutation'
        $script:shutdownPrompt | Should Match 'write_domain=working_tree\|git_index\|git_refs\|generated_runtime\|host_config\|external_effect'
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

    It 'keeps enrolled membership monotonic and fails closed when a later snapshot omits a member' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'monotonic-membership-state.json'
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; GuardReady=$true }
        $membersAB = @(
            [ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a' },
            [ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-b' }
        ) | ConvertTo-Json -Compress
        $membersA = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a' }) | ConvertTo-Json -Compress
        $snapshotAB = @(
            [ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true },
            [ordered]@{ target_thread_id='b'; automation_id='automation-target-b'; source_turn_id='turn-b'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptB; checkpoint_id=$script:checkpointB; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }
        ) | ConvertTo-Json -Compress
        $snapshotA = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $null = & $script:disposition -SnapshotJson $snapshotAB -MembershipJson $membersAB -ShutdownArmed -CurrentTickId $now.AddMinutes(-1).ToString('o') -VisibleCount 2 -EligibleCount 2 -MonitoredCount 2 @coverage
        $shrunk = & $script:disposition -SnapshotJson $snapshotA -MembershipJson $membersA -ShutdownArmed -CurrentTickId $now.ToString('o') -VisibleCount 1 -EligibleCount 1 -MonitoredCount 1 @coverage
        $journal = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json

        $shrunk.reason_code | Should Be 'membership_shrink_detected'
        $shrunk.power_action | Should Be 'observe_only'
        $shrunk.snapshot_key | Should BeNullOrEmpty
        @($journal.membership).Count | Should Be 2
        @($journal.membership.target_thread_id) | Should Contain 'b'
        [string]$journal.snapshot_key | Should BeNullOrEmpty
    }

    It 'persists one candidate through supervisor deletion, shutdown scheduling, and receipt replay suppression' {
        $now = [datetimeoffset]::UtcNow
        $statePath = Join-Path $TestDrive 'durable-candidate-state.json'
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; cleanup_receipt_key=('watch-cleanup:' + ('f' * 64)); evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $membership = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a' }) | ConvertTo-Json -Compress
        $coverage = @{ AutomationId=$script:supervisorAutomationId; StateRoot=$TestDrive; StatePath=$statePath; VisibilityComplete=$true; VisibleCount=1; EligibleCount=1; MonitoredCount=1; BlockingUnmonitoredCount=0; GuardReady=$true; MembershipJson=$membership }
        $firstTick = $now.AddMinutes(-1).ToString('o')
        $secondTick = $now.ToString('o')

        $first = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -CurrentTickId $firstTick @coverage
        $first.reason_code | Should Be 'stability_confirmation_required'
        $second = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -CurrentTickId $secondTick @coverage
        $second.reason_code | Should Be 'candidate_receipt_ready'
        $second.power_action | Should Be 'await_final_recheck'
        $second.candidate_receipt_key | Should Match '^watch-fleet-candidate:[0-9a-f]{64}$'
        $second.candidate_receipt_expires_at_utc | Should Not BeNullOrEmpty

        $final = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -FinalRecheck -CurrentTickId $secondTick @coverage
        $journal = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $final.reason_code | Should Be 'final_candidate_delete_supervisor'
        $final.power_action | Should Be 'delete_supervisor'
        $final.candidate_receipt_key | Should Be $second.candidate_receipt_key
        $journal.candidate.receipt_key | Should Be $second.candidate_receipt_key
        $journal.candidate.final_recheck_completed | Should Be $true
        $journal.candidate.membership_epoch | Should Be $journal.membership_epoch
        @($journal.candidate.member_receipts).Count | Should Be 1

        $automationRoot = Join-Path $TestDrive 'automation-root-after-delete'
        $null = New-Item -ItemType Directory -Path $automationRoot -Force
        $confirmed = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -FinalRecheck -ConfirmSupervisorDeleted -AutomationRoot $automationRoot -CurrentTickId $secondTick @coverage
        $confirmed.reason_code | Should Be 'supervisor_deleted_schedule_shutdown'
        $confirmed.power_action | Should Be 'schedule_shutdown'
        $confirmed.supervisor_delete_receipt_key | Should Match '^watch-supervisor-delete:[0-9a-f]{64}$'
        $confirmed.shutdown_receipt_key | Should Match '^watch-fleet-shutdown:[0-9a-f]{64}$'

        $recorded = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -FinalRecheck -ConfirmSupervisorDeleted -AutomationRoot $automationRoot -ConfirmedShutdownReceiptKey $confirmed.shutdown_receipt_key -CurrentTickId $secondTick @coverage
        $recorded.reason_code | Should Be 'shutdown_receipt_recorded'
        $recorded.power_action | Should Be 'observe_only'
        $recorded.successful_shutdown_receipt_count | Should Be 1

        $replayed = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -FinalRecheck -ConfirmSupervisorDeleted -AutomationRoot $automationRoot -ConfirmedShutdownReceiptKey $confirmed.shutdown_receipt_key -CurrentTickId $secondTick @coverage
        $replayed.reason_code | Should Be 'shutdown_already_scheduled'
        $replayed.power_action | Should Be 'observe_only'
        $replayed.successful_shutdown_receipt_count | Should Be 1
    }

    It 'does not accept a shutdown receipt without the armed candidate and supervisor-delete proof' {
        $now = [datetimeoffset]::UtcNow
        $snapshot = @([ordered]@{ target_thread_id='a'; automation_id='automation-target-a'; source_turn_id='turn-source-a'; state='complete'; task_stopped=$true; stop_reason='complete'; recovery_pending=$false; receipt_key=$script:receiptA; checkpoint_id=$script:checkpointA; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress

        $result = & $script:disposition -SnapshotJson $snapshot -AutomationId $script:supervisorAutomationId -CurrentTickId $now.ToString('o') -ConfirmedShutdownReceiptKey ('watch-fleet-shutdown:' + ('a' * 64))
        $result.power_action | Should Be 'observe_only'
        $result.reason_code | Should Be 'shutdown_not_armed'
        $result.successful_shutdown_receipt_count | Should Be 0
    }
}
