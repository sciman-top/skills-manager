. $PSScriptRoot\..\..\skills.ps1

Describe "Menu structure" {
    It "Keeps the top-level menu skeleton and submenu routing" {
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\src\Commands\Utils.ps1") -Raw

        $functionStart = $raw.IndexOf("function 菜单 {")
        $functionStart | Should BeGreaterThan -1

        $cursor = $raw.IndexOf("{", $functionStart)
        $cursor | Should BeGreaterThan -1
        $depth = 0
        $end = -1
        for ($i = $cursor; $i -lt $raw.Length; $i++) {
            $ch = $raw[$i]
            if ($ch -eq "{") { $depth++ }
            elseif ($ch -eq "}") {
                $depth--
                if ($depth -eq 0) {
                    $end = $i
                    break
                }
            }
        }
        $end | Should BeGreaterThan -1
        $menuBody = $raw.Substring($functionStart, $end - $functionStart + 1)

        $previousIndex = -1
        @(
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
        ) | ForEach-Object {
            $idx = $menuBody.IndexOf($_)
            $idx | Should BeGreaterThan -1
            $idx | Should BeGreaterThan $previousIndex
            $previousIndex = $idx
        }

        @(
            "function MCP菜单"
            "function 技能库管理菜单"
            "function 更多菜单"
        ) | ForEach-Object {
            $raw | Should Match $_
        }

        $menuBody | Should Match '"8"\s*\{\s*MCP菜单\s*\}'
        $menuBody | Should Match '"9"\s*\{\s*技能库管理菜单\s*\}'
        $menuBody | Should Match '"10"\s*\{\s*更多菜单\s*\}'
    }
}
