Describe 'watch-interrupted-task fleet supervisor contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $generator = Join-Path $repoRoot 'overrides\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'
        $script:prompt = & $generator -SupervisorThreadId 'supervisor-test'
    }

    It 'continuously reconciles all newly eligible visible local tasks' {
        $script:prompt | Should Match 'watch-interrupted-task:fleet:v1 supervisor_thread_id=supervisor-test'
        $script:prompt | Should Match 'policy_revision=2'
        $script:prompt | Should Match 'prompt_sha256=[0-9a-f]{64}'
        $script:prompt | Should Match 'every scheduled run'
        $script:prompt | Should Match 'newly eligible'
        $script:prompt | Should Match 'at most 50'
    }

    It 'is the sole automation writer and reconciles idempotently' {
        $script:prompt | Should Match 'sole automation writer'
        $script:prompt | Should Match 'exactly one target heartbeat'
        $script:prompt | Should Match 'New-WatchHeartbeatPrompt.ps1'
        $script:prompt | Should Match 'delete completed orphan heartbeats'
    }

    It 'never injects a peer message and observes only while the guard is soft' {
        $script:prompt | Should Match 'Never call send_message_to_thread'
        $script:prompt | Should Match 'Never hand off, wake, create, fork, rename'
        $script:prompt | Should Match 'soft_guard_only'
        $script:prompt | Should Match 'observe only'
    }
}
