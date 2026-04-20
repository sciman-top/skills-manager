. $PSScriptRoot\..\..\skills.ps1

Describe "Menu structure" {
    It "Keeps the top-level menu skeleton and submenu routing" {
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\src\Commands\Utils.ps1") -Raw

        @(
            "1\) 浏览技能"
            "2\) 选择安装"
            "3\) 粘贴命令导入"
            "4\) 卸载技能"
            "5\) 重建并同步"
            "6\) 更新上游"
            "7\) 目标仓审查"
            "8\) MCP 服务"
            "9\) 技能库管理"
            "10\) 更多"
        ) | ForEach-Object {
            $raw | Should Match $_
        }

        @(
            "function MCP菜单"
            "function 技能库管理菜单"
            "function 更多菜单"
        ) | ForEach-Object {
            $raw | Should Match $_
        }

        $raw | Should Match '"8"\s*\{\s*MCP菜单\s*\}'
        $raw | Should Match '"9"\s*\{\s*技能库管理菜单\s*\}'
        $raw | Should Match '"10"\s*\{\s*更多菜单\s*\}'
    }
}
