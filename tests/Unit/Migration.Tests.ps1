BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')
}

Describe 'Migration bundles' {
    It 'prunes excluded trees before enumeration and preserves empty payload directories' {
        $source = Join-Path $TestDrive 'prune-source'
        $destination = Join-Path $TestDrive 'prune-output'
        New-Item -ItemType Directory -Path (Join-Path $source '.git/objects'), (Join-Path $source 'private/cache'), (Join-Path $source 'empty') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'visible.txt') -Value 'payload'
        Mock Get-ChildItem { param($LiteralPath) [IO.DirectoryInfo]::new($LiteralPath).GetFileSystemInfos() }
        Mock Get-ChildItem { throw 'excluded tree must not be enumerated' } -ParameterFilter {
            $Recurse -or $LiteralPath -match '[\\/](\.git|private)([\\/]|$)'
        }
        Copy-MigrationTree $source $destination @('private') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $destination 'empty') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $destination 'visible.txt') | Should -Be 'payload'
        Test-Path -LiteralPath (Join-Path $destination '.git') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $destination 'private') | Should -BeFalse
    }

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
            foreach ($relative in @('src/model-orchestration/.state/run/backup.json', 'src/model-orchestration/.generated/codex/role.toml', 'src/model-orchestration/presets.json')) {
                $path = Join-Path $fixtureRoot $relative
                New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
                Set-Content -LiteralPath $path -Value 'fixture-only'
            }
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
        Test-Path -LiteralPath (Join-Path $packageRoot 'src/model-orchestration/presets.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $packageRoot 'src/model-orchestration/.state') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $packageRoot 'src/model-orchestration/.generated') | Should -BeFalse
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

Describe 'Migration credential unlock' {
    BeforeAll {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
        . (Join-Path $repoRoot 'skills.ps1')

        # 与 Unprotect-MigrationCredentialPayload 的格式契约一致（AAD、KDF、字段长度），
        # 用于端到端验证加密分支的解密路径，而不是自证 mock。
        function Protect-TestCredentialPayload([string]$Json, [string]$Passphrase) {
            $salt = [byte[]]::new(16); [Security.Cryptography.RandomNumberGenerator]::Fill($salt)
            $nonce = [byte[]]::new(12); [Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
            $plain = [Text.Encoding]::UTF8.GetBytes($Json)
            $tag = [byte[]]::new(16)
            $cipher = [byte[]]::new($plain.Length)
            $key = [byte[]]::new(32)
                $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($Passphrase, $salt, 200000, [Security.Cryptography.HashAlgorithmName]::SHA256)
            try {
                [Array]::Copy($kdf.GetBytes($key.Length), $key, $key.Length)
                $aad = [Text.Encoding]::UTF8.GetBytes('skills-manager:migration:mcp:v1')
                $aes = [Security.Cryptography.AesGcm]::new($key, $tag.Length)
                # .NET 10 运行时 Encrypt 参数序为 (nonce, plaintext, ciphertext, tag, aad)。
                try { $aes.Encrypt($nonce, $plain, $cipher, $tag, $aad) } finally { $aes.Dispose() }
            }
            finally { $kdf.Dispose(); [Array]::Clear($key, 0, $key.Length) }
            [pscustomobject][ordered]@{
                schema_version = 1
                algorithm = 'AES-256-GCM'
                kdf = 'PBKDF2-SHA256'
                iterations = 200000
                salt = [Convert]::ToBase64String($salt)
                nonce = [Convert]::ToBase64String($nonce)
                tag = [Convert]::ToBase64String($tag)
                ciphertext = [Convert]::ToBase64String($cipher)
            }
        }

        function New-UnlockPackageFixture {
            param(
                [string]$Name,
                [object]$CredentialDocument,
                [string[]]$ManifestServers = @('fixture-mcp'),
                [string]$Mode = 'private-general',
                [bool]$Encrypted = $false,
                [bool]$IncludesCredentials = $true
            )
            $packageRoot = Join-Path $TestDrive $Name
            New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
            $credentialName = if ($Encrypted) { 'MIGRATION-MCP-CREDENTIALS.enc.json' } else { 'MIGRATION-MCP-CREDENTIALS.json' }
            $CredentialDocument | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot $credentialName) -Encoding UTF8
            [pscustomobject][ordered]@{
                schema_version = 1
                kind = 'migration'
                mode = $Mode
                includes_credentials = $IncludesCredentials
                credentials_encrypted = $Encrypted
                credential_file = $credentialName
                mcp_servers = $ManifestServers
                private_use_only = $true
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'MIGRATION-MANIFEST.json') -Encoding UTF8
            $contentEntries = @(Get-PackageFileEntries $packageRoot)
            [ordered]@{ schema_version = 1; files = @($contentEntries) } |
                ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'MIGRATION-CONTENT.json') -Encoding UTF8
            return $packageRoot
        }

        function New-UnlockWorkspaceConfig {
            $cfgPath = Join-Path $TestDrive ('skills-' + [guid]::NewGuid().ToString('N') + '.json')
            [ordered]@{
                schema_version = 3
                sync_mode = 'copy'
                vendors = @()
                targets = @()
                mappings = @()
                imports = @()
                mcp_servers = @(
                    [ordered]@{ name = 'fixture-mcp'; enabled = $true; transport = 'stdio'; command = 'fixture-cmd'; args = @() }
                )
                mcp_targets = @()
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
            return $cfgPath
        }

        function Invoke-UnlockScenario {
            # 以普通局部变量赋值 $Root/$CfgPath：被调 CLI 函数沿动态作用域链即可见，
            # 与既有用例在 It 体内直接赋值同一机制。
            param([string]$PackageRoot, [string]$WorkspaceCfgPath, [string[]]$UnlockTokens)
            $oldRoot = $Root
            $oldCfgPath = $CfgPath
            try {
                $Root = $PackageRoot
                $CfgPath = $WorkspaceCfgPath
                Invoke-MigrationUnlockCommand $UnlockTokens
            }
            finally {
                $Root = $oldRoot
                $CfgPath = $oldCfgPath
            }
        }
    }

    It 'restores plaintext credential fields into skills.json with --yes' {
        $packageRoot = New-UnlockPackageFixture -Name 'unlock-plain' -CredentialDocument ([pscustomobject][ordered]@{
                schema_version = 1
                mcp_servers = @(
                    [pscustomobject][ordered]@{ name = 'fixture-mcp'; env = [pscustomobject][ordered]@{ FIXTURE_ENDPOINT = 'https://fixture.invalid' } }
                )
            })
        $cfgPath = New-UnlockWorkspaceConfig
        $result = Invoke-UnlockScenario $packageRoot $cfgPath @('--yes', '--json') | ConvertFrom-Json

        $result.restored_fields | Should -Be 1
        $written = Get-ContentUtf8 $cfgPath | ConvertFrom-Json
        $written.mcp_servers[0].env.FIXTURE_ENDPOINT | Should -Be 'https://fixture.invalid'
    }

    It 'rejects a credentials file outside the package root' {
        $packageRoot = New-UnlockPackageFixture -Name 'unlock-escape' -CredentialDocument ([pscustomobject][ordered]@{
                schema_version = 1; mcp_servers = @()
            })
        $cfgPath = New-UnlockWorkspaceConfig
        $outside = Join-Path $TestDrive 'outside-credentials.json'
        'not-a-credential' | Set-Content -LiteralPath $outside -Encoding UTF8

        { Invoke-UnlockScenario $packageRoot $cfgPath @('--yes', '--credentials', $outside) } |
            Should -Throw '*凭据文件必须位于当前迁移包目录内*'
    }

    It 'rejects restore for a server absent from the manifest' {
        $packageRoot = New-UnlockPackageFixture -Name 'unlock-foreign' -CredentialDocument ([pscustomobject][ordered]@{
                schema_version = 1
                mcp_servers = @(
                    [pscustomobject][ordered]@{ name = 'foreign-mcp'; env = [pscustomobject][ordered]@{ FIXTURE_ENDPOINT = 'https://fixture.invalid' } }
                )
            }) -ManifestServers @('fixture-mcp')
        $cfgPath = New-UnlockWorkspaceConfig

        { Invoke-UnlockScenario $packageRoot $cfgPath @('--yes') } |
            Should -Throw '*迁移凭据服务不在 manifest 中*'
    }

    It 'skips unsafe credential fields and restores nothing' {
        $unsafeValue = "https://fixture.invalid`ninjected-line"
        $packageRoot = New-UnlockPackageFixture -Name 'unlock-unsafe' -CredentialDocument ([pscustomobject][ordered]@{
                schema_version = 1
                mcp_servers = @(
                    [pscustomobject][ordered]@{ name = 'fixture-mcp'; env = [pscustomobject][ordered]@{ FIXTURE_ENDPOINT = $unsafeValue } }
                )
            })
        $cfgPath = New-UnlockWorkspaceConfig
        $result = Invoke-UnlockScenario $packageRoot $cfgPath @('--yes', '--json') | ConvertFrom-Json

        $result.restored_fields | Should -Be 0
        $written = Get-ContentUtf8 $cfgPath | ConvertFrom-Json
        $written.mcp_servers[0].PSObject.Properties['env'] | Should -BeNullOrEmpty
    }

    It 'decrypts the encrypted credential branch with the passphrase' {
        $plainPayload = [pscustomobject][ordered]@{
            schema_version = 1
            mcp_servers = @(
                [pscustomobject][ordered]@{ name = 'fixture-mcp'; headers = [pscustomobject][ordered]@{ 'X-Fixture' = 'fixture-value' } }
            )
        }
        $encrypted = Protect-TestCredentialPayload -Json ($plainPayload | ConvertTo-Json -Depth 8) -Passphrase 'test-pass-1234'
        $packageRoot = New-UnlockPackageFixture -Name 'unlock-encrypted' -CredentialDocument $encrypted -Encrypted $true
        $cfgPath = New-UnlockWorkspaceConfig
        Mock Read-Host { ConvertTo-SecureString 'test-pass-1234' -AsPlainText -Force }

        $result = Invoke-UnlockScenario $packageRoot $cfgPath @('--yes', '--json') | ConvertFrom-Json

        $result.restored_fields | Should -Be 1
        $written = Get-ContentUtf8 $cfgPath | ConvertFrom-Json
        $written.mcp_servers[0].headers.'X-Fixture' | Should -Be 'fixture-value'
    }

    It 'apply auto-unlocks private credential packages without prompting' {
        # 假 install.ps1 必须先于 content manifest 生成写入，才能通过完整性闭包校验。
        $packageRoot = Join-Path $TestDrive 'unlock-apply'
        New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
        @'
param([string]$Mode, [switch]$SkipRebuildLocked, [switch]$SyncMcp)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'applied.marker') -Value 'applied'
'@ | Set-Content -LiteralPath (Join-Path $packageRoot 'install.ps1') -Encoding UTF8
        $packageRoot = New-UnlockPackageFixture -Name 'unlock-apply' -CredentialDocument ([pscustomobject][ordered]@{
                schema_version = 1
                mcp_servers = @(
                    [pscustomobject][ordered]@{ name = 'fixture-mcp'; env = [pscustomobject][ordered]@{ FIXTURE_ENDPOINT = 'https://fixture.invalid' } }
                )
            }) -Mode 'private-general'
        $cfgPath = New-UnlockWorkspaceConfig
        # 若解锁路径触发口令提示（本包为明文凭据，不应提示），测试立即失败。
        Mock Read-Host { throw 'migration-apply must not prompt for a passphrase' }

        $oldRoot = $Root
        $oldCfgPath = $CfgPath
        try {
            $Root = $packageRoot
            $CfgPath = $cfgPath
            $result = Invoke-MigrationApplyCommand @('--skip-mcp', '--json') | ConvertFrom-Json
        }
        finally {
            $Root = $oldRoot
            $CfgPath = $oldCfgPath
        }

        $result.exit_code | Should -Be 0
        Test-Path -LiteralPath (Join-Path $packageRoot 'applied.marker') | Should -BeTrue
        $written = Get-ContentUtf8 $cfgPath | ConvertFrom-Json
        $written.mcp_servers[0].env.FIXTURE_ENDPOINT | Should -Be 'https://fixture.invalid'
    }
}
