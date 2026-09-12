BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src/Domain/OperationPlan.ps1')
    . (Join-Path $repoRoot 'src/Application/GlobalRuleProjection.ps1')
}

Describe 'Checked-in rule content' {
    It 'validates shared global sections, versions, and budgets without projecting' {
        $codex = Join-Path $TestDrive 'codex'
        $claude = Join-Path $TestDrive 'claude'
        New-Item -ItemType Directory -Path $codex, $claude -Force | Out-Null
        $result = Test-GlobalRuleSourceFamily $repoRoot $codex $claude
        $result.pass | Should -BeTrue -Because ($result.findings.code -join ', ')
        @($result.observations).Count | Should -Be 0
        (@(git -C $repoRoot check-attr eol -- rules/global/codex/AGENTS.md rules/global/claude/CLAUDE.md rules/global/zcode/AGENTS.md) -join "`n") | Should -Match 'eol: lf'
    }

    It 'retains the cold-routing execution and observation boundaries' {
        foreach ($path in @('rules/global/claude/CLAUDE.md', 'rules/global/zcode/AGENTS.md')) {
            $text = [IO.File]::ReadAllText((Join-Path $repoRoot $path))
            foreach ($contract in @('capability-router', 'one_shot', 'multi_turn_user_decision', 'parent-mediated', 'not_observable')) {
                $text | Should -Match ([regex]::Escape($contract))
            }
        }
    }

    It 'keeps the project contract bounded and its Claude wrapper canonical' {
        $facts = Get-GlobalRuleFileFacts (Join-Path $repoRoot 'AGENTS.md')
        $facts.bytes | Should -BeLessOrEqual 10240
        $facts.lines | Should -BeLessOrEqual 80
        $facts.text | Should -Match '\*\*项目契约\*\*:\s*2\.0'
        $wrapper = Get-GlobalRuleFileFacts (Join-Path $repoRoot 'CLAUDE.md')
        $wrapper.bom | Should -BeFalse
        ($wrapper.text -split '\r?\n')[0] | Should -Be '@AGENTS.md'
    }
}
