. $PSScriptRoot\..\..\skills.ps1

Describe "Selection Cancellation" {
    It "Treats blank menu input as 0 so non-interactive menus exit" {
        Mock Read-HostSafe { "" }

        Read-MenuChoice "请选择" | Should Be "0"
    }

    It "Marks input 0 as canceled in Read-SelectionIndices" {
        Mock Read-HostSafe { "0" }

        $result = Read-SelectionIndices "请选择" 3 "invalid"

        $result.canceled | Should Be $true
        $result.indices.Count | Should Be 0
    }

    It "Does not build when install selection is canceled with 0" {
        Mock Preflight {}
        Mock LoadCfg {
            [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "demo-vendor"; repo = "https://example.com/demo.git"; ref = "main" }
                )
                mappings = @()
                imports = @()
                targets = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "link"
            }
        }
        Mock 收集ManualSkills { @() }
        Mock 收集Skills {
            @(
                [pscustomobject]@{
                    vendor = "demo-vendor"
                    from = "skills\\demo-skill"
                    full = "E:\\demo"
                }
            )
        }
        Mock Get-InstalledSet {
            New-Object 'System.Collections.Generic.HashSet[string]'
        }
        Mock Filter-Skills { param($items, $filter) $items }
        Mock Read-HostSafe {
            param($prompt)
            if ($prompt -like "*关键词*") { return "" }
            return "0"
        }
        Mock Write-ItemsInColumns {}
        Mock Write-SelectionHint {}
        Mock 构建生效 {}

        安装

        Assert-MockCalled 构建生效 -Times 0 -Exactly
    }
}
