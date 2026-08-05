Describe 'watch-interrupted-task fleet supervisor contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $generator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'
        $script:prompt = & $generator -SupervisorThreadId 'supervisor-test'
    }

    It 'continuously observes all newly eligible visible local tasks' {
        $script:prompt | Should Match 'watch-interrupted-task:fleet:v1 supervisor_thread_id=supervisor-test'
        $script:prompt | Should Match 'policy_revision=2'
        $script:prompt | Should Match 'prompt_sha256=[0-9a-f]{64}'
        $script:prompt | Should Match 'every scheduled run'
        $script:prompt | Should Match 'newly eligible'
        $script:prompt | Should Match 'at most 50'
    }

    It 'pins the fleet to the user-selected read-only operating mode' {
        $script:prompt | Should Match 'operating_mode=supervisor_monitor_only'
        $script:prompt | Should Match 'New-WatchHeartbeatPrompt.ps1'
        $script:prompt | Should Match 'target contract.*exact silence rule "entire assistant output must be exactly DONT_NOTIFY"'
        $script:prompt | Should Match 'do not create, update, activate, pause, or delete target automations under any runtime result'
        $script:prompt | Should Match 'must not leave this mode automatically'
        $script:prompt | Should -Not -Match 'live-probe sentinel'
        $script:prompt | Should -Not -Match 'delete completed orphan heartbeats'
    }

    It 'also protects its host task because Desktop permits one heartbeat per task' {
        $script:prompt | Should Match 'at most one heartbeat automation'
        $script:prompt | Should Match 'dual-role'
        $script:prompt | Should Match 'Never create a separate target heartbeat for the supervisor thread'
        $script:prompt | Should Match 'classify the supervisor thread.*latest non-heartbeat business turn'
        $script:prompt | Should Match 'supervisor automation counts as that task''s one heartbeat'
    }

    It 'never injects a peer message and observes only while the guard is soft' {
        $script:prompt | Should Match 'Never call send_message_to_thread'
        $script:prompt | Should Match 'Never hand off, wake, create, fork, rename'
        $script:prompt | Should Match 'soft_guard_only'
        $script:prompt | Should Match 'observe only'
    }

    It 'does not publish routine reconciliation chatter' {
        $script:prompt | Should Match 'do not emit commentary, status, progress, or a summary'
        $script:prompt | Should Match 'entire assistant output must be exactly DONT_NOTIFY'
    }

    It 'classifies completion without cleanup or delayed success chatter' {
        $script:prompt | Should Match 'contextCompaction handoff summary'
        $script:prompt | Should Match 'historical verification'
        $script:prompt | Should Match 'target heartbeat final answer'
        $script:prompt | Should Match 'never claim that a target automation was deleted'
        $script:prompt | Should Match 'completion is not a new user-action boundary'
    }
}
