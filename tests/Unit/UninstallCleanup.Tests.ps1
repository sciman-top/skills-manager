. $PSScriptRoot\..\..\skills.ps1

Describe "Uninstall cleanup" {
    It "ignores empty override directories" {
        $oldOverridesDir = $script:OverridesDir
        try {
            $script:OverridesDir = Join-Path $TestDrive "overrides"
            $empty = Join-Path $script:OverridesDir "empty"
            $populated = Join-Path $script:OverridesDir "populated"
            New-Item -ItemType Directory -Path $empty, $populated -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $populated "SKILL.md") -Value "fixture"

            $names = @(Get-OverridesDirs | ForEach-Object Name)

            $names | Should Contain "populated"
            $names | Should Not Contain "empty"
        }
        finally {
            $script:OverridesDir = $oldOverridesDir
        }
    }

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
        Assert-MockCalled 构建生效 -Times 1 -Exactly -Scope It
    }

    It "Removes a skill non-interactively by leaf name" {
        $cfg = [pscustomobject]@{
            vendors = @(
                [pscustomobject]@{ name = "manual"; repo = ""; ref = "main" }
            )
            mappings = @(
                [pscustomobject]@{ vendor = "manual"; from = "ui-ux-pro-max"; to = "ui-ux-pro-max" }
            )
            imports = @(
                [pscustomobject]@{
                    name = "ui-ux-pro-max"
                    mode = "manual"
                    repo = "https://github.com/example/ui-ux-pro-max.git"
                    ref = "main"
                    skill = "."
                    sparse = $false
                }
            )
            targets = @()
            mcp_servers = @()
            mcp_targets = @()
            update_force = $false
            sync_mode = "link"
        }

        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock 收集ManualSkills {
            ,@([pscustomobject]@{ vendor = "manual"; from = "ui-ux-pro-max"; full = (Join-Path $TestDrive "imports\ui-ux-pro-max") })
        }
        Mock 收集OverridesSkills { @() }
        Mock 收集Skills {
            ,@([pscustomobject]@{ vendor = "manual"; from = "ui-ux-pro-max"; full = (Join-Path $TestDrive "imports\ui-ux-pro-max") })
        }
        Mock Filter-Skills { param($items, $filter) $items }
        Mock Select-Items { throw "Select-Items should not be called for non-interactive uninstall" }
        Mock Confirm-WithSummary { throw "Confirm-WithSummary should not be called with --yes" }
        Mock SaveCfg {}
        Mock Clear-SkillsCache {}
        Mock 构建生效 {}

        卸载 @("ui-ux-pro-max", "--yes")

        @($cfg.mappings).Count | Should Be 0
        @($cfg.imports).Count | Should Be 0
        Assert-MockCalled 构建生效 -Times 1 -Exactly -Scope It
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
