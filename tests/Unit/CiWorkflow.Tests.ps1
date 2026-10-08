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

    It 'checks the PR charter before selecting the proportional gate' {
        $scriptPath = Join-Path $repoRoot 'scripts\quality\verify-pr-charter.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue
        $script:workflow | Should -Match 'Verify pull request charter'
        $script:workflow | Should -Match 'verify-pr-charter\.ps1 -EventPath \$env:GITHUB_EVENT_PATH'
        $script:workflow | Should -Match "if: github\.event_name == 'pull_request'"
        $script:workflow.IndexOf('Verify pull request charter') | Should -BeLessThan $script:workflow.IndexOf('Select proportional quality gate profile')

        $validEvent = [ordered]@{
            pull_request = [ordered]@{
                body = @'
## Goal
- Keep the merge contract reviewable.
- New surface: yes

## Charter admission
- Current caller: GitHub pull request workflow
- Replaces / deletes: none; this is the existing PR template contract
- Minimum proof: focused CI workflow contract test

## Deletion delta
- Removed: 0

## Risks and Rollback
- Risk: a malformed PR body is rejected before tests.
- Rollback: revert the workflow and verifier change.
'@
            }
        }
        $validPath = Join-Path $TestDrive 'valid-event.json'
        $validEvent | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validPath -Encoding UTF8
        & pwsh -NoProfile -File $scriptPath -EventPath $validPath *> $null
        $LASTEXITCODE | Should -Be 0

        $template = Get-Content -LiteralPath (Join-Path $repoRoot '.github\pull_request_template.md') -Raw
        $templateAdmissionHeading = [regex]::Match($template, '(?m)^## Charter admission[^\r\n]*').Value
        $templateAdmissionHeading | Should -Match '^## Charter admission\s+\('
        $templateStyleEvent = [ordered]@{
            pull_request = [ordered]@{
                body = $validEvent.pull_request.body.Replace('## Charter admission', $templateAdmissionHeading)
            }
        }
        $templateStylePath = Join-Path $TestDrive 'template-style-event.json'
        $templateStyleEvent | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $templateStylePath -Encoding UTF8
        & pwsh -NoProfile -File $scriptPath -EventPath $templateStylePath *> $null
        $LASTEXITCODE | Should -Be 0

        $invalidEvent = [ordered]@{
            pull_request = [ordered]@{
                body = @'
## Goal
- <what this PR changes>
- New surface: yes

## Charter admission
- Current caller: <who calls this today; "may be useful later" is not a caller>
- Replaces / deletes: <what this removes or supersedes; "none" = net-new surface, justify it>
- Minimum proof: <smallest check that proves the change; does it escalate the gate to full?>

## Deletion delta
- Removed: <tests/gates/docs removed or merged; write 0 only after checking>

## Risks and Rollback
- Risk: <risk>
- Rollback: <rollback>
'@
            }
        }
        $invalidPath = Join-Path $TestDrive 'invalid-event.json'
        $invalidEvent | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidPath -Encoding UTF8
        & pwsh -NoProfile -File $scriptPath -EventPath $invalidPath *> $null
        $LASTEXITCODE | Should -Not -Be 0

        $emptyEvent = [ordered]@{ pull_request = [ordered]@{ body = '' } }
        $emptyPath = Join-Path $TestDrive 'empty-event.json'
        $emptyEvent | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $emptyPath -Encoding UTF8
        & pwsh -NoProfile -File $scriptPath -EventPath $emptyPath *> $null
        $LASTEXITCODE | Should -Not -Be 0

        $missingSectionEvent = [ordered]@{
            pull_request = [ordered]@{
                body = $validEvent.pull_request.body -replace '## Charter admission', '## Admission details'
            }
        }
        $missingSectionPath = Join-Path $TestDrive 'missing-section-event.json'
        $missingSectionEvent | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $missingSectionPath -Encoding UTF8
        & pwsh -NoProfile -File $scriptPath -EventPath $missingSectionPath *> $null
        $LASTEXITCODE | Should -Not -Be 0

        $routineEvent = [ordered]@{
            pull_request = [ordered]@{
                body = @'
## Goal
- Fix a regression in an existing command.
- New surface: no

## Risks and Rollback
- Risk: the command may still reject invalid input.
- Rollback: revert the implementation change.
'@
            }
        }
        $routinePath = Join-Path $TestDrive 'routine-event.json'
        $routineEvent | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $routinePath -Encoding UTF8
        & pwsh -NoProfile -File $scriptPath -EventPath $routinePath *> $null
        $LASTEXITCODE | Should -Be 0

        $missingSurfaceEvent = [ordered]@{ pull_request = [ordered]@{ body = $routineEvent.pull_request.body.Replace('- New surface: no', '') } }
        $missingSurfacePath = Join-Path $TestDrive 'missing-surface-event.json'
        $missingSurfaceEvent | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $missingSurfacePath -Encoding UTF8
        & pwsh -NoProfile -File $scriptPath -EventPath $missingSurfacePath *> $null
        $LASTEXITCODE | Should -Not -Be 0
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
