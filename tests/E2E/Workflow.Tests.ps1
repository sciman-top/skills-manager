. $PSScriptRoot\..\..\skills.ps1

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
    Context "构建生效 + 同步" {
        It "Builds agent and syncs to target in sync mode" {
            $root = Join-Path $TestDrive "ws-build"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-TestWorkspace $root

            $skillDir = Join-Path $script:VendorDir "demo\skills\hello"
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            Set-Content -Path (Join-Path $skillDir "SKILL.md") -Value "# demo"

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
            try {
                $script:Locked = $true
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
                Assert-MockCalled 更新Imports -Times 0 -Exactly
                Assert-MockCalled 更新Vendor -Times 0 -Exactly
            }
            finally {
                $script:Locked = $oldLocked
            }
        }
    }

    Context "MCP 同步" {
        It "Writes mcp files for codex and project trae" {
            $root = Join-Path $TestDrive "ws-mcp"
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

            (Test-Path (Join-Path $root ".codex\.mcp.json")) | Should Be $true
            (Test-Path (Join-Path $root ".codex\config.toml")) | Should Be $true
            (Test-Path (Join-Path $root ".trae\mcp.json")) | Should Be $true
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
