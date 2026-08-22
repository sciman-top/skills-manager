BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')

}
Describe 'Host-profile rule discovery' {
    BeforeAll {
function New-RuleFixture([string]$Name) {
        $root = Join-Path $TestDrive $Name
        $repo = Join-Path $root 'repo'
        $sub = Join-Path $repo 'src\feature'
        $user = Join-Path $root 'user'
        New-Item -ItemType Directory -Path $sub, $user -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $user 'AGENTS.md') -Value '# global' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Value '# repo' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $sub 'AGENTS.override.md') -Value '# override' -Encoding UTF8
        return [pscustomobject]@{ root = $root; repo = $repo; sub = $sub; user = $user }
    }
}

    It 'discovers the bounded Codex global to subtree chain with observed precedence' {
        $fixture = New-RuleFixture 'codex-chain'
        $result = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.sub -HostName codex -UserRuleRoot $fixture.user

        @($result.documents).Count | Should -Be 3
        (@($result.documents.scope) -join ',') | Should -Be 'global,repo,override'
        @($result.documents | Where-Object discovery_state -eq observed).Count | Should -Be 3
        $result.load_verification | Should -Be 'not_run'
        $result.writes | Should -Be 0
    }

    It 'selects configured fallback only when higher-priority Codex files are absent' {
        $fixture = New-RuleFixture 'fallback'
        Remove-Item -LiteralPath (Join-Path $fixture.repo 'AGENTS.md')
        Set-Content -LiteralPath (Join-Path $fixture.repo 'PROJECT.md') -Value '# fallback' -Encoding UTF8
        $result = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.repo -HostName codex -FallbackNames @('PROJECT.md')

        @($result.documents).Count | Should -Be 1
        $result.documents[0].path | Should -Match 'PROJECT\.md$'
    }

    It 'skips an empty global override and selects the first non-empty Codex rule' {
        $fixture = New-RuleFixture 'empty-global-override'
        [IO.File]::WriteAllText((Join-Path $fixture.user 'AGENTS.override.md'), " `t")

        $result = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.repo -HostName codex -UserRuleRoot $fixture.user

        $result.documents[0].path | Should -Be (Join-Path $fixture.user 'AGENTS.md')
        @($result.candidates | Where-Object { $_.path -match 'AGENTS\.override\.md$' -and $_.reason -eq 'empty_candidate' }).Count | Should -BeGreaterThan 0
    }

    It 'skips an empty project override and selects the next non-empty Codex rule' {
        $fixture = New-RuleFixture 'empty-project-override'
        [IO.File]::WriteAllText((Join-Path $fixture.repo 'AGENTS.override.md'), "
`t")

        $result = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.repo -HostName codex

        $result.documents[0].path | Should -Be (Join-Path $fixture.repo 'AGENTS.md')
        @($result.candidates | Where-Object { $_.path -match 'AGENTS\.override\.md$' -and $_.reason -eq 'empty_candidate' }).Count | Should -Be 1
    }

    It 'marks Claude precedence inferred instead of copying Codex semantics' {
        $fixture = New-RuleFixture 'claude'
        Set-Content -LiteralPath (Join-Path $fixture.user 'CLAUDE.md') -Value '# global claude' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $fixture.repo 'CLAUDE.md') -Value '# repo claude' -Encoding UTF8
        $result = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.repo -HostName claude -UserRuleRoot $fixture.user

        @($result.documents).Count | Should -Be 2
        @($result.documents | Where-Object discovery_state -eq inferred).Count | Should -BeGreaterThan 0
        @($result.documents | Where-Object { $null -ne $_.precedence }).Count | Should -Be 1
    }

    It 'models ZCode as user AGENTS plus the Workspace-root AGENTS only' {
        $fixture = New-RuleFixture 'zcode'
        $result = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.sub -HostName zcode -UserRuleRoot $fixture.user

        @($result.documents).Count | Should -Be 2
        (@($result.documents.scope) -join ',') | Should -Be 'global,repo'
        @($result.documents | Where-Object discovery_state -eq observed).Count | Should -Be 2
        @($result.candidates | Where-Object { $_.path -match 'src\\feature\\AGENTS\.md$' }).Count | Should -Be 0
    }

    It 'records budget truncation without claiming files were loaded' {
        $fixture = New-RuleFixture 'budget'
        $result = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.sub -HostName codex -UserRuleRoot $fixture.user -MaxCombinedBytes 1

        @($result.truncated_paths).Count | Should -Be 3
        $result.combined_bytes | Should -Be 0
        $result.load_verification | Should -Be 'not_run'
    }

    It 'fails closed when current directory escapes the authorized repo root' {
        $fixture = New-RuleFixture 'escape'
        { Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.user -HostName codex } | Should -Throw
    }

    It 'does not modify discovered rule files' {
        $fixture = New-RuleFixture 'hash-stable'
        $before = (Get-FileHash -LiteralPath (Join-Path $fixture.repo 'AGENTS.md') -Algorithm SHA256).Hash
        $null = Get-RuleDiscovery -RepoRoot $fixture.repo -CurrentDirectory $fixture.sub -HostName codex -UserRuleRoot $fixture.user
        $after = (Get-FileHash -LiteralPath (Join-Path $fixture.repo 'AGENTS.md') -Algorithm SHA256).Hash

        $after | Should -Be $before
    }
}
