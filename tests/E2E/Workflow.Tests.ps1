$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'skills.ps1')

function Set-TestWorkspace([string]$root) {
    $script:Root = $root
    $script:CfgPath = Join-Path $root "skills.json"
    $script:LogPath = Join-Path $root "build.log"
    $script:VendorDir = Join-Path $root "vendor"
    $script:AgentDir = Join-Path $root "agent"
    $script:OverridesDir = Join-Path $root "overrides"
    $script:ManualDir = Join-Path $root "manual"
    $script:ImportDir = Join-Path $root "imports"
    $script:DryRun = $false
    $global:Root = $script:Root
    $global:CfgPath = $script:CfgPath
    $global:LogPath = $script:LogPath
    $global:VendorDir = $script:VendorDir
    $global:AgentDir = $script:AgentDir
    $global:OverridesDir = $script:OverridesDir
    $global:ManualDir = $script:ManualDir
    $global:ImportDir = $script:ImportDir
    $global:DryRun = $false
    EnsureDir $script:VendorDir
    EnsureDir $script:AgentDir
    EnsureDir $script:OverridesDir
    EnsureDir $script:ManualDir
    EnsureDir $script:ImportDir
}

Describe "E2E Workflows" {
    Context "CLI process contract" {
        It "Clears stale native exit state after a successful command" {
            $entry = (Join-Path $repoRoot "skills.ps1").Replace("'", "''")
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command "`$global:LASTEXITCODE = 128; & '$entry' help; exit `$LASTEXITCODE" 2>&1)

            $LASTEXITCODE | Should Be 0
            ($output -join "`n") | Should Match "skills\.ps1"
        }
    }

    Context "构建生效 + 同步" {
        It "Builds agent and syncs to target in sync mode" {
            $root = Join-Path $TestDrive "ws-build"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $skillDir = Join-Path $script:VendorDir "demo\skills\hello"
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

            (Test-Path (Join-Path $script:AgentDir "demo-hello\SKILL.md")) | Should Be $true
            (Test-Path (Join-Path $root "out\skills\demo-hello\SKILL.md")) | Should Be $true
        }

        It "Builds agent without writing host targets when projection is explicitly skipped" {
            $root = Join-Path $TestDrive "ws-build-without-host-projection"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $skillDir = Join-Path $script:VendorDir "demo\skills\hello"
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

            构建生效 -SkipHostProjection

            (Test-Path (Join-Path $script:AgentDir "demo-hello\SKILL.md")) | Should Be $true
            (Test-Path (Join-Path $root "out\skills")) | Should Be $false
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
            Mock Invoke-PrebuildCheck {}
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
                $_.Exception.Message | Should Match "构建生效失败"
            }

            $thrown | Should Be $true
            Assert-MockCalled Rollback-BuildTransaction -Times 1 -Exactly
            Assert-MockCalled Complete-BuildTransaction -Times 0 -Exactly
            Assert-MockCalled 应用到ClaudeCodex -Times 0 -Exactly
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

            Assert-MockCalled 更新Imports -Times 0 -Exactly
            Assert-MockCalled 更新Vendor -Times 0 -Exactly
            Assert-MockCalled 构建生效 -Times 0 -Exactly
        }

        It "Applies lock snapshot directly when -Locked is enabled" {
            $oldLocked = $script:Locked
            $oldSkipHostProjection = $script:SkipHostProjection
            try {
                $script:Locked = $true
                $script:SkipHostProjection = $true
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

                Assert-MockCalled Apply-LockToWorkspace -Times 1 -Exactly
                Assert-MockCalled 构建生效 -Times 1 -Exactly
                Assert-MockCalled 构建生效 -Times 1 -Exactly -ParameterFilter { [bool]$SkipHostProjection }
                Assert-MockCalled 更新Imports -Times 0 -Exactly
                Assert-MockCalled 更新Vendor -Times 0 -Exactly
            }
            finally {
                $script:Locked = $oldLocked
                $script:SkipHostProjection = $oldSkipHostProjection
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
            foreach ($path in $plannedPaths) { (Test-Path -LiteralPath $path) | Should Be $false }

            同步MCP

            foreach ($path in $plannedPaths) { (Test-Path -LiteralPath $path -PathType Leaf) | Should Be $true }
            (@($context.desired_state.path | Sort-Object) -join ',') | Should Be ($plannedPaths -join ',')
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
            (Test-Path $codexMcpPath) | Should Be $true
            (Get-Content -Raw -Path $codexMcpPath) | Should Match '"fetch"'
            (Test-Path (Join-Path $root ".codex\config.toml")) | Should Be $true
            (Test-Path (Join-Path $root ".trae\mcp.json")) | Should Be $true
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

            (Test-Path (Join-Path $root ".codex\config.toml")) | Should Be $true
            (Test-Path (Join-Path $root ".trae\mcp.json")) | Should Be $false
        }
    }

    Context "Phase 1 read-only CLI" {
        It "emits one capability inventory JSON envelope" {
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') capability-inventory --json 2>&1)
            $parsed = ($output -join "`n") | ConvertFrom-Json

            @($output).Count | Should Be 1
            $parsed.command | Should Be 'capability-inventory'
            $parsed.data.writes | Should Be 0
        }

        It "emits one rule audit JSON envelope without mutation" {
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-audit --repo $repoRoot --host codex --json 2>&1)
            $exitCode = $LASTEXITCODE
            $parsed = ($output -join "`n") | ConvertFrom-Json

            $exitCode | Should Be 0
            @($output).Count | Should Be 1
            $parsed.command | Should Be 'rule-audit'
            $parsed.writes | Should Be 0
            $parsed.provider_calls | Should Be 0
            $parsed.native_mutations | Should Be 0
        }
    }

    Context "Phase 2 fixture-only rule patch CLI" {
        It "plans and applies through the generated entry point with one JSON envelope" {
            $root = Join-Path $TestDrive 'rule-cli-success'; New-Item -ItemType Directory -Path $root -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture')
            $target = Join-Path $root 'AGENTS.md'; $desired = Join-Path $root 'desired.md'; $plan = Join-Path $root 'plan.json'
            [IO.File]::WriteAllText($target, 'before'); [IO.File]::WriteAllText($desired, 'after')

            $planOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-plan --target $target --desired-file $desired --fixture-root $root --json --out $plan 2>&1)
            $planExit = $LASTEXITCODE; $planJson = ($planOutput -join "`n") | ConvertFrom-Json
            $applyOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-apply --plan $plan --fixture-root $root --token APPLY_RULE_PATCH --json 2>&1)
            $applyExit = $LASTEXITCODE; $applyJson = ($applyOutput -join "`n") | ConvertFrom-Json

            $planExit | Should Be 0; @($planOutput).Count | Should Be 1; $planJson.command | Should Be 'rule-plan'
            $applyExit | Should Be 0; @($applyOutput).Count | Should Be 1; $applyJson.command | Should Be 'rule-apply'
            $applyJson.result.receipt.verification.host_loaded | Should Be 'not_run'
            [IO.File]::ReadAllText($target) | Should Be 'after'
        }

        It "returns exit 2 and preserves the target when apply is blocked" {
            $root = Join-Path $TestDrive 'rule-cli-blocked'; New-Item -ItemType Directory -Path $root -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture')
            $target = Join-Path $root 'AGENTS.md'; $desired = Join-Path $root 'desired.md'; $plan = Join-Path $root 'plan.json'
            [IO.File]::WriteAllText($target, 'before'); [IO.File]::WriteAllText($desired, 'after')
            $null = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-plan --target $target --desired-file $desired --fixture-root $root --json --out $plan

            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-apply --plan $plan --fixture-root $root --token WRONG --json 2>&1)
            $exitCode = $LASTEXITCODE; $parsed = ($output -join "`n") | ConvertFrom-Json

            $exitCode | Should Be 2; @($output).Count | Should Be 1; $parsed.result.status | Should Be 'blocked'
            [IO.File]::ReadAllText($target) | Should Be 'before'
        }
    }

    Context "Rule estate reviewed multi-target CLI" {
        It "plans applies and rolls back through the generated entry point" {
            $workspace = Join-Path $TestDrive 'estate-cli-workspace'; $repo = Join-Path $workspace 'repo-a'; $reviewRoot = Join-Path $workspace 'review'
            $codex = Join-Path $TestDrive 'estate-cli-codex'; $claude = Join-Path $TestDrive 'estate-cli-claude'
            foreach ($path in @($repo,$reviewRoot,$codex,$claude)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
            git -C $repo init --quiet; git -C $repo config user.email fixture@example.invalid; git -C $repo config user.name fixture
            [IO.File]::WriteAllText((Join-Path $repo 'AGENTS.md'), '# repo before'); git -C $repo add AGENTS.md; git -C $repo commit -m init --quiet
            [IO.File]::WriteAllText((Join-Path $codex 'AGENTS.md'), '# global before'); [IO.File]::WriteAllText((Join-Path $claude 'CLAUDE.md'), '# claude')
            [IO.File]::WriteAllText((Join-Path $reviewRoot 'repo.md'), '# repo after'); [IO.File]::WriteAllText((Join-Path $reviewRoot 'global.md'), '# global after')
            $review = [pscustomobject]@{ schema_version=1; review_status='reviewed'; reviewed_by='fixture-owner'; reviewed_by_type='human'; authorization_source='user_supplied'; changes=@(
                [pscustomobject]@{target_scope='repository';repository='repo-a';target_file='AGENTS.md';desired_file='repo.md';allow_create=$false;risk='medium';evidence_refs=@('e2e')},
                [pscustomobject]@{target_scope='global_codex';target_file='AGENTS.md';desired_file='global.md';allow_create=$false;risk='high';evidence_refs=@('e2e')}
            ) }
            $reviewPath=Join-Path $reviewRoot 'review.json';$authorizationPath=Join-Path $reviewRoot 'authorization.json';$review|Add-Member -NotePropertyName authorization_receipt -NotePropertyValue 'authorization.json';$review|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $reviewPath -Encoding UTF8
            $applyToken='APPLY_RULE_ESTATE_PATCH_'+[guid]::NewGuid().ToString('N').Substring(0,16).ToUpperInvariant()
            [pscustomobject][ordered]@{schema_version=1;domain='rule_estate_authorization';authorization_id=('rule-estate-auth-'+[guid]::NewGuid().ToString('N'));decision='approved';issued_by='fixture-owner';issued_by_type='human';authorization_source='user_supplied';issued_at=[datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o');expires_at=[datetimeoffset]::UtcNow.AddHours(1).ToString('o');review_sha256=Get-OperationSha256 ([IO.File]::ReadAllText($reviewPath));workspace_root=[IO.Path]::GetFullPath($workspace);codex_user_root=[IO.Path]::GetFullPath($codex);claude_user_root=[IO.Path]::GetFullPath($claude);approved_action_count=2;apply_token=$applyToken}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $authorizationPath -Encoding UTF8
            $planPath=Join-Path $workspace 'plan.json';$receiptPath=Join-Path $workspace 'receipt.json'
            $rootArgs=@('--workspace-root',$workspace,'--codex-user-root',$codex,'--claude-user-root',$claude)

            $planOutput=@(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-estate-plan --review $reviewPath @rootArgs --out $planPath --json 2>&1);$planExit=$LASTEXITCODE;$planJson=($planOutput -join "`n")|ConvertFrom-Json
            $applyOutput=@(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-estate-apply --plan $planPath @rootArgs --token $applyToken --out $receiptPath --json 2>&1);$applyExit=$LASTEXITCODE;$applyJson=($applyOutput -join "`n")|ConvertFrom-Json
            $repoAction=@($applyJson.result.receipt.actions|Where-Object target_scope -eq 'repository')[0]
            $rollbackOutput=@(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'skills.ps1') rule-estate-rollback --receipt $receiptPath --action-id $repoAction.action_id @rootArgs --token ROLLBACK_RULE_ESTATE_PATCH --json 2>&1);$rollbackExit=$LASTEXITCODE;$rollbackJson=($rollbackOutput -join "`n")|ConvertFrom-Json

            $planExit|Should Be 0;@($planOutput).Count|Should Be 1;$planJson.command|Should Be 'rule-estate-plan'
            $applyExit|Should Be 0;@($applyOutput).Count|Should Be 1;$applyJson.command|Should Be 'rule-estate-apply';$applyJson.result.writes|Should Be 2
            $rollbackExit|Should Be 0;@($rollbackOutput).Count|Should Be 1;$rollbackJson.command|Should Be 'rule-estate-rollback'
            [IO.File]::ReadAllText((Join-Path $repo 'AGENTS.md'))|Should Be '# repo before'
            [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md'))|Should Be '# global after'
            $applyJson.truth_boundary|Should Be 'filesystem_applied_not_host_loaded'
        }
    }

    Context "异常场景" {
        It "Fails loading config when vendors field is missing" {
            $root = Join-Path $TestDrive "ws-invalid-config"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root
            Set-Content -Path $script:CfgPath -Value '{"targets":[],"mappings":[],"imports":[]}' -NoNewline

            $thrown = $false
            try { LoadCfg | Out-Null } catch { $thrown = $true }
            $thrown | Should Be $true
        }

        It "Reports failure when target path is drive root" {
            $cfg = [pscustomobject]@{ targets = @([pscustomobject]@{ path = "C:\" }); sync_mode = "sync" }
            $failures = 应用到ClaudeCodex $cfg -SkipPreflight
            ($failures.Count -gt 0) | Should Be $true
        }

        It "Collects vendor update failure when git command throws" {
            $root = Join-Path $TestDrive "ws-update-failure"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $vendorPath = Join-Path $script:VendorDir "demo"
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
            ($failures.Count -gt 0) | Should Be $true
        }
    }
}
