BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')
}

Describe 'Migration bundles' {
    It 'requires explicit encryption for private-general' {
        { Get-MigrationTokens @('--mode','private-general') } | Should -Throw '*必须显式加 --encrypt*'
        $options = Get-MigrationTokens @('--mode','private-general','--encrypt')
        $options.mode | Should -Be 'private-general'
        $options.encrypt | Should -BeTrue
        { Get-MigrationTokens @('--mode','private-all') } | Should -Throw '*必须显式加 --encrypt*'
        (Get-MigrationTokens @('--mode','private-all','--encrypt')).mode | Should -Be 'private-all'
    }

    It 'round-trips MCP credentials with authenticated encryption without exposing plaintext' {
        $payload = [pscustomobject]@{ schema_version = 1; mcp_servers = @([pscustomobject]@{ name = 'secured'; env = [pscustomobject]@{ API_TOKEN = 'secret-value' }; headers = [pscustomobject]@{ Authorization = 'Bearer secret-value' } }) }
        $secure = ConvertTo-SecureString 'migration-test-passphrase' -AsPlainText -Force
        $encrypted = Protect-MigrationCredentialPayload $payload $secure
        ($encrypted | ConvertTo-Json -Depth 12) | Should -Not -Match 'secret-value'
        $roundTrip = Unprotect-MigrationCredentialPayload $encrypted $secure | ConvertFrom-Json
        $roundTrip.mcp_servers[0].env.API_TOKEN | Should -Be 'secret-value'
        { Unprotect-MigrationCredentialPayload $encrypted (ConvertTo-SecureString 'wrong-passphrase' -AsPlainText -Force) } | Should -Throw '*口令错误*'
    }

    It 'creates a private-general bundle with an encrypted credential companion file' {
        Mock Read-Host { ConvertTo-SecureString 'migration-test-passphrase' -AsPlainText -Force }
        $out = Join-Path $TestDrive 'private-general.zip'
        Invoke-MigrationCommand @('--mode','private-general','--encrypt','--out',$out)
        $extract = Join-Path $TestDrive 'private-general-extract'
        Expand-Archive -LiteralPath $out -DestinationPath $extract
        $root = Join-Path $extract 'skills-manager-migration-private-general'
        $manifest = Get-Content -LiteralPath (Join-Path $root 'MIGRATION-MANIFEST.json') -Raw | ConvertFrom-Json
        $manifest.includes_credentials | Should -BeTrue
        $manifest.credential_file | Should -Be 'MIGRATION-MCP-CREDENTIALS.enc.json'
        Test-Path -LiteralPath (Join-Path $root 'MIGRATION-MCP-CREDENTIALS.enc.json') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $root 'MIGRATION-MCP-CREDENTIALS.enc.json') -Raw) | Should -Not -Match 'migration-test-passphrase'
        $manifest.development_ready | Should -BeFalse
        $manifest.restore_ready | Should -BeTrue
        $manifest.git_history_included | Should -BeFalse
        $manifest.license_file | Should -Be 'LICENSE'
        Test-Path -LiteralPath (Join-Path $root 'LICENSE') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'tests\Unit\Migration.Tests.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'docs\INSTALLATION_AND_MIGRATION.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'MIGRATION-CONTENT.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'references\reference-shelf.manifest.json') | Should -BeTrue
    }

    It 'accepts documented CLI long options without top-level PowerShell binding loss' {
        $out = Join-Path $TestDrive 'cli-rescan.zip'
        & pwsh -NoProfile -File (Join-Path $repoRoot 'skills.ps1') migration --mode rescan --out $out --force --json | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $out | Should -BeTrue
    }

    It 'creates a rescan bundle without skills or MCP payload' {
        $out = Join-Path $TestDrive 'rescan.zip'
        Invoke-MigrationCommand @('--mode','rescan','--out',$out)
        Test-Path -LiteralPath $out | Should -BeTrue
        $extract = Join-Path $TestDrive 'rescan-extract'
        Expand-Archive -LiteralPath $out -DestinationPath $extract
        $root = Join-Path $extract 'skills-manager-migration-rescan'
        $manifest = Get-Content -LiteralPath (Join-Path $root 'MIGRATION-MANIFEST.json') -Raw | ConvertFrom-Json
        $manifest.mode | Should -Be 'rescan'
        @($manifest.apply) | Should -Contain '先在新电脑安装同版本的 skills-manager'
        Test-Path -LiteralPath (Join-Path $root 'agent') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'skills.json') | Should -BeFalse
    }

    It 'uses a timestamped ignored migration directory when no output path is supplied' {
        $result = Invoke-MigrationCommand @('--mode','rescan','--json') | ConvertFrom-Json
        $result.path | Should -Match ([regex]::Escape('\artifacts\deliveries\migration\'))
        $result.path | Should -Match '\\artifacts\\deliveries\\migration\\[^\\]+\\migration-rescan-[^\\]+\.zip$'
    }

    It 'rejects repository artifact-root output that bypasses the migration contract' {
        $out = Join-Path $repoRoot 'artifacts\migration-contract.zip'
        { Invoke-MigrationCommand @('--mode','rescan','--out',$out) } | Should -Throw '*Migration output under artifacts*'
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'general bundle uses core skills and strips MCP credential values' {
        $out = Join-Path $TestDrive 'general.zip'
        Invoke-MigrationCommand @('--mode','general','--out',$out)
        $extract = Join-Path $TestDrive 'general-extract'
        Expand-Archive -LiteralPath $out -DestinationPath $extract
        $root = Join-Path $extract 'skills-manager-migration-general'
        $manifest = Get-Content -LiteralPath (Join-Path $root 'MIGRATION-MANIFEST.json') -Raw | ConvertFrom-Json
        @($manifest.skills) | Should -Contain 'systematic-debugging'
        $cfg = Get-Content -LiteralPath (Join-Path $root 'skills.json') -Raw | ConvertFrom-Json
        @($cfg.mcp_servers | ForEach-Object { $_.name }) | Should -Contain 'microsoft-learn'
        foreach ($server in @($cfg.mcp_servers)) {
            $server.PSObject.Properties.Name | Should -Not -Contain 'headers'
            $server.PSObject.Properties.Name | Should -Not -Contain 'env'
        }
        Test-Path -LiteralPath (Join-Path $root 'src\Main.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'config\skills.schema.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'LICENSE') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'README.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'tests\Unit\Migration.Tests.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'docs\INSTALLATION_AND_MIGRATION.md') | Should -BeTrue
        @($cfg.imports | ForEach-Object name) | Should -Contain 'codebase-design'
        Test-Path -LiteralPath (Join-Path $root 'imports\codebase-design') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $root -Force -Recurse -Directory -Filter '.git').Count | Should -Be 0
        & pwsh -NoProfile -File (Join-Path $root 'build.ps1') | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'accepts migration-apply options and dispatches the command name' {
        (Get-MigrationApplyTokens @('--skip-mcp','--json')).skip_mcp | Should -BeTrue
        (Get-MigrationApplyTokens @('--skip-mcp','--json')).json | Should -BeTrue
        $version = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Version.ps1') -Raw
        $version | Should -Match 'migration-apply'
        (Get-Content -LiteralPath (Join-Path $repoRoot 'src\Main.ps1') -Raw) | Should -Match 'Invoke-MigrationApplyCommand'
    }

    It 'redacts MCP environment and header values while retaining only reference names' {
        $server = [pscustomobject]@{
            name = 'secured-docs'
            transport = 'http'
            url = 'https://example.invalid/mcp'
            env = [pscustomobject]@{ API_TOKEN = 'do-not-copy' }
            headers = [pscustomobject]@{ Authorization = 'Bearer do-not-copy' }
        }
        $intent = Get-MigrationMcpIntent $server
        $intent.PSObject.Properties.Name | Should -Not -Contain 'env'
        $intent.PSObject.Properties.Name | Should -Not -Contain 'headers'
        @($intent.credential_reference_names) | Should -Contain 'API_TOKEN'
        @($intent.credential_reference_names) | Should -Contain 'Authorization'
        ($intent | ConvertTo-Json -Depth 8) | Should -Not -Match 'do-not-copy'
    }
}
