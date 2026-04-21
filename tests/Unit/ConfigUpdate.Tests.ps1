. $PSScriptRoot\..\..\skills.ps1

Describe "Config And Update Enhancements" {
    Context "Config Diff Summary" {
        It "Builds count diff lines for key arrays" {
            $oldRaw = @'
{
  "vendors": [{"name":"a","repo":"x"}],
  "targets": [{"path":"~/.codex/skills"}],
  "mappings": [],
  "imports": [],
  "mcp_servers": [],
  "mcp_targets": []
}
'@
            $newCfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "a"; repo = "x" }
                    [pscustomobject]@{ name = "b"; repo = "y" }
                )
                targets = @([pscustomobject]@{ path = "~/.codex/skills" })
                mappings = @([pscustomobject]@{ vendor = "a"; from = "."; to = "a-root" })
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $true
                sync_mode = "link"
            }

            $lines = Get-CfgChangeSummaryLines $oldRaw $newCfg
            ($lines -join "`n") | Should Match "vendors: 1 -> 2"
            ($lines -join "`n") | Should Match "mappings: 0 -> 1"
        }
    }

    Context "Vendor import normalization" {
        It "Canonicalizes vendor import names by repo without restoring deleted mappings" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "superpowers"; repo = "https://github.com/obra/superpowers.git"; ref = "main" }
                )
                targets = @()
                mappings = @()
                imports = @(
                    [pscustomobject]@{
                        name = "superpowers-writing-plans"
                        mode = "vendor"
                        repo = "https://github.com/obra/superpowers.git"
                        ref = "main"
                        skill = "skills\writing-plans"
                        sparse = $false
                    }
                )
                mcp_servers = @()
                mcp_targets = @()
                update_force = $true
                sync_mode = "link"
            }
            $changed = $false
            $dirMigrations = [ordered]@{
                vendors = @()
                imports = @()
            }

            Fix-Cfg $cfg ([ref]$changed) ([ref]$dirMigrations)

            $changed | Should Be $true
            @($cfg.imports).Count | Should Be 1
            $cfg.imports[0].name | Should Be "superpowers"
            @($cfg.mappings).Count | Should Be 0
        }

        It "Does not recreate mapping for previously removed vendor skill" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "anthropics-skills"; repo = "https://github.com/anthropics/skills.git"; ref = "main" }
                )
                targets = @()
                mappings = @()
                imports = @(
                    [pscustomobject]@{
                        name = "anthropics-skills"
                        mode = "vendor"
                        repo = "https://github.com/anthropics/skills.git"
                        ref = "main"
                        skill = "skills\theme-factory"
                        sparse = $false
                    }
                )
                mcp_servers = @()
                mcp_targets = @()
                update_force = $true
                sync_mode = "link"
            }
            $changed = $false
            $dirMigrations = [ordered]@{
                vendors = @()
                imports = @()
            }

            Fix-Cfg $cfg ([ref]$changed) ([ref]$dirMigrations)

            @($cfg.imports).Count | Should Be 1
            $cfg.imports[0].skill | Should Be "skills\theme-factory"
            @($cfg.mappings).Count | Should Be 0
        }

        It "Prunes vendor root mapping and root import automatically" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "web-quality-skills"; repo = "https://github.com/addyosmani/web-quality-skills.git"; ref = "main" }
                )
                targets = @()
                mappings = @(
                    [pscustomobject]@{ vendor = "web-quality-skills"; from = "."; to = "web-quality-skills-web-quality-skills" }
                    [pscustomobject]@{ vendor = "web-quality-skills"; from = "skills\accessibility"; to = "web-quality-skills-skills-accessibility" }
                )
                imports = @(
                    [pscustomobject]@{
                        name = "web-quality-skills"
                        mode = "vendor"
                        repo = "https://github.com/addyosmani/web-quality-skills.git"
                        ref = "main"
                        skill = "."
                        sparse = $false
                    }
                    [pscustomobject]@{
                        name = "web-quality-skills"
                        mode = "vendor"
                        repo = "https://github.com/addyosmani/web-quality-skills.git"
                        ref = "main"
                        skill = "skills\accessibility"
                        sparse = $false
                    }
                )
                mcp_servers = @()
                mcp_targets = @()
                update_force = $true
                sync_mode = "link"
            }
            $changed = $false
            $dirMigrations = [ordered]@{
                vendors = @()
                imports = @()
            }

            Fix-Cfg $cfg ([ref]$changed) ([ref]$dirMigrations)

            $changed | Should Be $true
            (@($cfg.mappings | Where-Object { $_.from -eq "." })).Count | Should Be 0
            (@($cfg.mappings | Where-Object { $_.from -eq "skills\accessibility" })).Count | Should Be 1
            (@($cfg.imports | Where-Object { $_.mode -eq "vendor" -and $_.skill -eq "." })).Count | Should Be 0
            (@($cfg.imports | Where-Object { $_.mode -eq "vendor" -and $_.skill -eq "skills\accessibility" })).Count | Should Be 1
        }
    }

    Context "Fine-Grained update_force" {
        It "Matches git dirty check only when candidate path is repo top-level" {
            $candidate = Join-Path $TestDrive "repo-root-check"
            New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            Mock Invoke-GitCapture {
                param($GitArgs)
                if ($GitArgs[0] -eq "rev-parse" -and $GitArgs[1] -eq "--show-toplevel") {
                    return (Join-Path $candidate "parent")
                }
                return $null
            }

            $isRepoRoot = Test-IsGitRepoRoot $candidate
            $isRepoRoot | Should Be $false
        }

        It "Skips non-git manual import caches in update_force dirty detection" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports"
                $cache = Join-Path $script:ImportDir "openpyxl"
                New-Item -ItemType Directory -Path $cache -Force | Out-Null

                $cfg = [pscustomobject]@{
                    update_force = $true
                    vendors = @()
                    imports = @(
                        [pscustomobject]@{
                            name = "openpyxl"
                            mode = "manual"
                        }
                    )
                }
                Mock Test-IsGitRepoRoot { $false } -ParameterFilter { $path -eq $cache }
                Mock Has-GitChanges { throw "Has-GitChanges should not be called for non-git caches." }

                $skip = @{}
                $ok = Confirm-UpdateForce $cfg ([ref]$skip)

                $ok | Should Be $true
                $skip.Count | Should Be 0
                Assert-MockCalled Has-GitChanges -Times 0 -Exactly
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }

        It "Records skip key when target-level force clean is denied" {
            $cfg = [pscustomobject]@{
                update_force = $true
            }
            $skip = @{}
            Mock Get-DirtyUpdateTargets {
                @([pscustomobject]@{ kind = "vendor"; name = "demo"; path = "x:\demo" })
            }

            $script:confirmCall = 0
            Mock Confirm-Action {
                $script:confirmCall++
                if ($script:confirmCall -eq 1) { return $true }
                return $false
            }

            $ok = Confirm-UpdateForce $cfg ([ref]$skip)
            $ok | Should Be $true
            $skip.ContainsKey("vendor|demo") | Should Be $true
        }

        It "Skips hard reset for vendor entries listed in skip map" {
            $oldVendorDir = $script:VendorDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor"
                New-Item -ItemType Directory -Path (Join-Path $script:VendorDir "demo") -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "demo"; ref = "main" })
                    imports = @()
                    mappings = @()
                    update_force = $true
                }
                $skip = @{ "vendor|demo" = $true }

                $script:cleanCalls = New-Object System.Collections.Generic.List[object]
                Mock Git-HardResetClean { param($forceClean) $script:cleanCalls.Add($forceClean) | Out-Null }
                Mock Invoke-Git {}
                Mock Has-GitUpstream { $false }
                Mock Get-GitHeadBranch { "main" }

                更新Vendor $cfg -SkipPreflight -SkipForceClean $skip | Out-Null
                $script:cleanCalls.Count | Should Be 1
                [bool]$script:cleanCalls[0] | Should Be $false
            }
            finally {
                $script:VendorDir = $oldVendorDir
            }
        }
    }

    Context "Update Plan/Upgrade" {
        It "Runs plan mode without mutating workspace" {
            $oldPlan = $script:Plan
            $oldLocked = $script:Locked
            $oldUpgrade = $script:Upgrade
            try {
                $script:Plan = $true
                $script:Locked = $false
                $script:Upgrade = $false
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
                Mock Show-UpdatePlan {}
                Mock Confirm-UpdateForce { $true }
                Mock 更新Imports { @() }
                Mock 更新Vendor { @() }
                Mock 构建生效 {}
                更新
                Assert-MockCalled Show-UpdatePlan -Times 1 -Exactly
                Assert-MockCalled 更新Imports -Times 0 -Exactly
                Assert-MockCalled 更新Vendor -Times 0 -Exactly
                Assert-MockCalled 构建生效 -Times 0 -Exactly
            }
            finally {
                $script:Plan = $oldPlan
                $script:Locked = $oldLocked
                $script:Upgrade = $oldUpgrade
            }
        }

        It "Refreshes lock file after successful upgrade" {
            $oldPlan = $script:Plan
            $oldLocked = $script:Locked
            $oldUpgrade = $script:Upgrade
            try {
                $script:Plan = $false
                $script:Locked = $false
                $script:Upgrade = $true
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
                Mock Confirm-UpdateForce { $true }
                Mock 更新Imports { @() }
                Mock 更新Vendor { @() }
                Mock 构建生效 {}
                Mock Save-LockData {}
                更新
                Assert-MockCalled Save-LockData -Times 1 -Exactly
            }
            finally {
                $script:Plan = $oldPlan
                $script:Locked = $oldLocked
                $script:Upgrade = $oldUpgrade
            }
        }
    }

    Context "Import path auto-repair" {
        It "Rewrites outdated manual import skill path to resolved candidate during update" {
            $oldImportDir = $script:ImportDir
            $oldCfgPath = $script:CfgPath
            try {
                $script:ImportDir = Join-Path $TestDrive "imports"
                $script:CfgPath = Join-Path $TestDrive "skills.json"
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null
                Set-Content -Path $script:CfgPath -Value '{"imports":[]}'

                $cache = Join-Path $script:ImportDir "storyboard-creation"
                $actual = Join-Path $cache "guides\video\storyboard-creation"
                New-Item -ItemType Directory -Path $actual -Force | Out-Null
                Set-Content -Path (Join-Path $actual "SKILL.md") -Value "---`nname: storyboard-creation`ndescription: x`n---"

                $cfg = [pscustomobject]@{
                    imports = @(
                        [pscustomobject]@{
                            name = "storyboard-creation"
                            mode = "manual"
                            repo = "https://github.com/inference-sh-6/skills.git"
                            ref = "main"
                            skill = "skills\storyboard-creation"
                            sparse = $false
                        }
                    )
                }

                Mock Preflight {}
                Mock Optimize-Imports {}
                Mock Ensure-Repo {}

                更新Imports $cfg -SkipPreflight | Out-Null

                $cfg.imports[0].skill | Should Be "guides\video\storyboard-creation"
            }
            finally {
                $script:ImportDir = $oldImportDir
                $script:CfgPath = $oldCfgPath
            }
        }

        It "Passes SkipFetch into Ensure-Repo doFetch parameter without shifting confirmClean" {
            $cfg = [pscustomobject]@{
                imports = @(
                    [pscustomobject]@{
                        name = "social-content"
                        mode = "manual"
                        repo = "https://github.com/example/social-content.git"
                        ref = "main"
                        skill = "."
                        sparse = $false
                    }
                )
            }

            Mock Preflight {}
            Mock Optimize-Imports {}
            Mock Test-IsSkillDir { $true }
            $script:ensureRepoArgs = $null
            Mock Ensure-Repo {
                param($path, $repo, $ref, $sparsePath, $forceClean, $confirmClean, $doFetch)
                $script:ensureRepoArgs = [pscustomobject]@{
                    path = $path
                    repo = $repo
                    ref = $ref
                    sparsePath = $sparsePath
                    forceClean = $forceClean
                    confirmClean = $confirmClean
                    doFetch = $doFetch
                }
            }

            更新Imports $cfg -SkipPreflight -SkipFetch | Out-Null

            $script:ensureRepoArgs | Should Not BeNullOrEmpty
            $script:ensureRepoArgs.path | Should Match "social-content$"
            $script:ensureRepoArgs.repo | Should Be "https://github.com/example/social-content.git"
            $script:ensureRepoArgs.ref | Should Be "main"
            ([string]::IsNullOrWhiteSpace([string]$script:ensureRepoArgs.sparsePath)) | Should Be $true
            $script:ensureRepoArgs.forceClean | Should Be $false
            $script:ensureRepoArgs.confirmClean | Should Be $false
            $script:ensureRepoArgs.doFetch | Should Be $false
        }

        It "Falls back to sparse checkout when Windows invalid path blocks pull" {
            $cfg = [pscustomobject]@{
                imports = @(
                    [pscustomobject]@{
                        name = "openpyxl"
                        mode = "manual"
                        repo = "https://github.com/example/workspace-hub.git"
                        ref = "main"
                        skill = ".claude\skills\data\office\openpyxl"
                        sparse = $false
                    }
                )
            }

            Mock Preflight {}
            Mock Optimize-Imports {}
            Mock Test-IsSkillDir { $true }
            Mock SaveCfgSafe {}

            $script:ensureRepoCalls = New-Object System.Collections.Generic.List[object]
            Mock Ensure-Repo {
                param($path, $repo, $ref, $sparsePath, $forceClean, $confirmClean, $doFetch)
                $script:ensureRepoCalls.Add([pscustomobject]@{
                        path = $path
                        repo = $repo
                        ref = $ref
                        sparsePath = $sparsePath
                        forceClean = $forceClean
                        confirmClean = $confirmClean
                        doFetch = $doFetch
                    }) | Out-Null
                if ($script:ensureRepoCalls.Count -eq 1) {
                    throw "git 失败：git pull；详情：error: invalid path '**Status:**' | Updating aaa..bbb"
                }
            }

            $failures = 更新Imports $cfg -SkipPreflight -SkipFetch

            @($failures).Count | Should Be 0
            $script:ensureRepoCalls.Count | Should Be 2
            ([string]::IsNullOrWhiteSpace([string]$script:ensureRepoCalls[0].sparsePath)) | Should Be $true
            $script:ensureRepoCalls[1].sparsePath | Should Be ".claude/skills/data/office/openpyxl"
            $cfg.imports[0].sparse | Should Be $true
            Assert-MockCalled SaveCfgSafe -Times 1 -Exactly
        }

        It "Falls back to git archive when sparse checkout still fails on invalid path repos" {
            $cfg = [pscustomobject]@{
                imports = @(
                    [pscustomobject]@{
                        name = "python-docx"
                        mode = "manual"
                        repo = "https://github.com/example/workspace-hub.git"
                        ref = "main"
                        skill = ".claude\skills\data\office\python-docx"
                        sparse = $false
                    }
                )
            }

            Mock Preflight {}
            Mock Optimize-Imports {}
            Mock Test-IsSkillDir { $true }
            Mock SaveCfgSafe {}
            Mock Ensure-Repo {
                throw "git 失败：git pull；详情：error: invalid path '**Status:**' | Updating aaa..bbb"
            }
            Mock Ensure-RepoFromGitArchive {}
            Mock Ensure-RepoFromGitHubTreeSnapshot {}

            $failures = 更新Imports $cfg -SkipPreflight -SkipFetch

            @($failures).Count | Should Be 0
            Assert-MockCalled Ensure-RepoFromGitArchive -Times 1 -Exactly
            Assert-MockCalled Ensure-RepoFromGitHubTreeSnapshot -Times 0 -Exactly
        }

        It "Falls back to existing cached import when git index lock blocks update" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports-lock"
                $cache = Join-Path $script:ImportDir "social-content"
                $gitDir = Join-Path $cache ".git"
                New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
                Set-Content -Path (Join-Path $gitDir "index.lock") -Value "stale"
                Set-Content -Path (Join-Path $cache "SKILL.md") -Value "---`nname: social-content`ndescription: x`n---"

                $cfg = [pscustomobject]@{
                    imports = @(
                        [pscustomobject]@{
                            name = "social-content"
                            mode = "manual"
                            repo = "https://github.com/example/social-content.git"
                            ref = "main"
                            skill = "."
                            sparse = $false
                        }
                    )
                }

                Mock Preflight {}
                Mock Optimize-Imports {}
                Mock Ensure-Repo { throw "git 失败：git reset --hard；详情：fatal: Could not write new index file." }

                $failures = 更新Imports $cfg -SkipPreflight -SkipFetch

                @($failures).Count | Should Be 0
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }
    }
}
