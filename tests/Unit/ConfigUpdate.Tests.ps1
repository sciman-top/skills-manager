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

    Context "Config contract validation" {
        It "Collects contract errors without mutating config shape" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git" }
                )
                targets = @(
                    [pscustomobject]@{ path = "~/.codex/skills" }
                )
                mappings = @(
                    [pscustomobject]@{ vendor = "missing-vendor"; from = "..\escape"; to = "skill-x" }
                )
                imports = @()
                mcp_servers = @(
                    [pscustomobject]@{ name = "bad-server"; transport = "websocket" }
                )
                sync_mode = "invalid"
            }

            $errors = @(Get-CfgContractErrors $cfg)
            $joined = $errors -join "`n"

            $joined | Should Match "mapping.from 非法"
            $joined | Should Match "mcp_server.transport 仅支持 stdio/sse/http：bad-server"
            $joined | Should Match "sync_mode 仅支持 link 或 sync"
            $joined | Should Match "mapping 引用了不存在的 vendor：missing-vendor"
            $cfg.PSObject.Properties.Match("mcp_targets").Count | Should Be 0
        }

        It "Treats overrides as a reserved mapping vendor in config contracts" {
            $cfg = [pscustomobject]@{
                vendors = @()
                targets = @()
                mappings = @(
                    [pscustomobject]@{ vendor = "overrides"; from = "."; to = "custom-skill" }
                )
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                sync_mode = "link"
            }

            $errors = @(Get-CfgContractErrors $cfg)
            ($errors | Where-Object { $_ -like "*不存在的 vendor*" }).Count | Should Be 0
            { Assert-Cfg $cfg } | Should Not Throw
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

    Context "Update parallelism" {
        It "Uses auto parallelism based on unique repo count when config does not set update_parallelism" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "v1"; repo = "https://github.com/example/a.git" }
                )
                imports = @(
                    [pscustomobject]@{ name = "i1"; mode = "manual"; repo = "https://github.com/example/b.git" },
                    [pscustomobject]@{ name = "i2"; mode = "manual"; repo = "https://github.com/example/b.git" }
                )
            }

            Get-UpdateRepoCount $cfg | Should Be 2
            Get-UpdateParallelism $cfg | Should Be 2
        }

        It "Falls back to 1 when update_parallelism is invalid" {
            $cfg = [pscustomobject]@{
                update_parallelism = -3
                vendors = @()
                imports = @()
            }

            Get-UpdateParallelism $cfg | Should Be 1
        }

        It "Keeps explicit update_parallelism when valid" {
            $cfg = [pscustomobject]@{
                update_parallelism = 4
                vendors = @()
                imports = @()
            }

            Get-UpdateParallelism $cfg | Should Be 4
        }

        It "Clamps parallel prefetch timeout from environment" {
            $oldTimeout = $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS
            try {
                $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS = "1"
                Get-UpdatePrefetchTimeoutSeconds | Should Be 1

                $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS = "9999"
                Get-UpdatePrefetchTimeoutSeconds | Should Be 1800

                $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS = "45"
                Get-UpdatePrefetchTimeoutSeconds | Should Be 45
            }
            finally {
                $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS = $oldTimeout
            }
        }
    }

    Context "Update fast no-op" {
        It "Allows fast no-op only when every planned source is clean and unchanged" {
            $oldVendorDir = $script:VendorDir
            $oldImportDir = $script:ImportDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor-fast-noop"
                $script:ImportDir = Join-Path $TestDrive "imports-fast-noop"
                $vendorPath = Join-Path $script:VendorDir "demo-vendor"
                $importPath = Join-Path $script:ImportDir "demo-import"
                New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null
                New-Item -ItemType Directory -Path $importPath -Force | Out-Null
                Set-Content -Path (Join-Path $importPath "SKILL.md") -Value "---`nname: demo-import`ndescription: x`n---"

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "demo-vendor"; repo = "https://example.com/vendor.git"; ref = "main" })
                    imports = @([pscustomobject]@{ name = "demo-import"; mode = "manual"; repo = "https://example.com/import.git"; ref = "main"; skill = "." })
                }
                $items = @(
                    [pscustomobject]@{ type = "vendor"; name = "demo-vendor"; current = "abc"; target = "abc"; changed = $false },
                    [pscustomobject]@{ type = "import"; name = "demo-import"; current = "def"; target = "def"; changed = $false }
                )

                Mock Test-IsGitRepoRoot { $true } -ParameterFilter { $path -eq $vendorPath }
                Mock Test-IsGitRepoRoot { $false } -ParameterFilter { $path -eq $importPath }
                Mock Invoke-GitCapture { "" } -ParameterFilter { $GitArgs[0] -eq "status" }

                (Test-UpdateCanFastNoop $cfg $items) | Should Be $true
            }
            finally {
                $script:VendorDir = $oldVendorDir
                $script:ImportDir = $oldImportDir
            }
        }

        It "Rejects fast no-op when a git cache has local changes" {
            $oldVendorDir = $script:VendorDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor-fast-noop-dirty"
                $vendorPath = Join-Path $script:VendorDir "demo-vendor"
                New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "demo-vendor"; repo = "https://example.com/vendor.git"; ref = "main" })
                    imports = @()
                }
                $items = @([pscustomobject]@{ type = "vendor"; name = "demo-vendor"; current = "abc"; target = "abc"; changed = $false })

                Mock Test-IsGitRepoRoot { $true } -ParameterFilter { $path -eq $vendorPath }
                Mock Invoke-GitCapture { " M SKILL.md" } -ParameterFilter { $GitArgs[0] -eq "status" }

                (Test-UpdateCanFastNoop $cfg $items) | Should Be $false
            }
            finally {
                $script:VendorDir = $oldVendorDir
            }
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

        It "Skips non-git caches during parallel prefetch" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports-prefetch"
                $cache = Join-Path $script:ImportDir "openpyxl"
                New-Item -ItemType Directory -Path $cache -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @(
                        [pscustomobject]@{
                            name = "openpyxl"
                            mode = "manual"
                        }
                    )
                }

                Mock Test-IsGitRepoRoot { $false } -ParameterFilter { $path -eq $cache }
                Mock Start-Job { throw "Start-Job should not be called for non-git caches." }

                Invoke-ParallelGitPrefetch $cfg 2

                Assert-MockCalled Start-Job -Times 0 -Exactly
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }

        It "Stops and cleans up timed-out parallel prefetch jobs" {
            $oldVendorDir = $script:VendorDir
            $oldTimeout = $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS
            try {
                $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS = "1"
                $script:VendorDir = Join-Path $TestDrive "vendor-prefetch-timeout"
                $vendorPath = Join-Path $script:VendorDir "demo"
                New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git" })
                    imports = @()
                }
                $job = [pscustomobject]@{ Id = 42; Name = "prefetch-demo" }

                Mock Test-IsGitRepoRoot { $true } -ParameterFilter { $path -eq $vendorPath }
                Mock Start-Job { $job }
                Mock Wait-Job { $null }
                Mock Stop-Job {}
                Mock Remove-Job {}
                Mock Receive-Job { throw "Receive-Job should not be called for timed-out jobs." }

                Invoke-ParallelGitPrefetch $cfg 2 | Should Be $false

                Assert-MockCalled Stop-Job -Times 1 -Exactly -Scope It
                Assert-MockCalled Remove-Job -Times 1 -Exactly -Scope It
                Assert-MockCalled Receive-Job -Times 0 -Exactly -Scope It
            }
            finally {
                $script:VendorDir = $oldVendorDir
                $env:SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS = $oldTimeout
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
        It "Builds dereferenced tag candidates without format errors" {
            Mock Invoke-GitCapture { $null }

            $resolved = $null
            $thrown = $false
            try {
                $resolved = Resolve-RemoteCommit "https://github.com/example/demo.git" "v1"
            }
            catch {
                $thrown = $true
            }

            $thrown | Should Be $false
            $resolved | Should Be $null
        }

        It "Prefers exact branch refs over ambiguous ls-remote suffix matches" {
            Mock Invoke-GitCapture {
                param($GitArgs)
                $candidate = [string]$GitArgs[-1]
                if ($candidate -eq "refs/heads/main") {
                    return "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`trefs/heads/main"
                }
                if ($candidate -eq "main") {
                    return "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`trefs/heads/changeset-release/main`nbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`trefs/heads/main"
                }
                return $null
            }

            Resolve-RemoteCommit "https://github.com/example/ambiguous.git" "main" | Should Be "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            Assert-MockCalled Invoke-GitCapture -ParameterFilter { $GitArgs[-1] -eq "refs/heads/main" } -Times 1 -Exactly -Scope It
            Assert-MockCalled Invoke-GitCapture -ParameterFilter { $GitArgs[-1] -eq "main" } -Times 0 -Exactly -Scope It
        }

        It "Returns local zip hash for archive-based update sources" {
            $zip = Join-Path $TestDrive "plan-demo.zip"
            Set-Content -Path $zip -Value "zip-plan-data"

            $resolved = Resolve-RemoteCommit $zip "main"

            $resolved | Should Be ("zip:{0}" -f (Get-FileContentHash $zip))
        }

        It "Does not read parent repository HEAD for non-git import caches" {
            $cache = Join-Path $TestDrive "plain-import-cache"
            New-Item -ItemType Directory -Path $cache -Force | Out-Null

            Mock Test-IsGitRepoRoot { $false } -ParameterFilter { $path -eq $cache }
            Mock Invoke-GitCapture { throw "Invoke-GitCapture should not be called for a non-git cache." }

            Get-CurrentRepoCommit $cache | Should Be $null
            Assert-MockCalled Invoke-GitCapture -Times 0 -Exactly -Scope It
        }

        It "Reads source metadata for non-git import caches" {
            $cache = Join-Path $TestDrive "metadata-import-cache"
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            Write-ImportSourceMetadata $cache "https://github.com/example/workspace.git" "main" "abc123" "archive"

            Mock Test-IsGitRepoRoot { $false } -ParameterFilter { $path -eq $cache }

            Get-CurrentRepoCommit $cache | Should Be "abc123"
        }

        It "Caches repeated remote commit lookups for identical repo and ref" {
            $cache = @{}
            Mock Resolve-RemoteCommit { "abc123" }

            $first = Resolve-RemoteCommitCached "https://github.com/example/demo.git" "main" $cache
            $second = Resolve-RemoteCommitCached "https://github.com/example/demo.git" "main" $cache

            $first | Should Be "abc123"
            $second | Should Be "abc123"
            Assert-MockCalled Resolve-RemoteCommit -Times 1 -Exactly
        }

        It "Reuses cached remote target across repeated imports from the same repo" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports-plan-cache"
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null
                foreach ($name in @("skill-a", "skill-b")) {
                    $cachePath = Join-Path $script:ImportDir $name
                    New-Item -ItemType Directory -Path (Join-Path $cachePath ".git") -Force | Out-Null
                }

                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @(
                        [pscustomobject]@{ name = "skill-a"; mode = "manual"; repo = "https://github.com/example/shared.git"; ref = "main"; skill = "skills\\a" },
                        [pscustomobject]@{ name = "skill-b"; mode = "manual"; repo = "https://github.com/example/shared.git"; ref = "main"; skill = "skills\\b" }
                    )
                }

                Mock Get-CurrentRepoCommit { "current-sha" }
                Mock Resolve-RemoteCommit { "remote-sha" }

                $items = @(Get-UpdatePlanItems $cfg)

                $items.Count | Should Be 2
                ($items | Where-Object { $_.target -eq "remote-sha" }).Count | Should Be 2
                Assert-MockCalled Resolve-RemoteCommit -Times 1 -Exactly -Scope It
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }

        It "Uses local prefetched remote refs for plan targets when available" {
            $oldVendorDir = $script:VendorDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor-local-ref-plan"
                $vendorPath = Join-Path $script:VendorDir "demo"
                New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "demo"; repo = "https://github.com/example/demo.git"; ref = "main" })
                    imports = @()
                }

                Mock Test-IsGitRepoRoot { $true } -ParameterFilter { $path -eq $vendorPath }
                Mock Get-CurrentRepoCommit { "local-head" } -ParameterFilter { $path -eq $vendorPath }
                Mock Invoke-GitCapture {
                    param($GitArgs)
                    if (($GitArgs -join " ") -match "refs/remotes/origin/main") {
                        return "1111111111111111111111111111111111111111"
                    }
                    throw "unexpected git call: $($GitArgs -join ' ')"
                }
                Mock Resolve-RemoteCommit { throw "Resolve-RemoteCommit should not be called when local remote ref is present." }

                $items = @(Get-UpdatePlanItems $cfg -PreferLocalRefs)

                $items.Count | Should Be 1
                $items[0].target | Should Be "1111111111111111111111111111111111111111"
                Assert-MockCalled Resolve-RemoteCommit -Times 0 -Exactly -Scope It
            }
            finally {
                $script:VendorDir = $oldVendorDir
            }
        }

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

        It "Falls back to per-source fetch when parallel prefetch fails" {
            $oldPlan = $script:Plan
            $oldLocked = $script:Locked
            $oldUpgrade = $script:Upgrade
            try {
                $script:Plan = $false
                $script:Locked = $false
                $script:Upgrade = $false

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" })
                    targets = @()
                    mappings = @()
                    imports = @([pscustomobject]@{ name = "import-a"; mode = "manual"; repo = "https://example.com/b.git"; ref = "main"; skill = "." })
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "sync"
                }

                Mock LoadCfg { $cfg }
                Mock Invoke-PrebuildCheck {}
                Mock Confirm-UpdateForce { $true }
                Mock Skip-IfDryRun { $false }
                Mock Preflight {}
                Mock Get-UpdateParallelism { 2 }
                Mock Invoke-ParallelGitPrefetch { $false }
                Mock Get-UpdatePlanItems { @([pscustomobject]@{ type = "vendor"; name = "vendor-a"; current = "old"; target = "new"; changed = $true }) }
                Mock Test-UpdateCanFastNoop { $false }
                $script:importSkipFetchValues = New-Object System.Collections.Generic.List[bool]
                $script:vendorSkipFetchValues = New-Object System.Collections.Generic.List[bool]
                Mock 更新Imports {
                    param($cfg, [switch]$SkipPreflight, $SkipForceClean, [switch]$SkipFetch)
                    $script:importSkipFetchValues.Add([bool]$SkipFetch) | Out-Null
                    @()
                }
                Mock 更新Vendor {
                    param($cfg, [switch]$SkipPreflight, $SkipForceClean, [switch]$SkipFetch)
                    $script:vendorSkipFetchValues.Add([bool]$SkipFetch) | Out-Null
                    @()
                }
                Mock 构建生效 {}
                Mock Write-FailureSummary {}

                更新

                Assert-MockCalled 更新Imports -Times 1 -Exactly -Scope It
                Assert-MockCalled 更新Vendor -Times 1 -Exactly -Scope It
                $script:importSkipFetchValues.Count | Should Be 1
                $script:vendorSkipFetchValues.Count | Should Be 1
                $script:importSkipFetchValues[0] | Should Be $false
                $script:vendorSkipFetchValues[0] | Should Be $false
            }
            finally {
                $script:Plan = $oldPlan
                $script:Locked = $oldLocked
                $script:Upgrade = $oldUpgrade
                Remove-Variable -Scope Script -Name importSkipFetchValues -ErrorAction SilentlyContinue
                Remove-Variable -Scope Script -Name vendorSkipFetchValues -ErrorAction SilentlyContinue
            }
        }

        It "Skips per-source fetch only after successful parallel prefetch" {
            $oldPlan = $script:Plan
            $oldLocked = $script:Locked
            $oldUpgrade = $script:Upgrade
            try {
                $script:Plan = $false
                $script:Locked = $false
                $script:Upgrade = $false

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" })
                    targets = @()
                    mappings = @()
                    imports = @([pscustomobject]@{ name = "import-a"; mode = "manual"; repo = "https://example.com/b.git"; ref = "main"; skill = "." })
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "sync"
                }

                Mock LoadCfg { $cfg }
                Mock Invoke-PrebuildCheck {}
                Mock Confirm-UpdateForce { $true }
                Mock Skip-IfDryRun { $false }
                Mock Preflight {}
                Mock Get-UpdateParallelism { 2 }
                Mock Invoke-ParallelGitPrefetch { $true }
                Mock Get-UpdatePlanItems { @([pscustomobject]@{ type = "vendor"; name = "vendor-a"; current = "old"; target = "new"; changed = $true }) }
                Mock Test-UpdateCanFastNoop { $false }
                $script:importSkipFetchValues = New-Object System.Collections.Generic.List[bool]
                $script:vendorSkipFetchValues = New-Object System.Collections.Generic.List[bool]
                Mock 更新Imports {
                    param($cfg, [switch]$SkipPreflight, $SkipForceClean, [switch]$SkipFetch)
                    $script:importSkipFetchValues.Add([bool]$SkipFetch) | Out-Null
                    @()
                }
                Mock 更新Vendor {
                    param($cfg, [switch]$SkipPreflight, $SkipForceClean, [switch]$SkipFetch)
                    $script:vendorSkipFetchValues.Add([bool]$SkipFetch) | Out-Null
                    @()
                }
                Mock 构建生效 {}
                Mock Write-FailureSummary {}

                更新

                Assert-MockCalled 更新Imports -Times 1 -Exactly -Scope It
                Assert-MockCalled 更新Vendor -Times 1 -Exactly -Scope It
                $script:importSkipFetchValues.Count | Should Be 1
                $script:vendorSkipFetchValues.Count | Should Be 1
                $script:importSkipFetchValues[0] | Should Be $true
                $script:vendorSkipFetchValues[0] | Should Be $true
            }
            finally {
                $script:Plan = $oldPlan
                $script:Locked = $oldLocked
                $script:Upgrade = $oldUpgrade
                Remove-Variable -Scope Script -Name importSkipFetchValues -ErrorAction SilentlyContinue
                Remove-Variable -Scope Script -Name vendorSkipFetchValues -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Import path auto-repair" {
        BeforeEach {
            Mock Resolve-RemoteCommit { "abc123" }
        }

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
            Assert-MockCalled Ensure-RepoFromGitArchive -Times 1 -Exactly -Scope It
            Assert-MockCalled Ensure-RepoFromGitHubTreeSnapshot -Times 0 -Exactly -Scope It
        }

        It "Falls back to GitHub tree snapshot when git archive fallback fails" {
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
            Mock Ensure-RepoFromGitArchive { throw "archive unavailable" }
            Mock Ensure-RepoFromGitHubTreeSnapshot {}

            $failures = 更新Imports $cfg -SkipPreflight -SkipFetch

            @($failures).Count | Should Be 0
            Assert-MockCalled Ensure-RepoFromGitArchive -Times 1 -Exactly -Scope It
            Assert-MockCalled Ensure-RepoFromGitHubTreeSnapshot -Times 1 -Exactly -Scope It
        }

        It "Falls back to git archive when sparse repo update succeeds but target skill is still missing" {
            $cfg = [pscustomobject]@{
                imports = @(
                    [pscustomobject]@{
                        name = "openpyxl"
                        mode = "manual"
                        repo = "https://github.com/example/workspace-hub.git"
                        ref = "main"
                        skill = ".claude\skills\data\office\openpyxl"
                        sparse = $true
                    }
                )
            }

            Mock Preflight {}
            Mock Optimize-Imports {}
            Mock SaveCfgSafe {}
            Mock Ensure-Repo {}
            Mock Resolve-SkillPath { param($base, $skillPath) return $skillPath }
            $script:archiveFallbackUsed = $false
            Mock Ensure-RepoFromGitArchive { $script:archiveFallbackUsed = $true }
            Mock Ensure-RepoFromGitHubTreeSnapshot {}

            Mock Test-IsSkillDir {
                return $script:archiveFallbackUsed
            }

            $failures = 更新Imports $cfg -SkipPreflight -SkipFetch

            @($failures).Count | Should Be 0
            Assert-MockCalled Ensure-RepoFromGitArchive -Times 1 -Exactly -Scope It
            Assert-MockCalled Ensure-RepoFromGitHubTreeSnapshot -Times 0 -Exactly -Scope It
            Remove-Variable -Scope Script -Name archiveFallbackUsed -ErrorAction SilentlyContinue
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
                Mock Test-IsSkillDir { $true }

                $failures = 更新Imports $cfg -SkipPreflight -SkipFetch

                @($failures).Count | Should Be 0
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }
    }
}
