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
        $oldRoot = $Root
        $oldAgentDir = $AgentDir
        $oldCfgPath = $CfgPath
        try {
            $fixtureRoot = Join-Path $TestDrive 'migration-repo'
            $fixtureAgent = Join-Path $fixtureRoot 'agent'
            New-Item -ItemType Directory -Path (Join-Path $fixtureAgent 'demo-skill') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'rules\global') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fixtureAgent 'demo-skill\SKILL.md') -Value '# demo'
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'rules\global\AGENTS.md') -Value '# fixture rules'
            $Root = $fixtureRoot
            $AgentDir = $fixtureAgent
            $CfgPath = Join-Path $fixtureRoot 'skills.json'
            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    targets = @()
                    mappings = @()
                    imports = @()
                    mcp_servers = @()
                    mcp_targets = @()
                }
            }
            $out = Join-Path $TestDrive 'private-all.zip'
            $result = Invoke-MigrationCommand @('--mode', 'private-all', '--out', $out, '--json') | ConvertFrom-Json
        }
        finally {
            $Root = $oldRoot
            $AgentDir = $oldAgentDir
            $CfgPath = $oldCfgPath
        }
        $result.path | Should -Be $out
        $extract = Join-Path $TestDrive 'private-extract'
        Expand-Archive -LiteralPath $result.path -DestinationPath $extract
        $packageRoot = Join-Path $extract 'skills-manager-migration-private-all'
        $manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'MIGRATION-MANIFEST.json') -Raw | ConvertFrom-Json
        $manifest.delivery_version | Should -BeNullOrEmpty
        $manifest.private_use_only | Should -BeTrue
        $manifest.includes_credentials | Should -BeTrue
        $manifest.credentials_encrypted | Should -BeFalse
        $manifest.credential_file | Should -Be 'MIGRATION-MCP-CREDENTIALS.json'
        Test-Path -LiteralPath (Join-Path $packageRoot 'MIGRATION-MCP-CREDENTIALS.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $packageRoot 'agent\demo-skill\SKILL.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $packageRoot 'rules\global\AGENTS.md') | Should -BeTrue
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
