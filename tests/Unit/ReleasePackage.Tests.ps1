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

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.1' -Package Bootstrap -OutputDirectory $output | Out-Null
        $LASTEXITCODE | Should -Be 0

        $bootstrap = Join-Path $output 'skills-manager-test.1-bootstrap.zip'
        Test-Path -LiteralPath $bootstrap | Should -Be $true
        Test-Path -LiteralPath (Join-Path $output 'skills-manager-test.1-SHA256SUMS.txt') | Should -Be $true

        $extract = Join-Path $TestDrive 'extracted'
        Expand-Archive -LiteralPath $bootstrap -DestinationPath (Join-Path $extract 'bootstrap')
        $bootstrapRoot = Join-Path $extract 'bootstrap\skills-manager-test.1-bootstrap'
        $bootstrapManifest = Get-Content -LiteralPath (Join-Path $bootstrapRoot 'RELEASE-MANIFEST.json') -Raw | ConvertFrom-Json

        $bootstrapManifest.package | Should -Be 'bootstrap'
        $bootstrapManifest.includes_prebuilt_agent | Should -Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'setup.cmd') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'LICENSE') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'reports') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot '.git') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'THIRD-PARTY-NOTICES.json') | Should -Be $false
    }

    It 'fails closed before creating a portable archive with unknown licenses' {
        $output = Join-Path $TestDrive 'portable-blocked'
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'

        $result = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.2' -Package Portable -OutputDirectory $output 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $result -join "`n" | Should -Match 'Portable release blocked: \d+ skills require license review'
        Test-Path -LiteralPath (Join-Path $output 'skills-manager-test.2-portable.zip') | Should -BeFalse
    }
}
