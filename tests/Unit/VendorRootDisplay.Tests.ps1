. $PSScriptRoot\..\..\skills.ps1

Describe "Vendor root display filtering" {
    It "Hides vendor root when child skills exist in same list" {
        $items = @(
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "." },
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "skills\\accessibility" },
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "skills\\seo" }
        )

        $filtered = Hide-VendorRootSkills $items

        @($filtered).Count | Should Be 2
        (@($filtered) | Where-Object { $_.from -eq "." }).Count | Should Be 0
    }

    It "Keeps vendor root when no child skill exists for that vendor" {
        $items = @(
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "." }
        )

        $filtered = Hide-VendorRootSkills $items

        @($filtered).Count | Should Be 1
        @($filtered)[0].from | Should Be "."
    }

    It "Does not hide root of other vendor" {
        $items = @(
            [pscustomobject]@{ vendor = "a"; from = "." },
            [pscustomobject]@{ vendor = "b"; from = "." },
            [pscustomobject]@{ vendor = "b"; from = "skills\\child" }
        )

        $filtered = Hide-VendorRootSkills $items

        (@($filtered) | Where-Object { $_.vendor -eq "a" -and $_.from -eq "." }).Count | Should Be 1
        (@($filtered) | Where-Object { $_.vendor -eq "b" -and $_.from -eq "." }).Count | Should Be 0
    }

    It "Includes override skills in discovery aggregation" {
        $root = Join-Path $TestDrive "ws-discover"
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $oldRoot = $script:Root
        $oldOverridesDir = $script:OverridesDir
        $oldGlobalRoot = $global:Root
        $oldGlobalOverridesDir = $global:OverridesDir
        try {
            $script:Root = $root
            $script:OverridesDir = Join-Path $root "overrides"
            $global:Root = $script:Root
            $global:OverridesDir = $script:OverridesDir
            New-Item -ItemType Directory -Path $script:OverridesDir -Force | Out-Null

            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    imports = @()
                    mappings = @()
                    targets = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "link"
                }
            }
            Mock 收集ManualSkills { @() }
            Mock 收集OverridesSkills {
                ,@([pscustomobject]@{
                    vendor = "overrides"
                    from = "custom-windows-encoding-guard"
                    full = (Join-Path $root "overrides\custom-windows-encoding-guard")
                })
            }

            $items = 收集Skills ""

            @($items).Count | Should Be 1
            (@($items) | Where-Object { $_.vendor -eq "overrides" -and $_.from -eq "custom-windows-encoding-guard" }).Count | Should Be 1
        }
        finally {
            $script:Root = $oldRoot
            $script:OverridesDir = $oldOverridesDir
            $global:Root = $oldGlobalRoot
            $global:OverridesDir = $oldGlobalOverridesDir
        }
    }
}
