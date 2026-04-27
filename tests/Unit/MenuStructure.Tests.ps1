. $PSScriptRoot\..\..\skills.ps1

Describe "Menu structure" {
    function Get-FunctionBody {
        param(
            [string]$Text,
            [string]$FunctionName
        )

        $start = $Text.IndexOf("function $FunctionName {")
        if ($start -lt 0) {
            throw "Failed to locate function $FunctionName"
        }

        $cursor = $Text.IndexOf("{", $start)
        if ($cursor -lt 0) {
            throw "Failed to locate opening brace for $FunctionName"
        }

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
            "function 目标仓管理菜单"
            "function 审查高级菜单"
        ) | ForEach-Object {
            $raw | Should Match $_
            $generated | Should Match $_
        }

        $mcpBody = Get-FunctionBody $raw "MCP菜单"
        Assert-MenuRouting $mcpBody (@{ "1" = "安装MCP"; "2" = "卸载MCP"; "3" = "同步MCP"; "0" = "return" }) @(
            "1) 新增 MCP"
            "2) 卸载 MCP"
            "3) 同步配置"
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
            "4) 打开 skills.json"
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
            "2) 自动更新"
            "3) 解除目标目录关联"
            "4) 清理 .bak 备份"
            "0) 返回"
        )

        $auditBody = Get-FunctionBody $raw "审查目标菜单"
        @(
            "流程：需求 -> 审查包 -> 预检 -> 应用"
            "1) 查看需求"
            "2) 编辑需求"
            "3) 目标仓列表"
            "4) 生成审查包"
            "5) 预检建议"
            "6) 应用建议（先 dry-run）"
            "7) 查看最近状态"
            "8) 发现新技能"
            "9) 目标仓管理"
            "10) 高级设置"
            "0) 返回"
        ) | ForEach-Object {
            $auditBody | Should Match ([regex]::Escape($_))
        }

        $targetAdminBody = Get-FunctionBody $raw "目标仓管理菜单"
        @(
            "1) 查看目标仓列表"
            "2) 新增目标仓"
            "3) 修改目标仓"
            "4) 删除目标仓"
            "0) 返回"
        ) | ForEach-Object {
            $targetAdminBody | Should Match ([regex]::Escape($_))
        }

        $advancedAuditBody = Get-FunctionBody $raw "审查高级菜单"
        @(
            "1) 导入结构化需求"
            "2) 初始化审查配置"
            "3) 查看 AI 提示词"
            "4) 编辑 AI 提示词"
            "5) 直接执行建议（高级）"
            "0) 返回"
        ) | ForEach-Object {
            $advancedAuditBody | Should Match ([regex]::Escape($_))
        }
    }

    It "Groups help text around the expert-first menu labels" {
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\src\Commands\Utils.ps1") -Raw
        $helpBody = Get-FunctionBody $raw "帮助"

        @(
            "常用流程："
            "接入来源：新增技能库，或用 add/npx 导入单个技能"
            "安装技能：浏览技能 -> 选择安装/粘贴命令导入 -> 重建并同步"
            "目标仓审查：查看需求 -> 生成审查包 -> 预检建议 -> 应用建议"
            "菜单地图："
            "MCP 服务：新增 MCP、卸载 MCP、同步配置"
            "技能库管理：新增/删除技能库、生成锁文件、打开 skills.json"
            "更多：一键工作流、自动更新、解除目标目录关联、清理 .bak 备份"
            "浏览技能：只列出当前来源中的可用技能，不改配置"
            '重建并同步：根据 `skills.json` 重建 `agent/` 并同步到 `targets`'
            '只有 `--apply --yes` 才真正写入'
        ) | ForEach-Object {
            $helpBody | Should Match ([regex]::Escape($_))
        }
    }

    It "Documents the expert-first interactive menu in both readmes" {
        $readme = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\README.md") -Raw
        $readmeEn = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\README.en.md") -Raw

        @(
            '交互菜单按“高频动作直达 + 领域子菜单”组织'
            '浏览技能'
            '选择安装'
            '粘贴命令导入'
            '重建并同步（CLI 命令仍为 `构建生效`）'
            '更新上游（CLI 命令仍为 `更新`）'
            '目标仓审查'
            'MCP 服务'
            '技能库管理'
            '更多'
        ) | ForEach-Object {
            $readme | Should Match ([regex]::Escape($_))
        }

        @(
            'The interactive menu uses direct frequent actions plus domain submenus.'
            'Browse Skills'
            'Pick Install'
            'Paste Command Import'
            'Rebuild and Sync (CLI command remains `构建生效`)'
            'Update Upstream (CLI command remains `更新`)'
            'Target Repo Audit'
            'MCP Services'
            'Skill Library Admin'
            'More'
            'The `Target Repo Audit` submenu follows the workflow'
        ) | ForEach-Object {
            $readmeEn | Should Match ([regex]::Escape($_))
        }
    }
}
