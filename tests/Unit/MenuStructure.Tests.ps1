. $PSScriptRoot\..\..\skills.ps1

Describe "Menu structure" {
    function Get-FunctionBody {
        param(
            [string]$Text,
            [string]$FunctionName
        )

        $start = $Text.IndexOf("function $FunctionName {")
        $start | Should BeGreaterThan -1

        $cursor = $Text.IndexOf("{", $start)
        $cursor | Should BeGreaterThan -1

        $depth = 0
        for ($i = $cursor; $i -lt $Text.Length; $i++) {
            $ch = $Text[$i]
            if ($ch -eq "{") {
                $depth++
            }
            elseif ($ch -eq "}") {
                $depth--
                if ($depth -eq 0) {
                    return $Text.Substring($start, $i - $start + 1)
                }
            }
        }

        throw "Failed to extract function body for $FunctionName"
    }

    function Assert-MenuRouting {
        param(
            [string]$MenuBody,
            [hashtable]$ExpectedRoutes,
            [string[]]$ExpectedLabels
        )

        $previousIndex = -1
        foreach ($label in $ExpectedLabels) {
            $idx = $MenuBody.IndexOf($label)
            $idx | Should BeGreaterThan -1
            $idx | Should BeGreaterThan $previousIndex
            $previousIndex = $idx
        }

        foreach ($entry in $ExpectedRoutes.GetEnumerator()) {
            $pattern = ('"{0}"\s*\{{\s*{1}\s*\}}' -f $entry.Key, [regex]::Escape([string]$entry.Value))
            $MenuBody | Should Match $pattern
        }
    }

    It "Keeps the top-level menu skeleton and submenu routing" {
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\src\Commands\Utils.ps1") -Raw
        $generated = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\skills.ps1") -Raw

        $menuBody = Get-FunctionBody $raw "菜单"
        $generatedMenuBody = Get-FunctionBody $generated "菜单"

        $expectedLabels = @(
            "1) 浏览技能"
            "2) 选择安装"
            "3) 粘贴命令导入"
            "4) 卸载技能"
            "5) 重建并同步"
            "6) 更新上游"
            "7) 目标仓审查"
            "8) MCP 服务"
            "9) 技能库管理"
            "10) 更多"
            "98) 帮助"
            "0) 退出"
        )

        $expectedRoutes = @{
            "1" = "发现"
            "2" = "安装"
            "3" = "命令导入安装"
            "4" = "卸载"
            "5" = "构建生效"
            "6" = "更新"
            "7" = "审查目标菜单"
            "8" = "MCP菜单"
            "9" = "技能库管理菜单"
            "10" = "更多菜单"
            "98" = "帮助"
            "0" = "return"
        }

        Assert-MenuRouting $menuBody $expectedRoutes $expectedLabels
        Assert-MenuRouting $generatedMenuBody $expectedRoutes $expectedLabels

        @(
            "function MCP菜单"
            "function 技能库管理菜单"
            "function 更多菜单"
        ) | ForEach-Object {
            $raw | Should Match $_
            $generated | Should Match $_
        }

        $mcpBody = Get-FunctionBody $raw "MCP菜单"
        Assert-MenuRouting $mcpBody (@{ "1" = "安装MCP"; "2" = "卸载MCP"; "3" = "同步MCP"; "0" = "return" }) @(
            "1) 新增 MCP 服务"
            "2) 卸载 MCP 服务"
            "3) 同步 MCP 配置"
            "0) 返回"
        )

        $skillLibraryBody = Get-FunctionBody $raw "技能库管理菜单"
        Assert-MenuRouting $skillLibraryBody (@{
            "1" = "新增技能库"
            "2" = "删除技能库"
            "3" = "锁定"
            "4" = "打开配置"
            "0" = "return"
        }) @(
            "1) 新增技能库"
            "2) 删除技能库"
            "3) 生成锁文件"
            "4) 打开配置"
            "0) 返回"
        )

        $moreBody = Get-FunctionBody $raw "更多菜单"
        Assert-MenuRouting $moreBody (@{
            "1" = "Invoke-Workflow @()"
            "2" = "自动更新设置"
            "3" = "解除关联"
            "4" = "清理备份"
            "0" = "return"
        }) @(
            "1) 一键工作流"
            "2) 自动更新设置"
            "3) 解除关联"
            "4) 清理备份"
            "0) 返回"
        )
    }
}
