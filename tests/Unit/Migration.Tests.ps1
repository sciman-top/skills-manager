BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')
}

Describe 'Migration bundles' {
    It 'admits only the private snapshot and auxiliary rescan modes' {
        (Get-MigrationTokens @()).mode | Should -Be 'private-all'
        (Get-MigrationTokens @('--mode', 'private-all')).mode | Should -Be 'private-all'
        (Get-MigrationTokens @('--mode', 'rescan')).mode | Should -Be 'rescan'
        { Get-MigrationTokens @('--mode', 'general') } | Should -Throw
        { Get-MigrationTokens @('--encrypt') } | Should -Throw
    }

    It 'creates a plaintext private snapshot under the requested version directory' {
        Mock Read-Host { throw 'private snapshot must not prompt for a passphrase' }
        $version = 'test.snapshot'
        $result = Invoke-MigrationCommand @('--mode', 'private-all', '--version', $version, '--json') | ConvertFrom-Json
        $result.path | Should -Match '\\artifacts\\deliveries\\test\.snapshot\\private-snapshot\\[^\\]+\\migration-private-all-[^\\]+\.zip$'
        $extract = Join-Path $TestDrive 'private-extract'
        Expand-Archive -LiteralPath $result.path -DestinationPath $extract
        $root = Join-Path $extract 'skills-manager-migration-private-all'
        $manifest = Get-Content -LiteralPath (Join-Path $root 'MIGRATION-MANIFEST.json') -Raw | ConvertFrom-Json
        $manifest.private_use_only | Should -BeTrue
        $manifest.includes_credentials | Should -BeTrue
        $manifest.credentials_encrypted | Should -BeFalse
        $manifest.credential_file | Should -Be 'MIGRATION-MCP-CREDENTIALS.json'
        Test-Path -LiteralPath (Join-Path $root 'agent') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'rules\global') | Should -BeTrue
    }

    It 'requires a version number for a default delivery path' {
        { Invoke-MigrationCommand @('--mode', 'private-all') } | Should -Throw '*--version*'
    }

    It 'keeps rescan as an auxiliary list without skills or MCP payload' {
        $out = Join-Path $TestDrive 'rescan.zip'
        Invoke-MigrationCommand @('--mode', 'rescan', '--out', $out)
        Expand-Archive -LiteralPath $out -DestinationPath (Join-Path $TestDrive 'rescan-extract')
        $root = Join-Path $TestDrive 'rescan-extract\skills-manager-migration-rescan'
        Test-Path -LiteralPath (Join-Path $root 'agent') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'skills.json') | Should -BeFalse
    }
}
