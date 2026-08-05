Describe 'watch-interrupted-task fleet supervisor revision-3 contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $generator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'
        $disposition = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\Get-WatchFleetShutdownDisposition.ps1'
        $script:prompt = & $generator -SupervisorThreadId 'supervisor-test'
        $script:shutdownPrompt = & $generator -SupervisorThreadId 'supervisor-test' -ShutdownWhenAllStopped
        $script:disposition = $disposition
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

    It 'recovers its own hosted task directly but never creates a duplicate heartbeat for itself' {
        $script:prompt | Should Match 'dual-role'
        $script:prompt | Should Match 'apply the target recovery contract to the supervisor thread itself'
        $script:prompt | Should Match 'Never create a separate target heartbeat for the supervisor thread'
        $script:prompt | Should Match 'cannot mutate its own automation'
    }

    It 'limits fleet writes to canonical provenance and verified cleanup' {
        $script:prompt | Should Match 'trusted canonical target body digest'
        $script:prompt | Should Match 'fresh host metadata'
        $script:prompt | Should Match 'delete only after verified completion'
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
        $script:shutdownPrompt | Should Match 'shutdown\.exe /s /t 120'
        $script:shutdownPrompt | Should Match 'Never add /f'
        $script:shutdownPrompt | Should Match 'shutdown /a'

        $standardJson = ((& $generator -SupervisorThreadId 'json-supervisor' -AsJson) | ConvertFrom-Json)
        $shutdownJson = ((& $generator -SupervisorThreadId 'json-supervisor' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json)
        $shutdownJson.shutdown_when_all_stopped | Should Be $true
        $shutdownJson.prompt_sha256 | Should Not Be $standardJson.prompt_sha256
    }

    It 'requires a non-empty fresh all-stopped snapshot twice and deduplicates shutdown' {
        $now = [datetimeoffset]::UtcNow
        $snapshot = @(
            [ordered]@{ target_thread_id='a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key='receipt-a'; checkpoint_id='done-a'; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true },
            [ordered]@{ target_thread_id='b'; state='needs_input'; task_stopped=$true; stop_reason='human_input_required'; recovery_pending=$false; receipt_key='receipt-b'; checkpoint_id='wait-b'; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='safe'; next_retry_at=''; no_active_turn=$true }
        ) | ConvertTo-Json -Depth 8 -Compress

        $first = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -NowUtc $now.ToString('o')
        $first.power_action | Should Be 'observe_only'
        $first.reason_code | Should Be 'stability_confirmation_required'

        $second = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -NowUtc $now.ToString('o') -PreviousSnapshotKey $first.snapshot_key
        $second.power_action | Should Be 'schedule_shutdown'
        $second.reason_code | Should Be 'all_monitored_tasks_stopped'
        $second.shutdown_receipt_key | Should Match '^watch-fleet-shutdown:[0-9a-f]{64}$'

        $deduplicated = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -NowUtc $now.ToString('o') -PreviousSnapshotKey $first.snapshot_key -PriorShutdownReceiptKey $second.shutdown_receipt_key
        $deduplicated.power_action | Should Be 'observe_only'
        $deduplicated.reason_code | Should Be 'shutdown_already_scheduled'
    }

    It 'accepts any proved stop reason without depending on Goal presence or a finite state allowlist' {
        $now = [datetimeoffset]::UtcNow
        $snapshot = @([ordered]@{
            target_thread_id='custom-stop'
            state='user_cancelled'
            task_stopped=$true
            stop_reason='user_cancelled'
            recovery_pending=$false
            receipt_key='receipt-custom'
            checkpoint_id='cancelled'
            evidence_timestamp_utc=$now.ToString('o')
            external_effect_state='none'
            next_retry_at=''
            no_active_turn=$true
        }) | ConvertTo-Json -Compress

        $first = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -NowUtc $now.ToString('o')
        $second = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -NowUtc $now.ToString('o') -PreviousSnapshotKey $first.snapshot_key
        $second.power_action | Should Be 'schedule_shutdown'
        $second.reason_code | Should Be 'all_monitored_tasks_stopped'
    }

    It 'blocks shutdown for transient recovery active retry unknown stale or empty snapshots' {
        $now = [datetimeoffset]::UtcNow
        foreach ($case in @(
            @{ State='resume_eligible'; Retry=''; Expected='recovery_or_retry_pending' },
            @{ State='running'; Retry=''; Expected='target_running' },
            @{ State='unknown'; Retry=''; Expected='target_state_unproved' },
            @{ State='complete'; Retry=$now.AddMinutes(2).ToString('o'); Expected='retry_scheduled' }
        )) {
            $snapshot = @([ordered]@{ target_thread_id='a'; state=$case.State; task_stopped=$true; stop_reason='claimed_stop'; recovery_pending=$false; receipt_key='receipt'; checkpoint_id='cp'; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=$case.Retry; no_active_turn=$true }) | ConvertTo-Json -Compress
            $result = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -NowUtc $now.ToString('o') -PreviousSnapshotKey 'irrelevant'
            $result.power_action | Should Be 'observe_only'
            $result.reason_code | Should Be $case.Expected
        }

        $empty = & $script:disposition -SnapshotJson '[]' -ShutdownArmed -NowUtc $now.ToString('o')
        $empty.reason_code | Should Be 'monitored_set_empty'

        $staleSnapshot = @([ordered]@{ target_thread_id='a'; state='complete'; task_stopped=$true; stop_reason='acceptance_complete'; recovery_pending=$false; receipt_key='receipt'; checkpoint_id='cp'; evidence_timestamp_utc=$now.AddHours(-1).ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
        $stale = & $script:disposition -SnapshotJson $staleSnapshot -ShutdownArmed -NowUtc $now.ToString('o')
        $stale.reason_code | Should Be 'stop_evidence_stale'
    }

    It 'requires explicit stopped and non-recovery proof even for otherwise terminal states' {
        $now = [datetimeoffset]::UtcNow
        foreach ($case in @(
            @{ Stopped=$false; Recovery=$false; Reason='complete'; Expected='stop_decision_unproved' },
            @{ Stopped=$true; Recovery=$true; Reason='complete'; Expected='recovery_or_retry_pending' },
            @{ Stopped=$true; Recovery=$false; Reason=''; Expected='stop_reason_invalid' }
        )) {
            $snapshot = @([ordered]@{ target_thread_id='a'; state='complete'; task_stopped=$case.Stopped; stop_reason=$case.Reason; recovery_pending=$case.Recovery; receipt_key='receipt'; checkpoint_id='cp'; evidence_timestamp_utc=$now.ToString('o'); external_effect_state='none'; next_retry_at=''; no_active_turn=$true }) | ConvertTo-Json -Compress
            $result = & $script:disposition -SnapshotJson $snapshot -ShutdownArmed -NowUtc $now.ToString('o')
            $result.reason_code | Should Be $case.Expected
        }
    }
}
