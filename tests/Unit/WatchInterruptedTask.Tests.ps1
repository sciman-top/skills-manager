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
    }

    It 'enables reviewed revision-3 conditional recovery instead of observe-only mode' {
        $script:skill | Should Match 'operating_mode=conditional_recovery'
        $script:prompt | Should Match 'operating_mode=conditional_recovery'
        $script:prompt | Should Match 'policy_revision=3'
        $script:prompt | Should Match 'resume_from_checkpoint'
        $script:prompt | Should -Not -Match 'classification is observation only'
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
            -GoalStatus active -HasPositiveEvidence -EvidenceTimestampUtc $now -CheckpointId 'cp-1' `
            -ReceiptKey 'receipt-1' -ExternalEffectState safe

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
                CheckpointId = 'cp-1'
                ReceiptKey = 'receipt-1'
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
            $blocked.reason_code | Should Match 'missing_|external_effect'
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
            -GoalStatus active -HasPositiveEvidence -EvidenceTimestampUtc $now -CheckpointId 'cp-2' `
            -ReceiptKey 'receipt-2' -ExternalEffectState none
        $repair.task_action | Should Be 'diagnose_replan_and_continue'
        $repair.goal_action | Should Be 'keep_active'

        $drift = & $dispositionScriptPath -State strategy_drift -OperatingMode conditional_recovery `
            -GoalStatus active -HasPositiveEvidence -EvidenceTimestampUtc $now -CheckpointId 'cp-3' `
            -ReceiptKey 'receipt-3' -ExternalEffectState none
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
        $proved.automation_action | Should Be 'request_supervisor_cleanup'
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
        $script:prompt | Should -Not -Match 'entire assistant output must be exactly DONT_NOTIFY'
    }

    It 'never uses cross-task messaging or blindly replays external effects' {
        $script:prompt | Should Match 'Never call send_message_to_thread'
        $script:prompt | Should Match 'Never replay external side effects'
        $script:prompt | Should Match 'read-only list/read/wait'
        $script:recoveryDesign | Should Match 'idempotency'
        $script:recoveryDesign | Should Match 'Retry-After'
    }
}
