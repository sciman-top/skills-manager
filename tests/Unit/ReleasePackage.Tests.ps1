$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

Describe 'Release packaging' {
    It 'ships the one-click wrappers and migration documentation' {
        $setup = Get-Content -LiteralPath (Join-Path $repoRoot 'setup.cmd') -Raw
        $readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw

        $setup | Should Match 'install\.ps1" -Mode CurrentUser'
        $setup | Should Match 'PowerShell 7\+'
        $readme | Should Match 'bootstrap\.zip'
        $readme | Should Match 'portable\.zip'
        Test-Path -LiteralPath (Join-Path $repoRoot 'docs\INSTALLATION_AND_MIGRATION.md') | Should Be $true
        Test-Path -LiteralPath (Join-Path $repoRoot 'docs\RELEASING.md') | Should Be $true
    }

    It 'builds self-describing bootstrap and portable archives without runtime state' {
        $output = Join-Path $TestDrive 'release-output'
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.1' -OutputDirectory $output | Out-Null
        $LASTEXITCODE | Should Be 0

        $bootstrap = Join-Path $output 'skills-manager-test.1-bootstrap.zip'
        $portable = Join-Path $output 'skills-manager-test.1-portable.zip'
        Test-Path -LiteralPath $bootstrap | Should Be $true
        Test-Path -LiteralPath $portable | Should Be $true
        Test-Path -LiteralPath (Join-Path $output 'skills-manager-test.1-SHA256SUMS.txt') | Should Be $true

        $extract = Join-Path $TestDrive 'extracted'
        Expand-Archive -LiteralPath $bootstrap -DestinationPath (Join-Path $extract 'bootstrap')
        Expand-Archive -LiteralPath $portable -DestinationPath (Join-Path $extract 'portable')
        $bootstrapRoot = Join-Path $extract 'bootstrap\skills-manager-test.1-bootstrap'
        $portableRoot = Join-Path $extract 'portable\skills-manager-test.1-portable'
        $bootstrapManifest = Get-Content -LiteralPath (Join-Path $bootstrapRoot 'RELEASE-MANIFEST.json') -Raw | ConvertFrom-Json
        $portableManifest = Get-Content -LiteralPath (Join-Path $portableRoot 'RELEASE-MANIFEST.json') -Raw | ConvertFrom-Json

        $bootstrapManifest.package | Should Be 'bootstrap'
        $bootstrapManifest.includes_prebuilt_agent | Should Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'setup.cmd') | Should Be $true
        Test-Path -LiteralPath (Join-Path $bootstrapRoot 'reports') | Should Be $false
        Test-Path -LiteralPath (Join-Path $bootstrapRoot '.git') | Should Be $false
        $portableManifest.package | Should Be 'portable'
        $portableManifest.includes_prebuilt_agent | Should Be $true
        Test-Path -LiteralPath (Join-Path $portableRoot 'agent') | Should Be $true
    }
}
