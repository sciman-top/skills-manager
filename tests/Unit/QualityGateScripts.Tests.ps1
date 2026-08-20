Describe 'Proportional quality gate profiles' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:gate = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\quality\run-local-quality-gates.ps1') -Raw
    }

    It 'has a docs-only path that performs diff checking without build or tests' {
        $script:gate | Should -Match "ValidateSet\('docs', 'quick', 'focused', 'full'\)"
        $script:gate | Should -Match "Profile -eq 'docs'"
        $script:gate | Should -Match 'git diff --check'
        $script:gate | Should -Match 'DiffBase'
    }

    It 'requires an explicit test slice for focused gates and passes name filters through' {
        $script:gate | Should -Match "Profile -eq 'focused'"
        $script:gate | Should -Match 'Focused profile requires -TestPath or -TestName'
        $script:gate | Should -Match 'tests\\run\.ps1 -TestPath \$TestPath -TestName \$TestName'
        $script:gate | Should -Match 'TestName'
        $script:gate | Should -Match "Profile -eq 'focused'"
    }
}
