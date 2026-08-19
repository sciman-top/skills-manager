BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $runnerPath = Join-Path $repoRoot 'scripts\weekly-skills-update.ps1'
}

Describe 'Weekly skills-only update automation' {
    It 'updates and commits only the skills lock without MCP or push mutations' {
        $text = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

        $text | Should -Match "'check-updates', '--json'"
        $text | Should -Match "'更新', '-Upgrade'"
        $text | Should -Match "'add', '--', 'skills.lock.json'"
        $text | Should -Not -Match '同步MCP'
        $text | Should -Not -Match "'push'"
    }

    It 'requires a clean main worktree and rejects unexpected tracked writes' {
        $text = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

        $text | Should -Match "branch -ne 'main'"
        $text | Should -Match 'tracked_worktree_dirty'
        $text | Should -Match 'unexpected tracked write set'
        $text | Should -Match 'FileShare]::None'
    }
}
