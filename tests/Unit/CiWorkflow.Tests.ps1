Describe 'GitHub CI workflow supply-chain contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:workflow = Get-Content -LiteralPath (Join-Path $repoRoot '.github\workflows\ci.yml') -Raw
    }

    It 'pins checkout and the Pester package bytes and gives full tests a realistic bounded budget' {
        $script:workflow | Should -Match 'timeout-minutes:\s*15'
        $script:workflow | Should -Match 'timeout-minutes:\s*30'
        $script:workflow | Should -Match 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
        $script:workflow | Should -Not -Match 'ensure-test-runtime\.ps1'
        $bootstrap = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\quality\ensure-test-runtime.ps1') -Raw
        # Bootstrap must pin the Pester version to an exact verified byte hash
        # and verify it with SHA256 before use; decompression mechanics are
        # free to change.
        $bootstrap | Should -Match 'Pester/\$version'
        $bootstrap | Should -Match '0207a75ea09f81b27c1ded44898b2bb3c845bafa02045bd64a39e26a53ca41b4'
        $bootstrap | Should -Match 'Get-FileHash[^\r\n]+SHA256'
        $script:workflow | Should -Match 'skills\.ps1 更新 -Locked -SkipHostProjection'
        $script:workflow | Should -Not -Match 'SkipPublisherCheck'
    }

    It 'runs required checks on PRs and release tags without a post-merge main rerun' {
        $script:workflow | Should -Not -Match '(?ms)^  push:\s*\r?\n\s+branches:'
        $script:workflow | Should -Match "tags:\s*\r?\n\s+- '\*'"
        $script:workflow | Should -Match 'pull_request:'
    }

    It 'shares proportional classification for PRs and reserves unconditional full for tags' {
        $script:workflow | Should -Match 'github\.ref.*refs/tags/'
        $script:workflow | Should -Not -Match "github\.event_name.*-eq 'push'"
        $script:workflow | Should -Match 'github\.event_name.*pull_request'
        $script:workflow | Should -Match 'resolve-gate-profile\.ps1 -BaseSha \$baseSha -Mode ci -Json'
        $script:workflow | Should -Match 'CI_GATE_PROFILE=\$profile'
        $script:workflow | Should -Match 'run-local-quality-gates\.ps1 @gateArgs'
        $script:workflow | Should -Match 'CI_FOCUSED_TEST_PATHS'
        # The final gate invocation must splat a hashtable: array splat is
        # positional-only and turned CI red by binding '-Profile' as a value.
        $script:workflow | Should -Match 'CheckGenerated = \$true'
        $script:workflow | Should -Match 'CI_REQUIRES_LOCKED_SOURCES -eq ''True'''
        $script:workflow | Should -Match 'requires_locked_sources'
        $script:workflow | Should -Not -Match "\['Verifier'\]"
        $script:workflow | Should -Not -Match "'mor'"
        $script:workflow | Should -Not -Match "\`$gateArgs = @\('-Profile'"
        # The classifier must stay in the shared resolver; CI keeps no inline copy.
        $script:workflow | Should -Not -Match 'git diff --name-only \$baseSha HEAD'
        $script:workflow | Should -Not -Match '\$riskPath = '
        $script:workflow | Should -Not -Match "\`$profile = '(quick|focused|docs)'"
        @([regex]::Matches($script:workflow, 'run-local-quality-gates\.ps1')).Count | Should -Be 1

        $resolver = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\quality\resolve-gate-profile.ps1') -Raw
        $resolver | Should -Match 'tests/E2E/'
        $riskMatch = [regex]::Match($resolver, '\$riskPath = ''([^'']+)''')
        $riskMatch.Success | Should -Be $true
        $riskPath = [regex]::new($riskMatch.Groups[1].Value)
        foreach ($path in @('tests/E2E/Workflow.Tests.ps1', '.github/workflows/ci.yml', 'scripts/quality/run-local-quality-gates.ps1', 'skills.lock.json', 'overrides/resources/native-agent-bridge/design-griller.toml', 'overrides/patches/provenance.json', 'audit-targets.json')) {
            $riskPath.IsMatch($path) | Should -Be $true
        }
        foreach ($path in @('src/Core.ps1', 'tests/Unit/Core.Tests.ps1', 'README.md', 'README.en.md', 'CONTRIBUTING.md', 'docs/product/README.md')) {
            $riskPath.IsMatch($path) | Should -Be $false
        }
        $resolver | Should -Match '\$skillFocusedPath'
        $resolver | Should -Match 'tests/Unit/SkillContent.Tests.ps1'
        $resolver | Should -Match 'Test-SkillsConfigFocusedChange'
    }

    It 'rejects invalid CI resolver output before selecting setup and proof: <case>' -ForEach @(
        @{ case = 'missing profile'; resolverText = "'{}'; exit 0" }
        @{ case = 'unknown profile'; resolverText = "'{`"profile`":`"skip`"}'; exit 0" }
        @{ case = 'failed resolver'; resolverText = "'{`"profile`":`"docs`",`"reason`":`"docs_only`",`"docs_only`":true,`"requires_locked_sources`":false,`"focused_test_paths`":[]}'; exit 9" }
        @{ case = 'non-boolean setup'; resolverText = "'{`"profile`":`"docs`",`"reason`":`"docs_only`",`"docs_only`":true,`"requires_locked_sources`":`"false`",`"focused_test_paths`":[]}'; exit 0" }
        @{ case = 'focused without tests'; resolverText = "'{`"profile`":`"focused`",`"reason`":`"source_path`",`"docs_only`":false,`"requires_locked_sources`":false,`"focused_test_paths`":[]}'; exit 0" }
        @{ case = 'malformed JSON'; resolverText = "'{'; exit 0" }
        @{ case = 'resolver exception'; resolverText = "throw 'resolver crashed'" }
        @{ case = 'array result'; resolverText = "'[{`"profile`":`"docs`",`"reason`":`"docs_only`",`"docs_only`":true,`"requires_locked_sources`":false,`"focused_test_paths`":[]}]'; exit 0" }
        @{ case = 'scalar test path'; resolverText = "'{`"profile`":`"focused`",`"reason`":`"source_path`",`"docs_only`":false,`"requires_locked_sources`":false,`"focused_test_paths`":`"tests/Unit/Core.Tests.ps1`"}'; exit 0" }
        @{ case = 'null test path'; resolverText = "'{`"profile`":`"focused`",`"reason`":`"source_path`",`"docs_only`":false,`"requires_locked_sources`":false,`"focused_test_paths`":[null]}'; exit 0" }
    ) {
        $selection = [regex]::Match($script:workflow, '(?ms)^[ \t]+\$resolved = .*?^[ \t]+\$requiresLockedSources = \[bool\]\$resolved\.requires_locked_sources[^\r\n]*')
        $selection.Success | Should -BeTrue
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts/quality') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $TestDrive 'scripts/quality/resolve-gate-profile.ps1') -Value $resolverText
        Push-Location $TestDrive
        try {
            $baseSha = 'HEAD'
            { & ([scriptblock]::Create($selection.Value)) *> $null } | Should -Throw '*Gate profile resolver*'
        }
        finally { Pop-Location }
    }

    It 'accepts valid CI resolver output: <profile>' -ForEach @(
        @{ profile = 'docs'; docsOnly = $true; requiresLockedSources = $false; focusedTests = @() }
        @{ profile = 'focused'; docsOnly = $false; requiresLockedSources = $false; focusedTests = @('tests/Unit/Core.Tests.ps1') }
        @{ profile = 'full'; docsOnly = $false; requiresLockedSources = $true; focusedTests = @() }
    ) {
        $selection = [regex]::Match($script:workflow, '(?ms)^[ \t]+\$resolved = .*?^[ \t]+\$requiresLockedSources = \[bool\]\$resolved\.requires_locked_sources[^\r\n]*')
        $selection.Success | Should -BeTrue
        $expected = [ordered]@{
            profile = $profile
            reason = 'valid_result'
            docs_only = $docsOnly
            requires_locked_sources = $requiresLockedSources
            focused_test_paths = @($focusedTests)
        }
        $resolverText = "'$($expected | ConvertTo-Json -Compress)'; exit 0"
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts/quality') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $TestDrive 'scripts/quality/resolve-gate-profile.ps1') -Value $resolverText
        Push-Location $TestDrive
        try {
            $baseSha = 'HEAD'
            $global:LASTEXITCODE = 7
            $actual = & ([scriptblock]::Create($selection.Value + "`n" + '[pscustomobject]@{ profile = $profile; docsOnly = $docsOnly; focusedTests = @($focusedTests); requiresLockedSources = $requiresLockedSources }'))
            $actual.profile | Should -Be $expected.profile
            $actual.docsOnly | Should -Be $expected.docs_only
            $actual.requiresLockedSources | Should -Be $expected.requires_locked_sources
            ($actual.focusedTests -join ',') | Should -Be ($expected.focused_test_paths -join ',')
        }
        finally { Pop-Location }
    }

    It 'routes documentation-only changes to the docs profile' {
        $resolver = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\quality\resolve-gate-profile.ps1') -Raw
        $resolver | Should -Match "Get-GateProfileResult 'docs'"
        $script:workflow | Should -Match 'DiffBase'
        $script:workflow | Should -Match 'docsOnly'
        $script:workflow | Should -Match 'CI_DIFF_BASE_SHA=\$baseSha'
    }

    It 'keeps tests read-only and grants release write access only to the tag job' {
        $script:workflow | Should -Match '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$'
        $script:workflow | Should -Match 'needs: test'
        $script:workflow | Should -Match 'contents:\s*write'
        @([regex]::Matches($script:workflow, '(?m)^\s+contents:\s*write\s*$')).Count | Should -Be 1
    }

    It 'checks the new-surface label before selecting the proportional gate' {
        $scriptPath = Join-Path $repoRoot 'scripts\quality\verify-new-surface.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue
        $script:workflow | Should -Match 'Verify new-surface label'
        $script:workflow | Should -Match 'verify-new-surface\.ps1 -EventPath \$env:GITHUB_EVENT_PATH'
        $script:workflow | Should -Match "if: github\.event_name == 'pull_request'"
        $script:workflow.IndexOf('Verify new-surface label') | Should -BeLessThan $script:workflow.IndexOf('Select proportional quality gate profile')
    }

    It 'applies the new-surface label rule to new runtime, gate, test and CI files only' {
        $scriptPath = Join-Path $repoRoot 'scripts\quality\verify-new-surface.ps1'
        $repo = Join-Path $TestDrive 'surface-repo'
        New-Item -ItemType Directory -Path $repo | Out-Null
        Push-Location $repo
        try {
            & git init -q -b main *> $null
            & git config user.email 'ci@example.invalid'
            & git config user.name 'ci'
            Set-Content -LiteralPath 'README.md' -Value 'base'
            & git add . *> $null
            & git commit -q -m base *> $null
            $base = (& git rev-parse HEAD).Trim()

            function Invoke-SurfaceGate([string[]]$Labels) {
                $event = [ordered]@{ pull_request = [ordered]@{ base = [ordered]@{ sha = $base }; labels = @($Labels | ForEach-Object { [ordered]@{ name = $_ } }) } }
                $path = Join-Path $TestDrive ('event-' + [Guid]::NewGuid().ToString('N') + '.json')
                $event | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
                & pwsh -NoProfile -File $scriptPath -EventPath $path *> $null
                return $LASTEXITCODE
            }

            New-Item -ItemType Directory -Path 'scripts', 'docs', 'tests/fixtures/sample' -Force | Out-Null
            Set-Content -LiteralPath 'scripts/new-gate.ps1' -Value '# gate'
            Set-Content -LiteralPath 'docs/new-note.md' -Value '# note'
            Set-Content -LiteralPath 'tests/fixtures/sample/data.json' -Value '{}'
            & git add . *> $null
            & git commit -q -m 'mixed change' *> $null

            # A new gate script without the label fails; with the label it passes.
            Invoke-SurfaceGate @() | Should -Be 1
            Invoke-SurfaceGate @('new-surface') | Should -Be 0

            # Docs and fixtures alone do not require the label.
            & git reset -q --hard $base *> $null
            New-Item -ItemType Directory -Path 'docs' -Force | Out-Null
            Set-Content -LiteralPath 'docs/only-doc.md' -Value '# doc'
            & git add . *> $null
            & git commit -q -m 'doc only' *> $null
            Invoke-SurfaceGate @() | Should -Be 0

            # A non-pull_request event is not applicable.
            $pushPath = Join-Path $TestDrive 'push-event.json'
            [ordered]@{ ref = 'refs/heads/main' } | ConvertTo-Json | Set-Content -LiteralPath $pushPath -Encoding UTF8
            & pwsh -NoProfile -File $scriptPath -EventPath $pushPath *> $null
            $LASTEXITCODE | Should -Be 0
        }
        finally { Pop-Location }
    }


    It 'attests exactly the three release assets with pinned provenance action and minimal tag-job permissions' {
        $script:workflow | Should -Match 'id-token:\s*write'
        $script:workflow | Should -Match 'attestations:\s*write'
        $script:workflow | Should -Match 'actions/attest-build-provenance@977bb373ede98d70efdf65b84cb5f73e068dcc2a'
        $script:workflow | Should -Match 'artifacts/deliveries/\$\{\{ github\.ref_name \}\}/\*\*/\*\.zip'
        $script:workflow | Should -Match 'skills-manager-\$\{\{ github\.ref_name \}\}-SHA256SUMS\.txt'
        @([regex]::Matches($script:workflow, '(?m)^\s+(id-token|attestations):\s*write\s*$')).Count | Should -Be 2
    }
}
