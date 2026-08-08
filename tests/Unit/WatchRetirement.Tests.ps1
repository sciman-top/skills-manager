Describe 'watch-interrupted-task retirement contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:skill = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\SKILL.md')
        $script:metadata = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\agents\openai.yaml')
        $script:config = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
    }

    It 'removes the legacy watch from the resident skill set' {
        @($script:config.skill_projection.resident_names) | Should Not Contain 'watch-interrupted-task'
    }

    It 'fails closed and forbids every legacy lifecycle activation' {
        $script:skill | Should Match 'runtime_status=retired_fail_closed'
        $script:skill | Should Match 'Never create, arm, enable, resume, reactivate, update, clone, or schedule'
        $script:skill | Should Match 'Never emit heartbeat XML'
        $script:skill | Should Match 'Never execute `shutdown\.exe`'
    }

    It 'exposes only cleanup-oriented host metadata' {
        $script:metadata | Should Match '旧守夜退役入口'
        $script:metadata | Should Match 'never create, arm, resume, or update a watch'
        $script:metadata | Should Not Match 'recover this task'
    }
}
