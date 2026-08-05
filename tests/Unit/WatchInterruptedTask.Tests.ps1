Describe 'watch-interrupted-task conditional recovery contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $skillPath = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\SKILL.md'
        $promptScriptPath = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'
        $dispositionScriptPath = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\Get-WatchHeartbeatDisposition.ps1'
        $recoveryDesignPath = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\references\recovery-design.md'
        $script:skill = Get-Content -Raw -LiteralPath $skillPath
        $script:recoveryDesign = Get-Content -Raw -LiteralPath $recoveryDesignPath
        $script:prompt = & $promptScriptPath -TargetThreadId 'target-test'
        $script:checkpoint = 'watch-checkpoint:' + ('c' * 64)
        $script:receipt = 'watch-receipt:' + ('d' * 64)
    }

    It 'enables reviewed revision-3 conditional recovery instead of observe-only mode' {
        $script:skill | Should Match 'operating_mode=conditional_recovery'
        $script:prompt | Should Match 'operating_mode=conditional_recovery'
        $script:prompt | Should Match 'policy_revision=3'
        $script:prompt | Should Match 'resume_from_checkpoint'
        $script:prompt | Should -Not -Match 'classification is observation only'
    }

    It 'never lets stale heartbeat instructions hijack a direct user turn after compaction' {
        $script:prompt | Should Match 'current user input itself is the native heartbeat envelope'
        $script:prompt | Should Match 'After any context compaction.*re-check'
        $script:prompt | Should Match 'direct user or business message'
        $script:prompt | Should Match 'do not emit heartbeat XML'
        $script:prompt | Should Match 'ignore stale heartbeat instructions'
    }

    It 'treats an active Goal as persisted intent but not completion evidence' {
        $script:skill | Should Match 'Goal Contract'
        $script:skill | Should Match 'Outcome.*Scope.*Acceptance.*Checkpoints.*Evidence'
        $script:prompt | Should Match 'get_goal'
        $script:prompt | Should Match 'active Goal alone is not completion evidence'
        $script:prompt | Should Match 'do not replace or clear an existing Goal'
        $script:prompt | Should Match 'three consecutive Goal turns'
    }

    It 'lets the host synthesize a bounded Goal Contract only after explicit Goal opt-in' {
        $script:skill | Should Match '目标守夜'
        $script:skill | Should Match 'explicitly requests Goal mode'
        $script:skill | Should Match 'must not silently rewrite the user intent'
        $script:skill | Should Match '4,000'
        $script:skill | Should Match 'measurable acceptance'
    }

    It 'requires structured recovery evidence, checkpoint, idempotency, and safe external-effect truth' {
        $now = [DateTime]::UtcNow.ToString('o')
        $result = & $dispositionScriptPath -State resume_eligible -OperatingMode conditional_recovery `
            -GoalStatus active -HasPositiveEvidence -EvidenceTimestampUtc $now -CheckpointId $script:checkpoint `
            -ReceiptKey $script:receipt -ExternalEffectState safe

        $result.task_action | Should Be 'resume_from_checkpoint'
        $result.goal_action | Should Be 'keep_active'
        $result.requires_receipt | Should Be $true
        $result.reason_code | Should Be 'recovery_authorized'

        foreach ($missing in @('evidence', 'checkpoint', 'receipt', 'external')) {
            $params = @{
                State = 'resume_eligible'
                OperatingMode = 'conditional_recovery'
                GoalStatus = 'active'
                HasPositiveEvidence = $true
                EvidenceTimestampUtc = $now
                CheckpointId = $script:checkpoint
                ReceiptKey = $script:receipt
                ExternalEffectState = 'safe'
            }
            switch ($missing) {
                'evidence' { $params.HasPositiveEvidence = $false }
                'checkpoint' { $params.CheckpointId = '' }
                'receipt' { $params.ReceiptKey = '' }
                'external' { $params.ExternalEffectState = 'unknown' }
            }
            $blocked = & $dispositionScriptPath @params
            $blocked.task_action | Should Be 'observe_only'
            $blocked.reason_code | Should Match 'missing_|invalid_|external_effect'
        }
    }

    It 'keeps monitor mode and paused or terminal Goals fail closed' {
        $now = [DateTime]::UtcNow.ToString('o')
        foreach ($case in @(
            @{ Mode = 'supervisor_monitor_only'; Goal = 'active' },
            @{ Mode = 'conditional_recovery'; Goal = 'paused' },
            @{ Mode = 'conditional_recovery'; Goal = 'complete' },
            @{ Mode = 'conditional_recovery'; Goal = 'blocked' }
        )) {
            $result = & $dispositionScriptPath -State continuation_gap -OperatingMode $case.Mode `
                -GoalStatus $case.Goal -HasPositiveEvidence -EvidenceTimestampUtc $now `
                -CheckpointId 'cp-1' -ReceiptKey 'receipt-1' -ExternalEffectState safe
            $result.task_action | Should Be 'observe_only'
        }
    }

    It 'diagnoses recoverable failures and strategy drift without changing the Goal objective' {
        $now = [DateTime]::UtcNow.ToString('o')
        $repair = & $dispositionScriptPath -State recoverable_task_failure -OperatingMode conditional_recovery `
            -GoalStatus active -HasPositiveEvidence -EvidenceTimestampUtc $now -CheckpointId $script:checkpoint `
            -ReceiptKey $script:receipt -ExternalEffectState none
        $repair.task_action | Should Be 'diagnose_replan_and_continue'
        $repair.goal_action | Should Be 'keep_active'

        $drift = & $dispositionScriptPath -State strategy_drift -OperatingMode conditional_recovery `
            -GoalStatus active -HasPositiveEvidence -EvidenceTimestampUtc $now -CheckpointId $script:checkpoint `
            -ReceiptKey $script:receipt -ExternalEffectState none
        $drift.task_action | Should Be 'reconcile_goal_and_continue'
        $drift.goal_action | Should Be 'keep_active'
    }

    It 'verifies acceptance before stopping and marking an active Goal complete' {
        $unproved = & $dispositionScriptPath -State goal_satisfied -OperatingMode conditional_recovery -GoalStatus active
        $unproved.task_action | Should Be 'verify_goal_acceptance'
        $unproved.goal_action | Should Be 'keep_active'

        $proved = & $dispositionScriptPath -State goal_satisfied -OperatingMode conditional_recovery -GoalStatus active -AcceptanceVerified
        $proved.task_action | Should Be 'stop_after_verification'
        $proved.goal_action | Should Be 'mark_complete'
        $proved.automation_action | Should Be 'keep_active'
    }

    It 'requests cleanup for every proved stable stop regardless of Goal presence or stop reason' {
        $now = [DateTime]::UtcNow.ToString('o')
        foreach ($case in @(
            @{ State = 'natural_pause'; Goal = 'none'; Reason = 'user_checkpoint'; Notify = 'dont_notify' },
            @{ State = 'natural_pause'; Goal = 'active'; Reason = 'user_checkpoint_goal'; Notify = 'dont_notify' },
            @{ State = 'needs_input'; Goal = 'paused'; Reason = 'human_input_required'; Notify = 'notify_once' },
            @{ State = 'complete'; Goal = 'complete'; Reason = 'acceptance_complete'; Notify = 'dont_notify' },
            @{ State = 'non_transient_failure'; Goal = 'blocked'; Reason = 'auth_failed_terminal'; Notify = 'notify_once' },
            @{ State = 'stopped'; Goal = 'active'; Reason = 'user_cancelled_custom'; Notify = 'dont_notify' }
        )) {
            $accepted = & $dispositionScriptPath -State $case.State -OperatingMode conditional_recovery -GoalStatus $case.Goal `
                -TaskStopped -StopReason $case.Reason -HasPositiveEvidence -EvidenceTimestampUtc $now `
                -CheckpointId $script:checkpoint -ReceiptKey $script:receipt `
                -ExternalEffectState none -NoActiveTurn
            $accepted.automation_action | Should Be 'request_supervisor_cleanup'
            $accepted.notification_action | Should Be $case.Notify
            $accepted.requires_receipt | Should Be $true
            $accepted.reason_code | Should Be 'proved_stopped_cleanup_ready'
        }
    }

    It 'keeps stopped cleanup fail closed without fresh complete safe stop evidence' {
        $now = [DateTime]::UtcNow.ToString('o')
        $base = @{
            State = 'natural_pause'
            OperatingMode = 'conditional_recovery'
            GoalStatus = 'none'
            TaskStopped = $true
            StopReason = 'user_checkpoint'
            RecoveryPending = $false
            HasPositiveEvidence = $true
            EvidenceTimestampUtc = $now
            CheckpointId = $script:checkpoint
            ReceiptKey = $script:receipt
            ExternalEffectState = 'none'
            NoActiveTurn = $true
            NextRetryAt = ''
        }

        foreach ($case in @(
            @{ Name = 'not-stopped'; Change = { param($p) $p.TaskStopped = $false }; Expected = 'stop_decision_unproved' },
            @{ Name = 'recovery'; Change = { param($p) $p.RecoveryPending = $true }; Expected = 'recovery_or_retry_pending' },
            @{ Name = 'retry'; Change = { param($p) $p.NextRetryAt = $now }; Expected = 'recovery_or_retry_pending' },
            @{ Name = 'active-turn'; Change = { param($p) $p.NoActiveTurn = $false }; Expected = 'active_turn_present_or_unproved' },
            @{ Name = 'reason'; Change = { param($p) $p.StopReason = '' }; Expected = 'stop_reason_invalid' },
            @{ Name = 'receipt'; Change = { param($p) $p.ReceiptKey = '' }; Expected = 'invalid_receipt_key' },
            @{ Name = 'external'; Change = { param($p) $p.ExternalEffectState = 'unsafe' }; Expected = 'external_effect_unproved' }
        )) {
            $params = @{} + $base
            & $case.Change $params
            $blocked = & $dispositionScriptPath @params
            $blocked.automation_action | Should Be 'keep_active'
            $blocked.reason_code | Should Be $case.Expected
        }
    }

    It 'never cleans up a recovery running or unknown state even when stopped fields contradict it' {
        $now = [DateTime]::UtcNow.ToString('o')
        foreach ($state in @(
            'running', 'resume_eligible', 'continuation_gap', 'recoverable_task_failure',
            'strategy_drift', 'verification_failed', 'peer_busy', 'unknown',
            'soft_guard_only', 'stale_policy_running', 'goal_satisfied'
        )) {
            $blocked = & $dispositionScriptPath -State $state -OperatingMode conditional_recovery -GoalStatus active `
                -TaskStopped -StopReason 'contradictory_stop' -HasPositiveEvidence -EvidenceTimestampUtc $now `
                -CheckpointId 'cp' -ReceiptKey 'receipt' -ExternalEffectState none -NoActiveTurn
            $blocked.automation_action | Should Be 'keep_active'
        }
    }

    It 'marks a Goal blocked only after the same proved impasse repeats for three turns' {
        $early = & $dispositionScriptPath -State needs_input -OperatingMode conditional_recovery -GoalStatus active `
            -ConsecutiveSameBlockCount 2 -SameBlockingConditionConfirmed -NoMeaningfulProgressPossible
        $early.goal_action | Should Be 'keep_active'

        $blocked = & $dispositionScriptPath -State needs_input -OperatingMode conditional_recovery -GoalStatus active `
            -ConsecutiveSameBlockCount 3 -SameBlockingConditionConfirmed -NoMeaningfulProgressPossible
        $blocked.goal_action | Should Be 'mark_blocked'
        $blocked.task_action | Should Be 'stop_for_user'
    }

    It 'outputs real JSON across a fresh pwsh process when AsJson is requested' {
        $command = "& '$promptScriptPath' -TargetThreadId 'json-test' -AsJson"
        $raw = & pwsh -NoProfile -Command $command
        $json = (@($raw) -join "`n") | ConvertFrom-Json
        $json.target_thread_id | Should Be 'json-test'
        $json.policy_revision | Should Be 3
        $json.prompt_sha256 | Should Match '^[0-9a-f]{64}$'
        $json.prompt | Should Match 'policy_revision=3'
    }

    It 'uses the native heartbeat XML response contract with durable receipt metadata' {
        $script:prompt | Should Match '<heartbeat>'
        $script:prompt | Should Match '<automation_id>'
        $script:prompt | Should Match '<decision>DONT_NOTIFY\|NOTIFY</decision>'
        $script:prompt | Should Match '<message>'
        $script:prompt | Should Match 'receipt_key'
        $script:prompt | Should Match 'task_stopped=true\|false'
        $script:prompt | Should Match 'stop_reason'
        $script:prompt | Should Match 'recovery_pending=true\|false'
        $script:prompt | Should Match 'automation_action=request_supervisor_cleanup'
        $script:prompt | Should Match 'evidence_timestamp_utc'
        $script:prompt | Should Match 'external_effect_state'
        $script:prompt | Should Match 'no_active_turn=true\|false'
        $script:prompt | Should -Not -Match 'entire assistant output must be exactly DONT_NOTIFY'
    }

    It 'never uses cross-task messaging or blindly replays external effects' {
        $script:prompt | Should Match 'Never call send_message_to_thread'
        $script:prompt | Should Match 'Never replay external side effects'
        $script:prompt | Should Match 'read-only list/read/wait'
        $script:recoveryDesign | Should Match 'idempotency'
        $script:recoveryDesign | Should Match 'Retry-After'
    }

    It 'keeps fleet shutdown separately armed and never equates transient interruption with stopped' {
        $script:skill | Should Match 'Automatic computer shutdown is a distinct, direct-user fleet lifecycle mode'
        $script:skill | Should Match 'ShutdownWhenAllStopped'
        $script:skill | Should Match 'does not maintain a finite allowlist of stop reasons'
        $script:skill | Should Match 'task_stopped=true'
        $script:skill | Should Match 'recovery_pending=false'
        $script:recoveryDesign | Should Match 'Goal presence does not change fleet aggregation'
        $script:recoveryDesign | Should Match 'resume_eligible.*continuation_gap.*recoverable_task_failure'
        $script:recoveryDesign | Should Match 'two consecutive.*ticks'
        $script:recoveryDesign | Should Match 'shutdown\.exe /s /t 120'
        $script:recoveryDesign | Should Match 'shutdown /a'
    }
}
