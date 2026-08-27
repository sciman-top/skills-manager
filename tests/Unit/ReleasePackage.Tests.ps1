BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

}
Describe 'Release packaging' {
    It 'ships the one-click wrappers and migration documentation' {
        $setup = Get-Content -LiteralPath (Join-Path $repoRoot 'setup.cmd') -Raw
        $readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw

        $setup | Should -Match 'install\.ps1" -Mode CurrentUser'
        $setup | Should -Match 'PowerShell 7\+'
        $readme | Should -Match 'bootstrap\.zip'
        $readme | Should -Match 'portable\.zip'
        Test-Path -LiteralPath (Join-Path $repoRoot 'docs\INSTALLATION_AND_MIGRATION.md') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $repoRoot 'docs\RELEASING.md') | Should -Be $true
    }

    It 'builds a self-describing bootstrap archive without runtime state' {
        $output = Join-Path $TestDrive 'release-output'
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.1' -Package Bootstrap -OutputDirectory $output -AllowDirtyWorktree | Out-Null
        $LASTEXITCODE | Should -Be 0

        $releaseRoot = Join-Path $output 'test.1'
        $bootstrap = Join-Path $releaseRoot 'skills-manager-test.1-bootstrap.zip'
        Test-Path -LiteralPath $bootstrap | Should -Be $true
        Test-Path -LiteralPath (Join-Path $releaseRoot 'skills-manager-test.1-SHA256SUMS.txt') | Should -Be $true

        $extract = Join-Path $TestDrive 'extracted'
        Expand-Archive -LiteralPath $bootstrap -DestinationPath (Join-Path $extract 'bootstrap')
        $bootstrapRoot = Join-Path $extract 'bootstrap\skills-manager-test.1-bootstrap'
        $bootstrapManifest = Get-Content -LiteralPath (Join-Path $bootstrapRoot 'RELEASE-MANIFEST.json') -Raw | ConvertFrom-Json

        $bootstrapManifest.package | Should -Be 'bootstrap'
        $bootstrapManifest.source_state | Should -Be 'dirty_development'
        $bootstrapManifest.publishable | Should -BeFalse
        $bootstrapManifest.includes_prebuilt_agent | Should -Be $false
        $bootstrapManifest.requires.git_for_install | Should -BeTrue
        $bootstrapManifest.requires.git_for_green_run | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'setup.cmd') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'LICENSE') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'scripts\release\release-update-worker.ps1') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'scripts\release\release-update-scheduled-runner.ps1') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'scripts\release\register-release-update-task.ps1') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'reports') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot '.git') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'THIRD-PARTY-NOTICES.json') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'references\reference-shelf.manifest.json') | Should -BeTrue

        $manifestPaths = @($bootstrapManifest.files.path | Sort-Object)
        $actualPaths = @(Get-ChildItem -LiteralPath $bootstrapRoot -Force -Recurse -File |
                ForEach-Object { [IO.Path]::GetRelativePath($bootstrapRoot, $_.FullName).Replace('\', '/') } |
                Where-Object { $_ -ne 'RELEASE-MANIFEST.json' } | Sort-Object)
        Compare-Object $manifestPaths $actualPaths | Should -BeNullOrEmpty
    }

    It 'builds a portable archive with pinned shared license evidence' {
        $output = Join-Path $TestDrive 'portable-output'
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.2' -Package Portable -OutputDirectory $output -AllowDirtyWorktree | Out-Null
        $LASTEXITCODE | Should -Be 0

        $portable = Join-Path (Join-Path $output 'test.2') 'skills-manager-test.2-portable.zip'
        Test-Path -LiteralPath $portable | Should -BeTrue
        $extract = Join-Path $TestDrive 'portable-extracted'
        Expand-Archive -LiteralPath $portable -DestinationPath $extract
        $packageRoot = Join-Path $extract 'skills-manager-test.2-portable'
        $notices = Get-Content -LiteralPath (Join-Path $packageRoot 'THIRD-PARTY-NOTICES.json') -Raw | ConvertFrom-Json

        $notices.summary.unknown_license | Should -Be 0
        $manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'RELEASE-MANIFEST.json') -Raw | ConvertFrom-Json
        $manifest.requires.git_for_install | Should -BeFalse
        $manifest.requires.git_for_update | Should -BeFalse
        $localSkill = $notices.skills | Where-Object skill -eq 'capability-router'
        @($localSkill.license_files) | Should -Contain 'LICENSE'
        $vendorSkill = $notices.skills | Where-Object skill -eq 'code-review-and-quality'
        @($vendorSkill.license_files) | Should -Contain 'THIRD-PARTY-LICENSES/vendor-agent-skills-2/LICENSE'
        $sharedLicense = Join-Path $packageRoot 'THIRD-PARTY-LICENSES\vendor-agent-skills-2\LICENSE'
        Test-Path -LiteralPath $sharedLicense | Should -BeTrue
        (Get-Item -LiteralPath $sharedLicense).Length | Should -BeGreaterThan 0
        @($notices.skills.skill) | Should -Not -Contain 'skills-2-skills-remotion'
        Test-Path -LiteralPath (Join-Path $packageRoot 'agent\pptx\scripts\__init__.py') | Should -BeTrue
        (Get-Item -LiteralPath (Join-Path $packageRoot 'agent\pptx\scripts\__init__.py')).Length | Should -Be 0
    }

    It 'fails closed before creating a portable archive with an unlicensed pinned source' {
        $fixtureRoot = Join-Path $TestDrive 'unlicensed-release-fixture'
        $fixtureScriptRoot = Join-Path $fixtureRoot 'scripts\release'
        $fixtureApplicationRoot = Join-Path $fixtureRoot 'src\Application'
        $fixtureDocs = Join-Path $fixtureRoot 'docs'
        $fixtureReferences = Join-Path $fixtureRoot 'references\updates'
        $fixtureAgent = Join-Path $fixtureRoot 'agent\unknown-skill'
        $fixtureVendor = Join-Path $fixtureRoot 'vendor\unlicensed'
        New-Item -ItemType Directory -Path $fixtureScriptRoot, $fixtureApplicationRoot, $fixtureDocs, $fixtureReferences, $fixtureAgent, $fixtureVendor -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\release\build-release.ps1') -Destination (Join-Path $fixtureScriptRoot 'build-release.ps1')
        foreach ($helper in @('release-update-worker.ps1', 'release-update-scheduled-runner.ps1', 'register-release-update-task.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot (Join-Path 'scripts\release' $helper)) -Destination (Join-Path $fixtureScriptRoot $helper)
        }
        Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Application\SkillSupply.ps1') -Destination (Join-Path $fixtureApplicationRoot 'SkillSupply.ps1')

        & git -C $fixtureVendor init --quiet
        & git -C $fixtureVendor config user.name 'Release Fixture'
        & git -C $fixtureVendor config user.email 'release-fixture@example.invalid'
        Set-Content -LiteralPath (Join-Path $fixtureVendor 'README.md') -Value '# no license grant' -Encoding utf8
        & git -C $fixtureVendor add README.md
        & git -C $fixtureVendor commit --quiet -m 'fixture source'
        $vendorCommit = (& git -C $fixtureVendor rev-parse HEAD).Trim()

        $rootFiles = @(
            'README.md', 'README.en.md', 'LICENSE', 'CODE_OF_CONDUCT.md', 'CONTRIBUTING.md', 'SECURITY.md',
            'build.ps1', 'install.ps1', 'setup.cmd', 'skills.cmd', 'skills.ps1'
        )
        foreach ($relativePath in $rootFiles) {
            Set-Content -LiteralPath (Join-Path $fixtureRoot $relativePath) -Value 'fixture' -Encoding utf8
        }
        Set-Content -LiteralPath (Join-Path $fixtureDocs 'INSTALLATION_AND_MIGRATION.md') -Value 'fixture' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fixtureDocs 'RELEASING.md') -Value 'fixture' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'references\README.md') -Value 'fixture' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'references\reference-shelf.manifest.json') -Value '{}' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fixtureReferences 'README.md') -Value 'fixture' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fixtureAgent 'SKILL.md') -Value "---`nname: unknown-skill`ndescription: fixture`nlicense: MIT`n---" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.gitignore') -Value "/agent/`n/vendor/" -Encoding utf8
        [ordered]@{
            vendors = @([ordered]@{ name = 'unlicensed'; repo = 'https://example.invalid/unlicensed.git'; ref = 'main' })
            targets = @()
            mappings = @([ordered]@{ vendor = 'unlicensed'; from = 'skills/unknown'; to = 'unknown-skill' })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixtureRoot 'skills.json') -Encoding utf8
        [ordered]@{
            version = 1
            vendors = @([ordered]@{ name = 'unlicensed'; repo = 'https://example.invalid/unlicensed.git'; ref = 'main'; commit = $vendorCommit })
            imports = @()
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixtureRoot 'skills.lock.json') -Encoding utf8

        & git -C $fixtureRoot init --quiet
        & git -C $fixtureRoot config user.name 'Release Fixture'
        & git -C $fixtureRoot config user.email 'release-fixture@example.invalid'
        & git -C $fixtureRoot add --all
        & git -C $fixtureRoot commit --quiet -m 'fixture release repo'

        $output = Join-Path $TestDrive 'portable-blocked'
        $script = Join-Path $fixtureScriptRoot 'build-release.ps1'
        $result = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.3' -Package Portable -OutputDirectory $output 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $result -join "`n" | Should -Match 'Portable release blocked: 1 skills require license review: unknown-skill'
        Test-Path -LiteralPath (Join-Path (Join-Path $output 'test.3') 'skills-manager-test.3-portable.zip') | Should -BeFalse
    }

    It 'rejects a tracked dirty release source unless explicitly marked non-publishable' {
        $output = Join-Path $TestDrive 'dirty-source-output'
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'
        $trackedFile = Join-Path $repoRoot 'README.md'
        $original = [IO.File]::ReadAllBytes($trackedFile)
        try {
            [IO.File]::WriteAllBytes($trackedFile, $original + [Text.Encoding]::UTF8.GetBytes("`r`n# dirty release fixture`r`n"))
            $result = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.dirty' -Package Bootstrap -OutputDirectory $output 2>&1)
            $LASTEXITCODE | Should -Not -Be 0
            $result -join "`n" | Should -Match 'requires a clean tracked worktree'
            Test-Path -LiteralPath (Join-Path (Join-Path $output 'test.dirty') 'skills-manager-test.dirty-bootstrap.zip') | Should -BeFalse
        }
        finally {
            [IO.File]::WriteAllBytes($trackedFile, $original)
        }
    }

    It 'rejects repository artifact-root output that bypasses the release contract' {
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'
        $result = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.root' -Package Bootstrap -OutputDirectory (Join-Path $repoRoot 'artifacts') -AllowDirtyWorktree 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $result -join "`n" | Should -Match 'Release output directory must be artifacts\\release'
        Test-Path -LiteralPath (Join-Path $repoRoot 'artifacts\test.root') | Should -BeFalse
    }
}
