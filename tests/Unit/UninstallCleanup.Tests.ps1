. $PSScriptRoot\..\..\skills.ps1

Describe "Uninstall cleanup" {
    It "Removes matching vendor import when uninstalling a vendor skill" {
        $cfg = [pscustomobject]@{
            vendors = @(
                [pscustomobject]@{ name = "anthropics-skills"; repo = "https://github.com/anthropics/skills.git"; ref = "main" }
            )
            mappings = @(
                [pscustomobject]@{ vendor = "anthropics-skills"; from = "skills\theme-factory"; to = "anthropics-skills-skills-theme-factory" }
            )
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
            targets = @()
            mcp_servers = @()
            mcp_targets = @()
            update_force = $false
            sync_mode = "link"
        }

        $repoRoot = Join-Path $TestDrive "skills-manager"

        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock 收集ManualSkills { @() }
        Mock 收集OverridesSkills { @() }
        Mock 收集Skills {
            ,@(
                [pscustomobject]@{
                    vendor = "anthropics-skills"
                    from = "skills\theme-factory"
                    full = (Join-Path $repoRoot "vendor\anthropics-skills\skills\theme-factory")
                }
            )
        }
        Mock Filter-Skills { param($items, $filter) $items }
        Mock Select-Items {
            [pscustomobject]@{
                canceled = $false
                items = ,@(
                    [pscustomobject]@{
                        vendor = "anthropics-skills"
                        from = "skills\theme-factory"
                        full = (Join-Path $repoRoot "vendor\anthropics-skills\skills\theme-factory")
                    }
                )
            }
        }
        Mock Confirm-WithSummary { $true }
        Mock SaveCfg {}
        Mock Clear-SkillsCache {}
        Mock 构建生效 {}
        Mock Read-Host { "" }

        卸载

        @($cfg.mappings).Count | Should Be 0
        @($cfg.imports).Count | Should Be 0
        Assert-MockCalled 构建生效 -Times 1 -Exactly
    }

    It "Get-InstalledSet excludes unmapped manual imports and keeps mapped/overrides only" {
        $cfg = [pscustomobject]@{
            vendors = @()
            mappings = @(
                [pscustomobject]@{ vendor = "agent-skills-2"; from = "skills\\api-and-interface-design"; to = "x" },
                [pscustomobject]@{ vendor = "manual"; from = "mapped-manual"; to = "y" }
            )
            imports = @()
            targets = @()
            mcp_servers = @()
            mcp_targets = @()
            update_force = $false
            sync_mode = "link"
        }
        $manualItems = @(
            [pscustomobject]@{ vendor = "manual"; from = "mapped-manual"; source = "imports" },
            [pscustomobject]@{ vendor = "manual"; from = "unmapped-manual"; source = "imports" },
            [pscustomobject]@{ vendor = "manual"; from = "legacy-manual"; source = "legacy-manual-dir" }
        )
        $overrideItems = @(
            [pscustomobject]@{ vendor = "overrides"; from = "custom-windows-encoding-guard" }
        )

        $installed = Get-InstalledSet $cfg $manualItems $overrideItems

        $installed.Count | Should Be 3
        $installed.Contains("manual|mapped-manual") | Should Be $true
        $installed.Contains("manual|legacy-manual") | Should Be $false
        $installed.Contains("manual|unmapped-manual") | Should Be $false
        $installed.Contains("overrides|custom-windows-encoding-guard") | Should Be $true
    }

    It "Uninstall candidate calculation does not duplicate overrides" {
        $cfg = [pscustomobject]@{
            vendors = @()
            mappings = @()
            imports = @()
            targets = @()
            mcp_servers = @()
            mcp_targets = @()
            update_force = $false
            sync_mode = "link"
        }
        $manualItems = @()
        $overrideItems = @([pscustomobject]@{ vendor = "overrides"; from = "governance-clarification-protocol"; full = "x" })

        $installedSet = Get-InstalledSet $cfg $manualItems $overrideItems
        $all = @($overrideItems)
        $list = Filter-Skills $all ""
        $onlyInstalled = Hide-VendorRootSkills ($list | Where-Object { $installedSet.Contains("$($_.vendor)|$($_.from)") })

        @($onlyInstalled).Count | Should Be 1
    }
}
