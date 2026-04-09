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

        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock 收集ManualSkills { @() }
        Mock 收集OverridesSkills { @() }
        Mock 收集Skills {
            ,@(
                [pscustomobject]@{
                    vendor = "anthropics-skills"
                    from = "skills\theme-factory"
                    full = "E:\CODE\skills-manager\vendor\anthropics-skills\skills\theme-factory"
                }
            )
        }
        Mock Filter-Skills { param($items, $filter) $items }
        Mock Get-InstalledSet {
            $set = New-Object 'System.Collections.Generic.HashSet[string]'
            $set.Add("anthropics-skills|skills\theme-factory") | Out-Null
            return $set
        }
        Mock Select-Items {
            [pscustomobject]@{
                canceled = $false
                items = ,@(
                    [pscustomobject]@{
                        vendor = "anthropics-skills"
                        from = "skills\theme-factory"
                        full = "E:\CODE\skills-manager\vendor\anthropics-skills\skills\theme-factory"
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
}
