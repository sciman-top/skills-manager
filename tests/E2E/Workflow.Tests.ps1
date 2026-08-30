BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')

    $script:originalWorkspaceState = @{}
    foreach ($name in @('Root', 'CfgPath', 'LogPath', 'VendorDir', 'AgentDir', 'OverridesDir', 'ManualDir', 'ImportDir', 'DryRun')) {
        $script:originalWorkspaceState[$name] = Get-Variable -Name $name -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    }

    function Set-TestWorkspace([string]$root) {
        $values = @{
            Root = $root
            CfgPath = Join-Path $root "skills.json"
            LogPath = Join-Path $root "build.log"
            VendorDir = Join-Path $root "vendor"
            AgentDir = Join-Path $root "agent"
            OverridesDir = Join-Path $root "overrides"
            ManualDir = Join-Path $root "manual"
            ImportDir = Join-Path $root "imports"
            DryRun = $false
        }
        foreach ($entry in $values.GetEnumerator()) {
            Set-Variable -Name $entry.Key -Scope 1 -Value $entry.Value
            Set-Variable -Name $entry.Key -Scope Script -Value $entry.Value
            Set-Variable -Name $entry.Key -Scope Global -Value $entry.Value
        }
        EnsureDir $VendorDir
        EnsureDir $AgentDir
        EnsureDir $OverridesDir
        EnsureDir $ManualDir
        EnsureDir $ImportDir
    }

}
AfterAll {
    foreach ($entry in $script:originalWorkspaceState.GetEnumerator()) {
        Set-Variable -Name $entry.Key -Scope Global -Value $entry.Value
        Set-Variable -Name $entry.Key -Scope Script -Value $entry.Value
    }
}
Describe "E2E Workflows" {
    Context "CLI process contract" {
        It "Clears stale native exit state after a successful command" {
            $entry = (Join-Path $repoRoot "skills.ps1").Replace("'", "''")
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command "`$global:LASTEXITCODE = 128; & '$entry' help; exit `$LASTEXITCODE" 2>&1)

            $LASTEXITCODE | Should -Be 0
            ($output -join "`n") | Should -Match "skills\.ps1"
        }

        It "Returns a non-zero exit code when add fails instead of reporting success" {
            # 密封：把自包含 bundle 复制到临时 fixture，子进程的 $Root 解析到 fixture
            # 目录，绝不触碰仓库 skills.json；断言 fixture 配置字节不变。
            $fixture = Join-Path $TestDrive ("cli-add-fixture-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $repoRoot "skills.ps1") -Destination (Join-Path $fixture "skills.ps1")
            # bundle 内含按 src\ 相对路径解析的懒加载守卫，fixture 必须带 src 树，
            # 否则守卫降级会改变失败路径的行为。
            Copy-Item -Path (Join-Path $repoRoot "src") -Destination (Join-Path $fixture "src") -Recurse
            Set-ContentUtf8 (Join-Path $fixture "skills.json") @'
{
  "schema_version": 3,
  "vendors": [],
  "targets": [],
  "mappings": [],
  "imports": [],
  "mcp_servers": [],
  "mcp_targets": [],
  "sync_mode": "link",
  "update_force": true
}
'@
            $fixtureCfg = Join-Path $fixture "skills.json"
            $before = [IO.File]::ReadAllBytes($fixtureCfg)
            # invalid.invalid 为 RFC 保留 TLD，DNS 必然 NXDOMAIN：
            # 走 Add-ImportFromArgs 的 catch -> return $false 路径（非解析抛错路径）。
            $entry = (Join-Path $fixture "skills.ps1").Replace("'", "''")
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command "& '$entry' add 'https://invalid.invalid/demo.git'; exit `$LASTEXITCODE" 2>&1)
            $LASTEXITCODE | Should -Be 1
            $after = [IO.File]::ReadAllBytes($fixtureCfg)
            ([BitConverter]::ToString($before)) | Should -Be ([BitConverter]::ToString($after))
        }
    }

    Context "构建生效 + 同步" {
        It "Builds agent and syncs to target in sync mode" {
            $root = Join-Path $TestDrive "ws-build"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $skillDir = Join-Path $VendorDir "demo\skills\hello"
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            Set-Content -Path (Join-Path $skillDir "SKILL.md") -Value @'
---
name: hello
description: demo skill
---
'@

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main" })
                targets = @([pscustomobject]@{ path = (Join-Path $root "out\skills") })
                mappings = @([pscustomobject]@{ vendor = "demo"; from = "skills\hello"; to = "demo-hello" })
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }
            SaveCfg $cfg

            构建生效

            (Test-Path (Join-Path $AgentDir "demo-hello\SKILL.md")) | Should -Be $true
            (Test-Path (Join-Path $root "out\skills\demo-hello\SKILL.md")) | Should -Be $true
        }

        It "Builds agent without writing host targets when projection is explicitly skipped" {
            $root = Join-Path $TestDrive "ws-build-without-host-projection"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $skillDir = Join-Path $VendorDir "demo\skills\hello"
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            Set-Content -Path (Join-Path $skillDir "SKILL.md") -Value @'
---
name: hello
description: demo skill
---
'@

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main" })
                targets = @([pscustomobject]@{ path = (Join-Path $root "out\skills") })
                mappings = @([pscustomobject]@{ vendor = "demo"; from = "skills\hello"; to = "demo-hello" })
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
                skill_projection = [pscustomobject]@{
                    managed_source_path = "agent"
                    sources = @()
                    discovery_catalog = [pscustomobject]@{ catalog_path = "agent/.skills-manager/catalog.json" }
                }
            }
            SaveCfg $cfg
            $closureDir = Join-Path $root 'config'
            New-Item -ItemType Directory -Path $closureDir -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $repoRoot 'config\skill-dependency-closure.json') -Destination (Join-Path $closureDir 'skill-dependency-closure.json')

            构建生效 -SkipHostProjection

            (Test-Path (Join-Path $AgentDir "demo-hello\SKILL.md")) | Should -Be $true
            $catalogPath = Join-Path $AgentDir ".skills-manager\catalog.json"
            (Test-Path -LiteralPath $catalogPath -PathType Leaf) | Should -Be $true
            @((Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json).skills.name) | Should -Contain "hello"
            (Test-Path (Join-Path $root "out\skills")) | Should -Be $false
        }

        It "does not inspect incomplete agent staging for native projection during dry-run" {
            $oldDryRun = $DryRun
            try {
                $DryRun = $true
                $cfg = [pscustomobject]@{
                    targets = @()
                    sync_mode = "link"
                }

                Mock Sync-ConfiguredSkillProjection { throw "must not run against dry-run staging" }

                $failures = @(应用到ClaudeCodex $cfg -SkipPreflight)

                $failures.Count | Should -Be 0
                Should -Invoke Sync-ConfiguredSkillProjection -Times 0 -Exactly
            }
            finally {
                $DryRun = $oldDryRun
            }
        }

        It "Migrates the Claude whole-root link to the managed skill allowlist" {
            $root = Join-Path $TestDrive "ws-managed-link-target"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root
            foreach ($name in @('resident-a', 'resident-b', 'cold-skill')) {
                $skillRoot = Join-Path $AgentDir $name
                New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value "---`nname: $name`ndescription: test skill`n---`n"
            }
            $target = Join-Path $root 'claude-skills'
            New-Item -ItemType Junction -Path $target -Target $AgentDir | Out-Null
            $receiptPath = Join-Path $repoRoot ("reports\skill-projection\test-claude-{0}.json" -f [guid]::NewGuid().ToString('N'))
            $receiptRelative = [IO.Path]::GetRelativePath($repoRoot, $receiptPath)
            $cfg = [pscustomobject]@{
                targets = @([pscustomobject]@{ path = $target; host = 'claude'; managed_link_only = $true; receipt_path = $receiptRelative })
                sync_mode = 'link'
                skill_projection = [pscustomobject]@{
                    managed_link_includes = @('resident-a', 'resident-b')
                    managed_link_excludes = @()
                }
            }
            try {
                Mock Sync-ConfiguredSkillProjection { [pscustomobject]@{ skipped = $true } }

                $failures = @(应用到ClaudeCodex $cfg -SkipPreflight)

                $failures.Count | Should -Be 0
                [bool]((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) | Should -BeFalse
                foreach ($name in @('resident-a', 'resident-b')) {
                    $projected = Join-Path $target $name
                    Test-Path -LiteralPath (Join-Path $projected 'SKILL.md') | Should -BeTrue
                    [bool]((Get-Item -LiteralPath $projected -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) | Should -BeTrue
                }
                Test-Path -LiteralPath (Join-Path $target 'cold-skill') | Should -BeFalse
                Should -Invoke Sync-ConfiguredSkillProjection -Times 1 -Exactly
            }
            finally {
                if (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath -Force }
            }
        }

        It "Does not migrate a managed-link-only target during dry-run" {
            $root = Join-Path $TestDrive "ws-managed-link-dry-run"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root
            $skillRoot = Join-Path $AgentDir 'resident'
            New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value "---`nname: resident`ndescription: test skill`n---`n"
            $target = Join-Path $root 'claude-skills'
            New-Item -ItemType Junction -Path $target -Target $AgentDir | Out-Null
            $cfg = [pscustomobject]@{
                targets = @([pscustomobject]@{ path = $target; host = 'claude'; managed_link_only = $true; receipt_path = 'reports/skill-projection/dry-run.json' })
                sync_mode = 'link'
                skill_projection = [pscustomobject]@{ managed_link_includes = @('resident'); managed_link_excludes = @() }
            }
            $oldDryRun = $DryRun
            try {
                $DryRun = $true

                $failures = @(应用到ClaudeCodex $cfg -SkipPreflight)

                $failures.Count | Should -Be 0
                [bool]((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) | Should -BeTrue
                (Get-NativeSkillProjectionLinkTarget $target) | Should -Be ([IO.Path]::GetFullPath($AgentDir).TrimEnd('\', '/'))
            }
            finally { $DryRun = $oldDryRun }
        }

        It "does not require a clean-commit promotion context during build dry-run" {
            $oldDryRun = $DryRun
            try {
                $DryRun = $true
                $cfg = [pscustomobject]@{
                    vendors = @()
                    targets = @()
                    mappings = @()
                    imports = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "link"
                }

                Mock Preflight {}
                Mock LoadCfg { $cfg }
                Mock Optimize-Imports {}
                Mock Write-BuildSummary {}
                Mock Start-BuildTransaction { [pscustomobject]@{ path = ''; has_backup_agent = $false } }
                Mock Start-DryRunMirrorCollect {}
                Mock Stop-DryRunMirrorCollect {}
                Mock Write-DryRunMirrorSummary {}
                Mock 构建Agent { @() }
                Mock Get-HostProjectionPromotionContext { throw "must not require clean commit during dry-run" }
                Mock 应用到ClaudeCodex { @() }
                Mock Complete-BuildTransaction {}

                构建生效

                Should -Invoke Get-HostProjectionPromotionContext -Times 0 -Exactly
                Should -Invoke 应用到ClaudeCodex -Times 1 -Exactly
            }
            finally {
                $DryRun = $oldDryRun
            }
        }

        It "Fails closed and rolls back when agent build reports failures" {
            $root = Join-Path $TestDrive "ws-build-failure"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $cfg = [pscustomobject]@{
                vendors = @()
                targets = @([pscustomobject]@{ path = (Join-Path $root "out\skills") })
                mappings = @()
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }

            Mock Preflight {}
            Mock LoadCfg { $cfg }
            Mock Start-BuildTransaction { [pscustomobject]@{ path = (Join-Path $root ".txn\build-test"); has_backup_agent = $false } }
            Mock Optimize-Imports {}
            Mock Write-BuildSummary {}
            Mock Start-DryRunMirrorCollect {}
            Mock Stop-DryRunMirrorCollect {}
            Mock Write-DryRunMirrorSummary {}
            Mock 构建Agent { @("build-agent-reused-existing-dir => locked file") }
            Mock 应用到ClaudeCodex { @() }
            Mock Rollback-BuildTransaction {}
            Mock Complete-BuildTransaction {}

            $thrown = $false
            try {
                构建生效
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "构建生效失败"
            }

            $thrown | Should -Be $true
            Should -Invoke Rollback-BuildTransaction -Times 1 -Exactly
            Should -Invoke Complete-BuildTransaction -Times 0 -Exactly
            Should -Invoke 应用到ClaudeCodex -Times 0 -Exactly
        }
    }

    Context "更新流程" {
        It "Stops update when force confirmation is rejected" {
            $root = Join-Path $TestDrive "ws-update-cancel"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root
            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    targets = @()
                    mappings = @()
                    imports = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $true
                    sync_mode = "sync"
                }
            }
            Mock Confirm-UpdateForce { $false }
            Mock Preflight {}
            Mock 更新Imports { @() }
            Mock 更新Vendor { @() }
            Mock 构建生效 {}

            更新

            Should -Invoke 更新Imports -Times 0 -Exactly
            Should -Invoke 更新Vendor -Times 0 -Exactly
            Should -Invoke 构建生效 -Times 0 -Exactly
        }

        It "Applies lock snapshot directly when -Locked is enabled" {
            $oldLocked = $Locked
            $oldSkipHostProjection = $SkipHostProjection
            try {
                . (Join-Path $repoRoot 'skills.ps1') -Locked -SkipHostProjection
                Mock LoadCfg {
                    [pscustomobject]@{
                        vendors = @()
                        targets = @()
                        mappings = @()
                        imports = @()
                        mcp_servers = @()
                        mcp_targets = @()
                        update_force = $false
                        sync_mode = "sync"
                    }
                }
                Mock Load-LockData { [pscustomobject]@{ version = 1; vendors = @(); imports = @() } }
                Mock Assert-LockMatchesCfg {}
                Mock Apply-LockToWorkspace {}
                Mock Confirm-UpdateForce { $true }
                Mock 更新Imports { @() }
                Mock 更新Vendor { @() }
                Mock 构建生效 {}

                更新

                Should -Invoke Apply-LockToWorkspace -Times 1 -Exactly -Scope It
                Should -Invoke 构建生效 -Times 1 -Exactly -Scope It
                Should -Invoke 构建生效 -Times 1 -Exactly -Scope It -ParameterFilter { [bool]$SkipHostProjection }
                Should -Invoke 更新Imports -Times 0 -Exactly -Scope It
                Should -Invoke 更新Vendor -Times 0 -Exactly -Scope It
            }
            finally {
                $Locked = $oldLocked
                $SkipHostProjection = $oldSkipHostProjection
            }
        }
    }

    Context "MCP 同步" {
        It "Uses the same planned target paths for apply without planning writes" {
            $root = Join-Path $TestDrive "ws-mcp-plan-parity"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    targets = @(
                        [pscustomobject]@{ path = (Join-Path $root ".codex\skills") },
                        [pscustomobject]@{ path = (Join-Path $root ".trae\skills") }
                    )
                    mappings = @()
                    imports = @()
                    mcp_servers = @(
                        [pscustomobject]@{
                            name = "fetch"
                            transport = "stdio"
                            command = "python"
                            args = @("-m", "mcp_server_fetch")
                        }
                    )
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "sync"
                }
            }

            $context = Get-McpSyncPlanningContext
            $plan = New-McpSyncOperationPlanResult -DesiredState $context.desired_state -CreatedAt '2026-08-01T08:00:00Z' -SourceRevision ('f' * 64)
            $plannedPaths = @($plan.operation_plan.targets.path | Sort-Object)
            foreach ($path in $plannedPaths) { (Test-Path -LiteralPath $path) | Should -Be $false }

            同步MCP

            foreach ($path in $plannedPaths) { (Test-Path -LiteralPath $path -PathType Leaf) | Should -Be $true }
            (@($context.desired_state.path | Sort-Object) -join ',') | Should -Be ($plannedPaths -join ',')
        }

        It "Writes mcp files for codex and project trae when trae target exists" {
            $root = Join-Path $TestDrive "ws-mcp"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    targets = @(
                        [pscustomobject]@{ path = (Join-Path $root ".codex\skills") },
                        [pscustomobject]@{ path = (Join-Path $root ".trae\skills") }
                    )
                    mappings = @()
                    imports = @()
                    mcp_servers = @(
                        [pscustomobject]@{
                            name = "fetch"
                            transport = "stdio"
                            command = "python"
                            args = @("-m", "mcp_server_fetch")
                        }
                    )
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "sync"
                }
            }

            同步MCP

            $codexMcpPath = Join-Path $root ".codex\.mcp.json"
            (Test-Path $codexMcpPath) | Should -Be $true
            (Get-Content -Raw -Path $codexMcpPath) | Should -Match '"fetch"'
            (Test-Path (Join-Path $root ".codex\config.toml")) | Should -Be $true
            (Test-Path (Join-Path $root ".trae\mcp.json")) | Should -Be $true
        }

        It "Does not write project trae when trae target is absent" {
            $root = Join-Path $TestDrive "ws-mcp-no-trae"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    targets = @([pscustomobject]@{ path = (Join-Path $root ".codex\skills") })
                    mappings = @()
                    imports = @()
                    mcp_servers = @(
                        [pscustomobject]@{
                            name = "fetch"
                            transport = "stdio"
                            command = "python"
                            args = @("-m", "mcp_server_fetch")
                        }
                    )
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "sync"
                }
            }

            同步MCP

            (Test-Path (Join-Path $root ".codex\config.toml")) | Should -Be $true
            (Test-Path (Join-Path $root ".trae\mcp.json")) | Should -Be $false
        }
    }

    Context "Read-only CLI" {
        It "emits one capability inventory JSON envelope" {
            $fixtureBin = Join-Path $TestDrive 'codex-fixture-bin'
            New-Item -ItemType Directory -Path $fixtureBin -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $fixtureBin 'codex.cmd'), @'
@echo off
if /I "%~1"=="plugin" echo {"installed":[]}
if /I "%~1"=="mcp" echo []
if /I "%~1"=="doctor" echo {"schemaVersion":1,"codexVersion":"fixture","overallStatus":"ok","checks":[]}
exit /b 0
'@, [Text.UTF8Encoding]::new($false))
            $oldPath = $env:PATH
            try {
                $env:PATH = $fixtureBin + [IO.Path]::PathSeparator + $oldPath
                $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') capability-inventory --json 2>&1)
                $parsed = ($output -join "`n") | ConvertFrom-Json
            }
            finally {
                $env:PATH = $oldPath
            }

            @($output).Count | Should -Be 1
            $parsed.command | Should -Be 'capability-inventory'
            $parsed.data.writes | Should -Be 0
        }

        It "emits one rule audit JSON envelope without mutation" {
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-audit --repo $repoRoot --host codex --json 2>&1)
            $exitCode = $LASTEXITCODE
            $parsed = ($output -join "`n") | ConvertFrom-Json

            $exitCode | Should -Be 0
            @($output).Count | Should -Be 1
            $parsed.command | Should -Be 'rule-audit'
            $parsed.writes | Should -Be 0
            $parsed.provider_calls | Should -Be 0
            $parsed.native_mutations | Should -Be 0
        }
    }

    Context "Fixture-only rule patch CLI" {
        It "plans and applies through the generated entry point with one JSON envelope" {
            $root = Join-Path $TestDrive 'rule-cli-success'; New-Item -ItemType Directory -Path $root -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture')
            $target = Join-Path $root 'AGENTS.md'; $desired = Join-Path $root 'desired.md'; $plan = Join-Path $root 'plan.json'
            [IO.File]::WriteAllText($target, 'before'); [IO.File]::WriteAllText($desired, 'after')

            $planOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-plan --target $target --desired-file $desired --fixture-root $root --json --out $plan 2>&1)
            $planExit = $LASTEXITCODE; $planJson = ($planOutput -join "`n") | ConvertFrom-Json
            $applyOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-apply --plan $plan --fixture-root $root --token APPLY_RULE_PATCH --json 2>&1)
            $applyExit = $LASTEXITCODE; $applyJson = ($applyOutput -join "`n") | ConvertFrom-Json

            $planExit | Should -Be 0; @($planOutput).Count | Should -Be 1; $planJson.command | Should -Be 'rule-plan'
            $applyExit | Should -Be 0; @($applyOutput).Count | Should -Be 1; $applyJson.command | Should -Be 'rule-apply'
            $applyJson.result.receipt.verification.host_loaded | Should -Be 'not_run'
            [IO.File]::ReadAllText($target) | Should -Be 'after'
        }

        It "returns exit 2 and preserves the target when apply is blocked" {
            $root = Join-Path $TestDrive 'rule-cli-blocked'; New-Item -ItemType Directory -Path $root -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture')
            $target = Join-Path $root 'AGENTS.md'; $desired = Join-Path $root 'desired.md'; $plan = Join-Path $root 'plan.json'
            [IO.File]::WriteAllText($target, 'before'); [IO.File]::WriteAllText($desired, 'after')
            $null = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-plan --target $target --desired-file $desired --fixture-root $root --json --out $plan

            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-apply --plan $plan --fixture-root $root --token WRONG --json 2>&1)
            $exitCode = $LASTEXITCODE; $parsed = ($output -join "`n") | ConvertFrom-Json

            $exitCode | Should -Be 2; @($output).Count | Should -Be 1; $parsed.result.status | Should -Be 'blocked'
            [IO.File]::ReadAllText($target) | Should -Be 'before'
        }
    }

    Context "Rule estate reviewed multi-target CLI" {
        It "plans applies and rolls back through the generated entry point" {
            $workspace = Join-Path $TestDrive 'estate-cli-workspace'; $repo = Join-Path $workspace 'repo-a'; $repoB = Join-Path $workspace 'repo-b'; $reviewRoot = Join-Path $workspace 'review'
            $codex = Join-Path $TestDrive 'estate-cli-codex'; $claude = Join-Path $TestDrive 'estate-cli-claude'
            foreach ($path in @($repo,$repoB,$reviewRoot,$codex,$claude)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
            foreach ($targetRepo in @($repo,$repoB)) { git -C $targetRepo init --quiet; git -C $targetRepo config user.email fixture@example.invalid; git -C $targetRepo config user.name fixture }
            [IO.File]::WriteAllText((Join-Path $repo 'AGENTS.md'), '# repo before'); git -C $repo add AGENTS.md; git -C $repo commit -m init --quiet
            [IO.File]::WriteAllText((Join-Path $repoB 'AGENTS.md'), '# repo-b before'); git -C $repoB add AGENTS.md; git -C $repoB commit -m init --quiet
            [IO.File]::WriteAllText((Join-Path $codex 'AGENTS.md'), '# global before'); [IO.File]::WriteAllText((Join-Path $claude 'CLAUDE.md'), '# claude')
            [IO.File]::WriteAllText((Join-Path $reviewRoot 'repo.md'), '# repo after'); [IO.File]::WriteAllText((Join-Path $reviewRoot 'global.md'), '# repo-b after')
            $review = [pscustomobject]@{ schema_version=1; review_status='reviewed'; reviewed_by='fixture-owner'; reviewed_by_type='human'; authorization_source='user_supplied'; changes=@(
                [pscustomobject]@{target_scope='repository';repository='repo-a';target_file='AGENTS.md';desired_file='repo.md';allow_create=$false;risk='medium';evidence_refs=@('e2e')},
                [pscustomobject]@{target_scope='repository';repository='repo-b';target_file='AGENTS.md';desired_file='global.md';allow_create=$false;risk='medium';evidence_refs=@('e2e')}
            ) }
            $reviewPath=Join-Path $reviewRoot 'review.json';$review|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $reviewPath -Encoding UTF8
            $planPath=Join-Path $workspace 'plan.json';$receiptPath=Join-Path $workspace 'receipt.json'
            $rootArgs=@('--workspace-root',$workspace,'--codex-user-root',$codex,'--claude-user-root',$claude)

            $planOutput=@(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-estate-plan --review $reviewPath @rootArgs --out $planPath --json 2>&1);$planExit=$LASTEXITCODE;$planJson=($planOutput -join "`n")|ConvertFrom-Json
            $applyToken=[string]$planJson.plan.apply.required_token
            $applyOutput=@(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-estate-apply --plan $planPath @rootArgs --token $applyToken --out $receiptPath --json 2>&1);$applyExit=$LASTEXITCODE;$applyJson=($applyOutput -join "`n")|ConvertFrom-Json
            $repoAction=@($applyJson.result.receipt.actions|Where-Object target_scope -eq 'repository')[0]
            $rollbackOutput=@(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-estate-rollback --receipt $receiptPath --action-id $repoAction.action_id @rootArgs --token ROLLBACK_RULE_ESTATE_PATCH --json 2>&1);$rollbackExit=$LASTEXITCODE;$rollbackJson=($rollbackOutput -join "`n")|ConvertFrom-Json

            $planExit| Should -Be 0;@($planOutput).Count| Should -Be 1;$planJson.command| Should -Be 'rule-estate-plan'
            $applyExit| Should -Be 0;@($applyOutput).Count| Should -Be 1;$applyJson.command| Should -Be 'rule-estate-apply';$applyJson.result.writes| Should -Be 2
            $rollbackExit| Should -Be 0;@($rollbackOutput).Count| Should -Be 1;$rollbackJson.command| Should -Be 'rule-estate-rollback'
            [IO.File]::ReadAllText((Join-Path $repo 'AGENTS.md'))| Should -Be '# repo before'
            [IO.File]::ReadAllText((Join-Path $repoB 'AGENTS.md'))| Should -Be '# repo-b after'
            $applyJson.truth_boundary| Should -Be 'filesystem_applied_not_host_loaded'
        }
    }

    Context "异常场景" {
        It "Fails loading config when vendors field is missing" {
            $root = Join-Path $TestDrive "ws-invalid-config"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root
            Set-Content -Path $CfgPath -Value '{"targets":[],"mappings":[],"imports":[]}' -NoNewline

            $thrown = $false
            try { LoadCfg | Out-Null } catch { $thrown = $true }
            $thrown | Should -Be $true
        }

        It "Reports failure when target path is drive root" {
            $cfg = [pscustomobject]@{ targets = @([pscustomobject]@{ path = "C:\" }); sync_mode = "sync" }
            $failures = 应用到ClaudeCodex $cfg -SkipPreflight
            ($failures.Count -gt 0) | Should -Be $true
        }

        It "Collects vendor update failure when git command throws" {
            $root = Join-Path $TestDrive "ws-update-failure"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $vendorPath = Join-Path $VendorDir "demo"
            New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main" })
                imports = @()
                mappings = @()
                targets = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }

            Mock Invoke-Git { throw "mock git failure" } -ParameterFilter { $GitArgs[0] -eq "fetch" }
            Mock Invoke-Git {}
            Mock Has-GitUpstream { $false }
            Mock Get-GitHeadBranch { "main" }

            $failures = 更新Vendor $cfg -SkipPreflight
            ($failures.Count -gt 0) | Should -Be $true
        }
    }
}
