BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')

}
Describe 'MCP machine-readable planning' {
    BeforeAll {
$createdAt = '2026-08-01T08:00:00Z'
$sourceRevision = 'f' * 64
function New-TestMcpServer([string]$Name = 'fixture') {
        return [pscustomobject]@{
            name = $Name
            transport = 'stdio'
            command = 'fixture-command'
            args = @('--token', '${FIXTURE_ARG_TOKEN}')
            env = [pscustomobject]@{ FIXTURE_ENV_FLAG = 'enabled' }
        }
    }
function New-TestDesiredState([string]$Root, [bool]$ExistingMatches = $false) {
        $specs = @(Get-McpSyncManagedTargetSpecs -Roots @(
                (Join-Path $Root '.codex'),
                (Join-Path $Root '.gemini'),
                (Join-Path $Root '.trae')
            ) -RepoRoot $Root)
        $server = New-TestMcpServer
        $initial = New-McpSyncDesiredState -Specs $specs -Servers @($server) -ActiveServers @($server)
        $states = @{}
        foreach ($target in @($initial)) {
            $states[(Normalize-OperationPathKey $target.path)] = [pscustomobject]@{
                exists = $ExistingMatches
                content = if ($ExistingMatches) { [string]$target.desired_content } else { '' }
            }
        }
        return @(New-McpSyncDesiredState -Specs $specs -Servers @($server) -ActiveServers @($server) -ExistingStates $states)
    }
}

    It 'enumerates only known managed targets and adds project Trae only when Trae is present' {
        $root = Join-Path $TestDrive 'targets'
        $repo = Join-Path $TestDrive 'repo'
        $withoutTrae = @(Get-McpSyncManagedTargetSpecs -Roots @((Join-Path $root '.codex')) -RepoRoot $root)
        $withTrae = @(Get-McpSyncManagedTargetSpecs -Roots @(
                (Join-Path $root '.codex'),
                (Join-Path $root '.gemini'),
                (Join-Path $root '.trae')
            ) -RepoRoot $repo)

        @($withoutTrae | Where-Object kind -eq 'trae_project_json').Count | Should -Be 0
        (@($withTrae.kind | Sort-Object) -join ',') | Should -Be 'codex_toml,gemini_settings,trae_json,trae_project_json'
        @($withTrae | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.path) }).Count | Should -Be 0
    }

    It 'maps Claude Code, Claude Desktop, and Antigravity to their native config files' {
        $testHome = Join-Path $TestDrive 'native-hosts'
        $claudeRoot = Join-Path $testHome '.claude'
        $geminiRoot = Join-Path $testHome '.gemini'
        $desktopConfig = Join-Path (Join-Path $TestDrive 'appdata' 'Claude') 'claude_desktop_config.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $desktopConfig) -Force | Out-Null

        $specs = @(Get-McpSyncManagedTargetSpecs -Roots @($claudeRoot, $geminiRoot) -RepoRoot $testHome `
            -ClaudeUserRoot $claudeRoot -ClaudeUserConfigPath (Join-Path $testHome '.claude.json') `
            -ClaudeDesktopConfigPath $desktopConfig -AntigravityUserRoot $geminiRoot)

        (@($specs.kind | Sort-Object) -join ',') | Should -Be 'antigravity_mcp_json,claude_code_json,claude_desktop_json,gemini_settings'
        ($specs | Where-Object kind -eq 'claude_code_json').path | Should -Be (Join-Path $testHome '.claude.json')
        ($specs | Where-Object kind -eq 'claude_desktop_json').path | Should -Be $desktopConfig
        ($specs | Where-Object kind -eq 'antigravity_mcp_json').path | Should -Be (Join-Path (Join-Path $geminiRoot 'config') 'mcp_config.json')
        @($specs.path | Where-Object { $_ -match '\\.mcp\.json$' }).Count | Should -Be 0
    }

    It 'maps Claude user MCP configuration when CLAUDE_CONFIG_DIR has a custom directory name' {
        $testHome = Join-Path $TestDrive 'claude-custom-config-root'
        $claudeRoot = Join-Path $testHome 'claude-state'
        $claudeConfig = Join-Path $testHome '.claude.json'
        $desktopConfig = Join-Path $TestDrive 'missing-desktop' 'Claude' 'claude_desktop_config.json'
        $oldConfigDir = [Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR')
        try {
            [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $claudeRoot)
            $specs = @(Get-McpSyncManagedTargetSpecs -Roots @($claudeRoot) -RepoRoot $testHome `
                -ClaudeUserConfigPath $claudeConfig -ClaudeDesktopConfigPath $desktopConfig)

            @($specs.kind) | Should -Be @('claude_code_json')
            $specs[0].path | Should -Be $claudeConfig

            Set-ContentUtf8 $claudeConfig '{"mcpServers":{"custom-user":{"command":"fixture"}}}'
            $expected = Get-McpExpectedServersByCli @($claudeRoot) -ClaudeUserConfigPath $claudeConfig
            @($expected.claude) | Should -Be @('custom-user')
        }
        finally {
            [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $oldConfigDir)
        }
    }

    It 'does not create empty Claude or Antigravity MCP files and leaves host-only JSON byte-identical' {
        $testHome = Join-Path $TestDrive 'empty-profile'
        $claudeRoot = Join-Path $testHome '.claude'
        $geminiRoot = Join-Path $testHome '.gemini'
        $desktopPath = Join-Path (Join-Path $TestDrive 'empty-appdata' 'Claude') 'claude_desktop_config.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $desktopPath) -Force | Out-Null
        $claudeContent = '{"projects":{"C:/WINDOWS/System32":{"x":1},"C:/WINDOWS/system32":{"x":2}}}'
        $desktopContent = '{ "theme": "dark", "locale": "en-US" }'
        Set-ContentUtf8 $desktopPath $desktopContent
        $specs = @(Get-McpSyncManagedTargetSpecs -Roots @($claudeRoot, $geminiRoot) -RepoRoot $testHome `
            -ClaudeUserRoot $claudeRoot -ClaudeUserConfigPath (Join-Path $testHome '.claude.json') `
            -ClaudeDesktopConfigPath $desktopPath -AntigravityUserRoot $geminiRoot)
        $states = @{}
        $states[(Normalize-OperationPathKey (Join-Path $testHome '.claude.json'))] = [pscustomobject]@{ exists = $true; content = $claudeContent }
        $states[(Normalize-OperationPathKey $desktopPath)] = [pscustomobject]@{ exists = $true; content = $desktopContent }
        foreach ($spec in @($specs | Where-Object { $_.kind -notin @('claude_code_json', 'claude_desktop_json') })) {
            $states[(Normalize-OperationPathKey $spec.path)] = [pscustomobject]@{ exists = $false; content = '' }
        }
        $disabled = New-TestMcpServer 'disabled-fixture'

        $desired = @(New-McpSyncDesiredState -Specs $specs -Servers @($disabled) -ActiveServers @() `
            -ProfileDisabledNames @('disabled-fixture') -ExistingStates $states)

        $desired.Count | Should -Be 2
        @($desired | Where-Object changed).Count | Should -Be 0
        ([string]($desired | Where-Object path -eq (Join-Path $testHome '.claude.json')).desired_content) | Should -Be $claudeContent
        ([string]($desired | Where-Object path -eq $desktopPath).desired_content) | Should -Be $desktopContent
        @($desired.path | Where-Object { $_ -match 'mcp_config\.json$' }).Count | Should -Be 0

        $states[(Normalize-OperationPathKey $desktopPath)] = [pscustomobject]@{ exists = $false; content = '' }
        $withoutDesktop = @(New-McpSyncDesiredState -Specs $specs -Servers @($disabled) -ActiveServers @() `
            -ProfileDisabledNames @('disabled-fixture') -ExistingStates $states)
        @($withoutDesktop.path | Where-Object { $_ -eq $desktopPath }).Count | Should -Be 0
    }

    It 'removes only explicitly uninstalled entries from Claude JSON and Codex TOML' {
        $testHome = Join-Path $TestDrive 'explicit-removal'
        $claudePath = Join-Path $testHome '.claude.json'
        $codexPath = Join-Path $testHome '.codex\config.toml'
        $claudeContent = '{"theme":"dark","mcpServers":{"retired":{"command":"stale"},"host-owned":{"command":"keep"}}}'
        $codexContent = @'
model = "host-model"
approval_policy = "never"

[mcp_servers.retired]
command = "stale"

[mcp_servers.node_repl]
command = "node"
'@
        $server = New-TestMcpServer 'active_server'
        $specs = @(
            [pscustomobject]@{ kind = 'claude_code_json'; path = $claudePath; root = $testHome; target_ref = 'test:claude-code' },
            [pscustomobject]@{ kind = 'codex_toml'; path = $codexPath; root = (Join-Path $testHome '.codex'); target_ref = 'test:codex' }
        )
        $states = @{
            (Normalize-OperationPathKey $claudePath) = [pscustomobject]@{ exists = $true; content = $claudeContent }
            (Normalize-OperationPathKey $codexPath) = [pscustomobject]@{ exists = $true; content = $codexContent }
        }

        $desired = @(New-McpSyncDesiredState -Specs $specs -Servers @($server) -ActiveServers @($server) `
            -ExplicitRemovalNames @('retired') -ExistingStates $states)
        $claude = ([string]($desired | Where-Object path -eq $claudePath).desired_content) | ConvertFrom-Json
        $codex = [string]($desired | Where-Object path -eq $codexPath).desired_content

        $claude.mcpServers.PSObject.Properties.Name | Should -Contain 'host-owned'
        $claude.mcpServers.PSObject.Properties.Name | Should -Contain 'active_server'
        $claude.mcpServers.PSObject.Properties.Name | Should -Not -Contain 'retired'
        $claude.theme | Should -Be 'dark'
        $codex | Should -Match 'model = "host-model"'
        $codex | Should -Match '\[mcp_servers\.active_server\]'
        $codex | Should -Match '\[mcp_servers\.node_repl\]'
        $codex | Should -Not -Match '\[mcp_servers\.retired\]'
    }

    It 'preflights the final MCP state before saving an uninstall' {
        $oldCfgPath = $CfgPath
        $oldDryRun = $DryRun
        try {
            $CfgPath = Join-Path $TestDrive 'uninstall-preflight' 'skills.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $CfgPath) -Force | Out-Null
            Set-ContentUtf8 $CfgPath '{}'
            $cfg = [pscustomobject]@{
                mcp_servers = @([pscustomobject]@{ name = 'fixture'; transport = 'stdio'; command = 'fixture-command' })
                mcp_profiles = @()
            }
            $DryRun = $false
            Mock LoadCfg { $cfg }
            Mock Get-McpSyncPlanningContext { throw 'preflight-blocked' }
            Mock SaveCfgSafe {}
            Mock 同步MCP {}

            { 卸载MCP @('fixture') } | Should -Throw '*preflight-blocked*'

            Should -Invoke Get-McpSyncPlanningContext -Times 1 -Exactly -ParameterFilter {
                $ReadOnlyConfig -and $ExplicitRemovalNames -contains 'fixture'
            }
            Should -Invoke SaveCfgSafe -Times 0 -Exactly
            Should -Invoke 同步MCP -Times 0 -Exactly
        }
        finally {
            $CfgPath = $oldCfgPath
            $DryRun = $oldDryRun
        }
    }

    It 'does not save source config during a dry-run MCP uninstall' {
        $oldCfgPath = $CfgPath
        $oldDryRun = $DryRun
        try {
            $CfgPath = Join-Path $TestDrive 'uninstall-dry-run' 'skills.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $CfgPath) -Force | Out-Null
            Set-ContentUtf8 $CfgPath '{}'
            $beforeHash = (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash
            $cfg = [pscustomobject]@{
                mcp_servers = @([pscustomobject]@{ name = 'fixture'; transport = 'stdio'; command = 'fixture-command' })
                mcp_profiles = @()
            }
            $DryRun = $true
            Mock LoadCfg { $cfg }
            Mock SaveCfgSafe {}
            Mock 同步MCP {}

            卸载MCP @('fixture')

            Should -Invoke SaveCfgSafe -Times 0 -Exactly
            Should -Invoke 同步MCP -Times 1 -Exactly -ParameterFilter { $ExplicitRemovalNames -contains 'fixture' }
            (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash | Should -Be $beforeHash
        }
        finally {
            $CfgPath = $oldCfgPath
            $DryRun = $oldDryRun
        }
    }

    It 'preserves unowned fetch and filesystem servers when they are absent from repository config' {
        $testHome = Join-Path $TestDrive 'unowned-servers'
        $claudeConfig = Join-Path $testHome '.claude.json'
        $existing = '{"mcpServers":{"fetch":{"command":"fetch-wrapper","args":["--local"]},"filesystem":{"command":"fs-wrapper","args":["D:/notes"]}},"theme":"dark"}'
        $states = @{}
        $states[(Normalize-OperationPathKey $claudeConfig)] = [pscustomobject]@{ exists = $true; content = $existing }
        $spec = [pscustomobject]@{ kind = 'claude_code_json'; path = $claudeConfig; root = $testHome; target_ref = 'test:claude-code' }

        $desired = @(New-McpSyncDesiredState -Specs @($spec) -Servers @() -ActiveServers @() -ExistingStates $states)

        $desired.Count | Should -Be 1
        $desired[0].changed | Should -Be $false
        $desired[0].desired_content | Should -Be $existing
    }

    It 'leaves Codex TOML byte-identical when the empty profile has no repository-managed section' {
        $testHome = Join-Path $TestDrive 'codex-host-owned'
        $codexConfig = Join-Path $testHome '.codex\config.toml'
        $existing = "[mcp_servers.node_repl]`r`ncommand = 'node'`r`n`r`n"
        $server = New-TestMcpServer 'context7'
        $states = @{}
        $states[(Normalize-OperationPathKey $codexConfig)] = [pscustomobject]@{ exists = $true; content = $existing }
        $spec = [pscustomobject]@{ kind = 'codex_toml'; path = $codexConfig; root = (Join-Path $testHome '.codex'); target_ref = 'test:codex' }

        $desired = @(New-McpSyncDesiredState -Specs @($spec) -Servers @($server) -ActiveServers @() `
            -ProfileDisabledNames @('context7') -ExistingStates $states)

        $desired.Count | Should -Be 1
        $desired[0].changed | Should -Be $false
        $desired[0].desired_content | Should -Be $existing
    }

    It 'removes profile-disabled Codex servers and preserves host-owned entries' {
        $testHome = Join-Path $TestDrive 'codex-empty-profile'
        $codexConfig = Join-Path $testHome '.codex\config.toml'
        $existing = @'
model = "host-model"
approval_policy = "never"

[mcp_servers.context7]
command = "old-context7"

[mcp_servers.microsoft-learn]
command = "old-docs"

[mcp_servers.node_repl]
command = "node"
'@
        $servers = @(New-TestMcpServer 'context7'; New-TestMcpServer 'microsoft-learn')
        $states = @{}
        $states[(Normalize-OperationPathKey $codexConfig)] = [pscustomobject]@{ exists = $true; content = $existing }
        $spec = [pscustomobject]@{ kind = 'codex_toml'; path = $codexConfig; root = (Join-Path $testHome '.codex'); target_ref = 'test:codex' }

        $desired = @(New-McpSyncDesiredState -Specs @($spec) -Servers $servers -ActiveServers @() `
            -ProfileDisabledNames @('context7', 'microsoft-learn') -ExistingStates $states)
        $content = [string]$desired[0].desired_content

        $desired[0].changed | Should -Be $true
        $content | Should -Match 'model = "host-model"'
        $content | Should -Match '\[mcp_servers\.node_repl\]'
        $content | Should -Not -Match '\[mcp_servers\.(context7|microsoft-learn)\]'
    }

    It 'uses the WorkBuddy bare mcp.json name instead of the dot-prefixed sidecar' {
        # WorkBuddy reads "<configDir>/mcp.json"; a ".mcp.json" there is never loaded,
        # so the generic default would make the sync a silent no-op on that host.
        $root = Join-Path $TestDrive 'workbuddy-root'
        $workbuddy = Join-Path $root '.workbuddy-ai'
        $specs = @(Get-McpSyncManagedTargetSpecs -Roots @($workbuddy) -RepoRoot $root)

        @($specs.kind) | Should -Be @('generic_json')
        $specs[0].path | Should -Be (Join-Path $workbuddy 'mcp.json')
    }

    It 'honours an env-declared WorkBuddy config dir with a custom folder name' {
        $oldEnv = [string]$env:WORKBUDDY_CONFIG_DIR
        try {
            $root = Join-Path $TestDrive 'branded-workbuddy'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $env:WORKBUDDY_CONFIG_DIR = $root
            $specs = @(Get-McpSyncManagedTargetSpecs -Roots @($root) -RepoRoot $TestDrive)

            @($specs.kind) | Should -Be @('generic_json')
            $specs[0].path | Should -Be (Join-Path $root 'mcp.json')
        }
        finally {
            if ($oldEnv) { $env:WORKBUDDY_CONFIG_DIR = $oldEnv } else { Remove-Item Env:\WORKBUDDY_CONFIG_DIR -ErrorAction SilentlyContinue }
        }
    }

    It 'fails closed when no MCP target roots resolve' {
        $oldCfgPath = $CfgPath
        try {
            $root = Join-Path $TestDrive 'no-targets'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $CfgPath = Join-Path $root 'skills.json'
            $cfg = [pscustomobject]@{
                targets     = @()
                mcp_targets = @()
                mcp_servers = @()
            }
            Mock Load-McpPlanConfigReadOnly { [pscustomobject]@{ cfg = $cfg; raw = '{}' } }

            # 回归钉：resolver 的嵌套返回曾使 roots.Count 恒为 1，空配置
            # 被静默放行为"同步 0 个目标"。
            { Get-McpSyncPlanningContext -ReadOnlyConfig } | Should -Throw '*未找到可同步的 MCP 目标目录*'
        }
        finally { $CfgPath = $oldCfgPath }
    }

    It 'treats explicitly removed servers as absent while building a dry-run plan' {
        $oldRoot = $script:Root
        $oldDryRun = $DryRun
        try {
            $script:Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
            $claudeRoot = Join-Path $TestDrive 'dry-run-removal\.claude'
            $claudePath = Join-Path $TestDrive 'dry-run-removal\.claude.json'
            $cfg = [pscustomobject]@{
                targets = @([pscustomobject]@{ path = (Join-Path $claudeRoot 'skills') })
                mcp_targets = @()
                mcp_servers = @([pscustomobject]@{ name = 'retired'; transport = 'stdio'; command = 'stale' })
                mcp_profiles = [pscustomobject]@{
                    active = 'default'
                    profiles = [pscustomobject]@{
                        default = [pscustomobject]@{ enabled = @('retired') }
                    }
                }
            }
            $spec = [pscustomobject]@{ kind = 'claude_code_json'; path = $claudePath; root = $claudeRoot; target_ref = 'test:claude-code' }
            $existing = '{"mcpServers":{"retired":{"command":"stale"},"host-owned":{"command":"keep"}}}'
            $states = @{ (Normalize-OperationPathKey $claudePath) = [pscustomobject]@{ exists = $true; content = $existing } }
            Mock Load-McpPlanConfigReadOnly { [pscustomobject]@{ cfg = $cfg; raw = '{}' } }
            Mock Resolve-McpTargetRootsFromCfg { @($claudeRoot) }
            Mock Get-McpSyncManagedTargetSpecs { @($spec) }
            Mock Get-McpExistingStates { $states }

            $DryRun = $true
            $context = Get-McpSyncPlanningContext -ReadOnlyConfig -ExplicitRemovalNames @('retired')

            @($context.servers).Count | Should -Be 0
            @($context.active_servers).Count | Should -Be 0
            @($context.profile_disabled_names).Count | Should -Be 0
            @($context.explicit_removal_names) | Should -Be @('retired')
            $payload = [string]$context.desired_state[0].desired_content | ConvertFrom-Json
            $payload.mcpServers.PSObject.Properties.Name | Should -Contain 'host-owned'
            $payload.mcpServers.PSObject.Properties.Name | Should -Not -Contain 'retired'
        }
        finally {
            $script:Root = $oldRoot
            $DryRun = $oldDryRun
        }
    }

    It 'Does not copy the GITHUB token into process env in read-only plan context' {
        $oldCodex = [string]$env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
        $oldGithub = [string]$env:GITHUB_PERSONAL_ACCESS_TOKEN
        $oldCfgPath = $CfgPath
        $oldRoot = $script:Root
        try {
            # Get-McpSyncPlanningContext 读显式 \$script:Root（动态作用域盖不住）。
            $script:Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
            Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            $env:GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_test_plan_only"
            $root = Join-Path $TestDrive 'plan-env'
            $cfg = [pscustomobject]@{
                targets     = @([pscustomobject]@{ path = (Join-Path $root '.codex\skills') })
                mcp_targets = @()
                mcp_servers = @([pscustomobject]@{ name = 'github'; transport = 'stdio'; command = 'fixture-command' })
            }
            Mock Load-McpPlanConfigReadOnly { [pscustomobject]@{ cfg = $cfg; raw = '{}' } }
            # 调用方作用域 DryRun=$false：fa5aeeb2 的 -not $DryRun 守卫未覆盖 plan 入口。
            & { $DryRun = $false; Get-McpSyncPlanningContext -ReadOnlyConfig | Out-Null }
            [string]$env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN | Should -Be ""
        }
        finally {
            if ($oldCodex) { $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldCodex } else { Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue }
            if ($oldGithub) { $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldGithub } else { Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue }
            $CfgPath = $oldCfgPath
            $script:Root = $oldRoot
        }
    }

    It 'uses the ZCode native config shape and does not create an undocumented sidecar' {
        $root = Join-Path $TestDrive 'zcode-root'
        $zcode = Join-Path $root '.zcode'
        $server = New-TestMcpServer 'zcode-fixture'
        $specs = @(Get-McpSyncManagedTargetSpecs -Roots @($zcode) -RepoRoot $root)
        $desired = @(New-McpSyncDesiredState -Specs $specs -Servers @($server) -ActiveServers @($server))

        @($specs.kind) | Should -Be @('zcode_json')
        $desired[0].path | Should -Be (Join-Path $zcode 'config.json')
        $payload = $desired[0].desired_content | ConvertFrom-Json
        $payload.mcp.servers.'zcode-fixture'.command | Should -Be 'fixture-command'
        $payload.mcp.servers.'zcode-fixture'.args[0] | Should -Be '--token'
        $payload.PSObject.Properties.Name | Should -Not -Contain 'mcpServers'
    }

    It 'chooses cli/config.json for the documented ZCode user root' {
        $userRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.zcode'
        (Get-ZCodeMcpConfigPath $userRoot) | Should -Be (Join-Path $userRoot 'cli\config.json')
    }

    It 'produces stable targets actions ids and hashes across repeated plans' {
        $desired = New-TestDesiredState (Join-Path $TestDrive 'stable')
        $first = New-McpSyncOperationPlanResult -DesiredState $desired -CreatedAt $createdAt -SourceRevision $sourceRevision
        $second = New-McpSyncOperationPlanResult -DesiredState @($desired | Sort-Object target_ref -Descending) -CreatedAt $createdAt -SourceRevision $sourceRevision

        ($first | ConvertTo-Json -Depth 50 -Compress) | Should -Be ($second | ConvertTo-Json -Depth 50 -Compress)
        (Test-OperationPlanContract $first.operation_plan).pass | Should -Be $true
        @($first.operation_plan.targets).Count | Should -Be @($desired).Count
        @($first.operation_plan.actions).Count | Should -Be @($desired).Count
    }

    It 'reports changed and unchanged targets without exposing desired content or secrets' {
        $root = Join-Path $TestDrive 'summary'
        $changed = @(New-TestDesiredState $root)
        $unchanged = @(New-TestDesiredState $root $true)
        $mixed = @($changed[0], $unchanged[1])
        $result = New-McpSyncOperationPlanResult -DesiredState $mixed -CreatedAt $createdAt -SourceRevision $sourceRevision
        $json = $result | ConvertTo-Json -Depth 50 -Compress

        $result.summary.changed_target_count | Should -Be 1
        $result.summary.unchanged_target_count | Should -Be 1
        @($result.operation_plan.actions).Count | Should -Be 1
        $result.summary.native_mutation_planned | Should -Be $false
        $result.summary.profile_changed | Should -Be $false
        foreach ($secret in @('FIXTURE_ARG_TOKEN', 'FIXTURE_ENV_TOKEN', 'API_TOKEN', 'desired_content')) {
            $json | Should -Not -Match ([regex]::Escape($secret))
        }
    }

    It 'keeps plan target refs and paths identical to the desired state consumed by apply' {
        $desired = @(New-TestDesiredState (Join-Path $TestDrive 'parity'))
        $result = New-McpSyncOperationPlanResult -DesiredState $desired -CreatedAt $createdAt -SourceRevision $sourceRevision

        (@($result.operation_plan.targets.target_ref | Sort-Object) -join ',') | Should -Be (@($desired.target_ref | Sort-Object) -join ',')
        (@($result.operation_plan.targets.path | Sort-Object) -join ',') | Should -Be (@($desired.path | Sort-Object) -join ',')
    }

    It 'does not write managed targets or invoke native mutation in plan mode' {
        $root = Join-Path $TestDrive 'zero-write'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $targetPath = Join-Path $root '.codex\config.toml'
        $desired = @(New-TestDesiredState $root)
        $beforeCfgHash = (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash
        Mock Get-McpSyncPlanningContext { [pscustomobject]@{ desired_state = $desired; config_revision = $sourceRevision } }
        Mock Invoke-NativeMcpSync {}
        Mock Invoke-NativeMcpCleanup {}

        $json = Invoke-McpSyncPlan -Json | ConvertFrom-Json

        $json.kind | Should -Be 'mcp_sync_plan'
        (Test-Path -LiteralPath $targetPath) | Should -Be $false
        (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash | Should -Be $beforeCfgHash
        Should -Invoke Invoke-NativeMcpSync -Times 0 -Exactly
        Should -Invoke Invoke-NativeMcpCleanup -Times 0 -Exactly
    }

    It 'writes only the explicitly requested plan output file' {
        $root = Join-Path $TestDrive 'out'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $desired = @(New-TestDesiredState $root)
        $outPath = Join-Path $root 'evidence\mcp-plan.json'
        Mock Get-McpSyncPlanningContext { [pscustomobject]@{ desired_state = $desired; config_revision = $sourceRevision } }

        Invoke-McpSyncPlan -Json -OutPath $outPath | Out-Null

        (Test-Path -LiteralPath $outPath -PathType Leaf) | Should -Be $true
        ((Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json).kind) | Should -Be 'mcp_sync_plan'
        foreach ($target in @($desired)) {
            (Test-Path -LiteralPath ([string]$target.path)) | Should -Be $false
        }
    }

    It 'keeps MCP planning behind the command interface without a standalone pass-through layer' {
        $source = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Commands\Mcp.ps1') -Raw
        $buildSource = Get-Content -LiteralPath (Join-Path $repoRoot 'build.ps1') -Raw

        $source | Should -Match 'function Get-McpSyncManagedTargetSpecs'
        $source | Should -Match 'function New-McpSyncDesiredState'
        $source | Should -Match 'function New-McpSyncOperationPlanResult'
        Test-Path -LiteralPath (Join-Path $repoRoot 'src\Application\McpPlanning.ps1') | Should -Be $false
        $buildSource | Should -Not -Match 'Application/McpPlanning\.ps1'
    }

    It 'parses MCP plan options without claiming global doctor JSON arguments' {
        $options = Parse-McpSyncPlanOptions @('--plan', '--json', '--out', '.\plan.json')
        $inline = Parse-McpSyncPlanOptions @('--out=.\inline.json')
        $empty = Parse-McpSyncPlanOptions (Merge-FilterAndArgs $null $null)
        $versionSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Version.ps1') -Raw

        $options.plan | Should -Be $true
        $options.json | Should -Be $true
        $options.out_path | Should -Be '.\plan.json'
        $inline.out_path | Should -Be '.\inline.json'
        $empty.plan | Should -Be $false
        $empty.json | Should -Be $false
        $empty.out_path | Should -Be ''
        $versionSource | Should -Not -Match '(?i)\[switch\]\$Json'
        $versionSource | Should -Not -Match '(?i)\[string\]\$Out'
    }
}

Describe 'MCP sync lock' {
    It 'Takes over a stale lock left by a hard-killed process' {
        $lockPath = Join-Path $TestDrive 'stale.skills-manager-mcp-sync.lock'
        Set-ContentUtf8 $lockPath 'stale'
        (Get-Item -LiteralPath $lockPath).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-20)

        $stream = Request-McpSyncLock $lockPath
        try {
            $stream | Should -Not -Be $null
            Test-Path -LiteralPath $lockPath -PathType Leaf | Should -BeTrue
        }
        finally { $stream.Dispose() }
    }

    It 'Fails closed against a fresh lock held by a possible concurrent sync' {
        $lockPath = Join-Path $TestDrive 'fresh.skills-manager-mcp-sync.lock'
        Set-ContentUtf8 $lockPath 'active'
        { Request-McpSyncLock $lockPath } | Should -Throw '*MCP 同步锁不可用*'
    }
}
