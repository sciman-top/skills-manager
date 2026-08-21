Describe 'GitHub CI workflow supply-chain contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:workflow = Get-Content -LiteralPath (Join-Path $repoRoot '.github\workflows\ci.yml') -Raw
    }

    It 'pins checkout and the Pester package bytes and bounds job runtime' {
        $script:workflow | Should -Match 'timeout-minutes:\s*20'
        $script:workflow | Should -Match 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
        $script:workflow | Should -Match 'ensure-test-runtime\.ps1 -CacheRoot \$env:RUNNER_TEMP -ExportToGitHubEnv'
        $bootstrap = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\quality\ensure-test-runtime.ps1') -Raw
        $bootstrap | Should -Match 'Pester/\$version'
        $bootstrap | Should -Match '0207a75ea09f81b27c1ded44898b2bb3c845bafa02045bd64a39e26a53ca41b4'
        $bootstrap | Should -Match 'Get-FileHash[^\r\n]+SHA256'
        $bootstrap | Should -Match '(?s)Get-FileHash.*ExtractToDirectory.*\[IO\.Directory\]::Move\(\$extractRoot, \$moduleRoot\)'
        $bootstrap | Should -Match '\$moduleRoot = Join-Path \$moduleParent \("\{0\}-\{1\}" -f \$version, \$expectedSha256\)'
        $bootstrap | Should -Not -Match '(?m)^\$moduleRoot[^\r\n]+NewGuid'
        $bootstrap | Should -Match '(?m)^\s*\$extractRoot[^\r\n]+NewGuid'
        $bootstrap | Should -Match 'PESTER_610_MANIFEST'
        $script:workflow | Should -Match '(?s)Rebuild locked skill sources.*skills\.ps1 更新 -Locked -SkipHostProjection.*Run repository proportional quality gate'
        $script:workflow | Should -Not -Match 'SkipPublisherCheck'
    }

    It 'avoids duplicate feature-branch push runs while retaining PR main and tag coverage' {
        $script:workflow | Should -Match '(?ms)^on:\s*\r?\n\s+push:\s*\r?\n\s+branches:\s*\r?\n\s+- main\s*\r?\n\s+tags:\s*\r?\n\s+- ''\*''\s*\r?\n\s+pull_request:\s*$'
    }

    It 'runs focused smoke tests for ordinary PR source changes and full for integration or risk paths' {
        $script:workflow | Should -Match "\`$profile = 'quick'"
        $script:workflow | Should -Match 'github\.ref.*refs/tags/'
        $script:workflow | Should -Match "github\.event_name.*-eq 'push'"
        $script:workflow | Should -Match 'github\.event_name.*pull_request'
        $script:workflow | Should -Match 'git diff --name-only \$baseSha HEAD'
        $script:workflow | Should -Match 'CI_GATE_PROFILE=\$profile'
        $script:workflow | Should -Match 'run-local-quality-gates\.ps1 @gateArgs'
        $script:workflow | Should -Match '\$profile = ''focused'''
        $script:workflow | Should -Match 'CI_FOCUSED_TEST_PATHS'
        $script:workflow | Should -Match 'tests/Unit/CiWorkflow\.Tests\.ps1'
        $script:workflow | Should -Match 'tests/E2E/'
        @([regex]::Matches($script:workflow, 'run-local-quality-gates\.ps1')).Count | Should -Be 1

        $riskMatch = [regex]::Match($script:workflow, '\$riskPath = ''([^'']+)''')
        $riskMatch.Success | Should -Be $true
        $riskPath = [regex]::new($riskMatch.Groups[1].Value)
        foreach ($path in @('tests/E2E/Workflow.Tests.ps1', 'rules/global/codex/AGENTS.md', '.github/workflows/ci.yml', 'scripts/quality/run-local-quality-gates.ps1', 'skills.json', 'audit-targets.json')) {
            $riskPath.IsMatch($path) | Should -Be $true
        }
        foreach ($path in @('src/Core.ps1', 'tests/Unit/Core.Tests.ps1', 'README.md', 'README.en.md', 'CONTRIBUTING.md', 'docs/product/README.md')) {
            $riskPath.IsMatch($path) | Should -Be $false
        }
    }

    It 'routes documentation-only changes to the docs profile' {
        $script:workflow | Should -Match '\$profile = ''docs'''
        $script:workflow | Should -Match 'DiffBase'
        $script:workflow | Should -Match 'docsOnly'
        $script:workflow | Should -Match 'CI_DIFF_BASE_SHA=\$baseSha'
    }

    It 'keeps tests read-only and grants release write access only to the tag job' {
        $script:workflow | Should -Match '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$'
        $script:workflow | Should -Match '(?ms)^  release:\s*\r?\n\s+if: startsWith\(github\.ref, ''refs/tags/v''\)\s*\r?\n\s+needs: test'
        $script:workflow | Should -Match '(?ms)^  release:.*?permissions:\s*\r?\n\s+contents:\s*write'
        $script:workflow | Should -Match '(?s)  release:.*?- name: Rebuild locked skill sources\s+shell: pwsh\s+run: \.\\skills\.ps1 更新 -Locked -SkipHostProjection\s+- name: Build release packages'
        @([regex]::Matches($script:workflow, '(?m)^\s+contents:\s*write\s*$')).Count | Should -Be 1
    }

    It 'attests exactly the three release assets with pinned provenance action and minimal tag-job permissions' {
        $script:workflow | Should -Match '(?ms)^  release:.*?permissions:\s*\r?\n\s+contents:\s*write\s*\r?\n\s+id-token:\s*write\s*\r?\n\s+attestations:\s*write'
        $script:workflow | Should -Match 'actions/attest-build-provenance@977bb373ede98d70efdf65b84cb5f73e068dcc2a'
        $script:workflow | Should -Match '(?ms)subject-path:\s*\|\s*\r?\n\s+artifacts/\*\.zip\s*\r?\n\s+artifacts/\*-SHA256SUMS\.txt\s*$'
        @([regex]::Matches($script:workflow, '(?m)^\s+(id-token|attestations):\s*write\s*$')).Count | Should -Be 2
    }
}
