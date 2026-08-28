function 打开配置 {
    Need (Test-Path $CfgPath) "缺少配置文件：$CfgPath"
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Invoke-StartProcess "code" "`"$CfgPath`""
    }
    else {
        Invoke-StartProcess "notepad" "`"$CfgPath`""
    }
}

function 解除关联 {
    Preflight
    if (Skip-IfDryRun "解除关联") { return }
    $cfg = LoadCfg
    foreach ($t in $cfg.targets) {
        $target = Resolve-TargetDir $t.path
        if ($target) {
            Remove-JunctionAndRestore $target
        }
    }
    Write-Host "解除完成。"
}

function 清理备份 {
    $excludeRoots = @($VendorDir, $AgentDir, $ImportDir, (Join-Path $Root ".git"))
    $bakDirs = @()
    $bakFiles = @()
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        if (Is-ExcludedPath $dir $excludeRoots) { continue }
        try {
            $entries = Get-ChildItem $dir -Force -ErrorAction SilentlyContinue
        }
        catch { continue }
        foreach ($e in $entries) {
            if ($e.PSIsContainer) {
                if (Is-ReparsePoint $e.FullName) { continue }
                if ($e.Name -eq ".bak" -or $e.Name -like "*.bak.*") { $bakDirs += $e }
                $stack.Push($e.FullName)
            }
            else {
                if ($e.Name -like "*.bak.*") { $bakFiles += $e }
            }
        }
    }

    if ($bakDirs.Count -eq 0 -and $bakFiles.Count -eq 0) {
        Write-Host "未发现备份文件或目录。"
        return
    }

    # 排除已包含在 .bak 目录下的文件，避免重复/噪声
    $filteredFiles = @()
    foreach ($f in $bakFiles) {
        $inBakDir = $false
        foreach ($d in $bakDirs) {
            if ($f.FullName.StartsWith($d.FullName + "\")) {
                $inBakDir = $true
                break
            }
        }
        if (-not $inBakDir) { $filteredFiles += $f }
    }

    $total = $bakDirs.Count + $filteredFiles.Count
    Write-Host ("将清理备份项共 {0} 个（目录 {1}，文件 {2}）。" -f $total, $bakDirs.Count, $filteredFiles.Count)

    $preview = @()
    foreach ($d in $bakDirs) { $preview += $d.FullName }
    foreach ($f in $filteredFiles) { $preview += $f.FullName }
    if (-not (Confirm-WithSummary "将清理以下备份项" $preview "输入 DELETE 确认彻底清理备份" "DELETE")) {
        Write-Host "已取消清理。"
        return
    }
    if (Skip-IfDryRun "清理备份") { return }

    foreach ($d in ($bakDirs | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not (Is-PathInsideOrEqual $d.FullName $Root)) { continue }
        Invoke-RemoveItem $d.FullName -Recurse
    }
    foreach ($f in $filteredFiles) {
        if (-not (Is-PathInsideOrEqual $f.FullName $Root)) { continue }
        Invoke-RemoveItem $f.FullName
    }
    Write-Host "清理完成。"
}
function MCP菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== MCP 服务 ==="
        Write-Host "1) 新增 MCP"
        Write-Host "2) 卸载 MCP"
        Write-Host "3) 同步配置"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { 安装MCP }
            "2" { 卸载MCP }
            "3" { 同步MCP }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 技能库管理菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 技能库管理 ==="
        Write-Host "1) 新增技能库"
        Write-Host "2) 删除技能库"
        Write-Host "3) 生成锁文件"
        Write-Host "4) 打开 skills.json"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { 新增技能库 }
            "2" { 删除技能库 }
            "3" { 锁定 }
            "4" { 打开配置 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 更多菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 更多 ==="
        Write-Host "1) 解除目标目录关联"
        Write-Host "2) 清理 .bak 备份"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { 解除关联 }
            "2" { 清理备份 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 帮助 {
    @'
Skills 管理器（中文菜单）

常用流程：
  1) 接入来源：新增技能库，或用 add/npx 导入单个技能
  2) 安装技能：浏览技能 -> 选择安装/粘贴命令导入 -> 重建并同步
  3) 日常维护：更新上游 -> 重建并同步 -> doctor --strict
  4) 目标仓审查：扫描目标仓 -> 生成三文件审查包 -> 预检/校验预演 -> 显式应用

菜单地图：
  - 主菜单：浏览技能、选择安装、粘贴命令导入、卸载技能、重建并同步、更新上游
  - 目标仓审查：目标仓扫描、审查包、预检、应用、状态
  - MCP 服务：新增 MCP、卸载 MCP、同步配置
  - 技能库管理：新增/删除技能库、生成锁文件、打开 skills.json
  - 更多：解除目标目录关联、清理 .bak 备份

主要功能说明：
  - 浏览技能：只列出当前来源中的可用技能，不改配置
  - 选择安装：勾选技能并写入 `mappings`
  - 粘贴命令导入：解析 `add` / `npx` 命令，导入后自动重建
  - 卸载技能：从 `mappings` 移除，必要时清理导入目录和备份
  - 重建并同步：根据 `skills.json` 重建 `agent/` 并同步到 `targets`
  - 更新上游：拉取 `vendor/`、`imports/` 后重建并同步
  - 目标仓审查：生成 snapshot/recommendations/receipt，先 dry-run，再按确认口令落盘
  - MCP 服务：维护 `skills.json` 中的 `mcp_servers` 并同步到目标 CLI
  - 技能库管理：维护来源、锁文件和配置
  - 项目迁移：生成 private-all 私用全量快照或 rescan 辅助清单；private-all 是明文、无口令的私用快照
  - 发行更新：仅对未修改的 GitHub Release 安装版校验、备份并更新本体；源码开发版仍通过 Git 更新

易混点：
  - 只想让本地配置重新输出：用“重建并同步”（CLI：`构建生效`）
  - 想拉取上游新内容：用“更新上游”（CLI：`更新`）
  - 已知道安装命令：用“粘贴命令导入”；想先浏览再挑选：用“选择安装”
  - `add`/`npx` 未指定 `--skill` 时只新增技能库，不会安装整库技能
  - `应用` 默认只 dry-run；只有 `--apply --yes` 才真正写入
  - `构建生效` 写入仓库外宿主目录前要求 clean Git commit；仅在明确接受风险时使用 `-AllowUnverifiedHostProjection`，receipt 会标记为 unverified override

常用命令：
  .\skills.ps1 发现
  .\skills.ps1 安装
  .\skills.ps1 命令导入安装
  .\skills.ps1 卸载 [<skill-name>|<index>|all] [--yes] [--filter <keyword>]
  .\skills.ps1 新增技能库
  .\skills.ps1 add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]
  .\skills.ps1 npx "skills add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
  .\skills.ps1 构建生效
  .\skills.ps1 构建生效 -SkillProfile full-compatible
  .\skills.ps1 构建生效 -AllowUnverifiedHostProjection
  .\skills.ps1 更新 -Plan
  .\skills.ps1 check-updates --json
  .\skills.ps1 更新 -Upgrade
  .\skills.ps1 锁定
  .\skills.ps1 清理无效映射 [--yes] [--no-build]
  .\skills.ps1 迁移 --mode private-all|rescan [--version <version>] [--out <迁移包.zip>] [--force]
  .\skills.ps1 migration-unlock [--credentials <MIGRATION-MCP-CREDENTIALS.json|.enc.json>] [--yes]
  .\skills.ps1 migration-apply [--skip-mcp] [--json]
  .\skills.ps1 release-update --check|--apply --yes [--sync-mcp] [--json]
  .\skills.ps1 release-update-schedule --enable|--disable [--time HH:mm] [--auto-apply] [--sync-mcp]

MCP：
  .\skills.ps1 安装MCP <name> -- <command> [args...]          （推荐）
  .\skills.ps1 安装MCP <name> --cmd <command> [--arg <arg>...] （兼容）
  .\skills.ps1 安装MCP <name> --transport http --url <url> [--bearer-token-env-var <ENV>] 
  .\skills.ps1 卸载MCP <name>
  .\skills.ps1 同步MCP
  .\skills.ps1 MCP配置 列表
  .\skills.ps1 MCP配置 使用 default|coding|dotnet|browser|database|off

规则治理：
  .\skills.ps1 rule-audit --repo <repo-root> [--user-root <path>] [--host codex|claude|zcode] --json
  .\skills.ps1 rule-estate-audit --workspace-root D:\CODE [--out <report.json>] --json
  全域审查自动发现工作区直属 Git 仓；默认排除 external、docs 与文档。可选 --registry 只比较外部快照 drift，不改变目标集合；仅显式 --out 写报告。
  .\skills.ps1 rule-estate-plan --review <reviewed-change-set.json> --workspace-root D:\CODE --out <plan.json> --json
  .\skills.ps1 rule-estate-apply --plan <plan.json> --workspace-root D:\CODE --token <plan.apply.required_token> --out <receipt.json> --json
  .\skills.ps1 rule-estate-rollback --receipt <receipt.json> --action-id <id> --workspace-root D:\CODE --token ROLLBACK_RULE_ESTATE_PATCH --json
  全域写入只接受 reviewed change-set 中的直属 Git 仓库 AGENTS.md/CLAUDE.md；用户级 Codex/Claude/ZCode 规则被拒绝，必须走 rules/global 的 global-rules-* 单写入入口。plan 生成绑定当前 review/roots/actions 的确认 token，apply 执行全量预检、逐目标 receipt、fail-fast、resume 和单目标 rollback；不自动 commit/push。
  .\skills.ps1 global-rules-plan --out .\reports\global-rule-projection\plan.json --json
  .\skills.ps1 global-rules-apply --plan <plan.json> --token <plan.apply.required_token> --out <receipt.json> --json
  .\skills.ps1 global-rules-check --json
  全局规则以 rules/global 为唯一源；投影只写用户 Codex AGENTS.md、Claude CLAUDE.md 和已配置的 ZCode AGENTS.md，保留备份与 receipt，不证明宿主已加载。

技能投影：
  .\skills.ps1 构建生效
  .\skills.ps1 构建生效 -SkillProfile full-compatible
  默认 profile=core（技能集合和数量以 skills.json 的 profile 为准）；full-compatible 显式投影所有当前允许的兼容技能，并按宿主排除特异技能。
  .\skills.ps1 capability-inventory --view skill-surfaces [--host-snapshot <snapshot.json>] [--host-probe] --json
  默认不调用宿主 CLI；仅 --host-probe 读取公开 Codex JSON，结果脱敏且不证明宿主已加载。

目标仓审查：
  .\skills.ps1 审查目标 列表
  .\skills.ps1 审查目标 添加 <name> <path>
  .\skills.ps1 审查目标 修改 <name> <path>
  .\skills.ps1 审查目标 删除 <name>
  .\skills.ps1 审查目标 扫描 [--query <user-goal>] [--out <dir>] [--force]
  .\skills.ps1 审查目标 预检 --run-id <run-id>
  .\skills.ps1 审查目标 预检 --recommendations <file>
  .\skills.ps1 审查目标 应用确认 --recommendations <file>
  .\skills.ps1 审查目标 应用 --recommendations <file> [--dry-run-ack "我知道未落盘"]
  .\skills.ps1 审查目标 应用 --recommendations <file> --apply --yes [--add-indexes "1,3"] [--remove-indexes "2"] [--mcp-add-indexes "1"] [--mcp-remove-indexes "2"]
  .\skills.ps1 审查目标 状态

维护：
  .\skills.ps1 解除关联
  .\skills.ps1 清理备份
  .\skills.ps1 doctor [--json] [--offline-contract] [--fix] [--dry-run-fix] [--strict]
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-skill-integrity.ps1 [-ReportPath <file>]

通用参数：
  -DryRun：仅预演（跳过写入/删除/同步/拉取）
  -Locked：严格锁定（需 skills.lock.json 且 commit 全匹配）
  -Plan：仅输出更新预览（不改动）
  -Upgrade：执行更新后自动刷新 skills.lock.json

配置：skills.json
  - vendors：上游仓库 URL
  - mappings：白名单（安装/卸载）
  - mcp_servers：MCP 服务清单（安装MCP/卸载MCP会自动同步）
  - mcp_targets：可选 MCP 目标目录（未配置时从 targets 自动推断）
  - sync_mode：Windows 优先 link（junction），受限环境用 sync

MCP/门禁环境变量：
  - SKILLS_MCP_VERIFY_GEMINI_CLI=1|true|yes|on：启用 Gemini CLI 实机校验（默认关闭）
  - SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS：统一设置 mcp list 校验超时（秒）
  - SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_<CLI>：按 CLI 覆盖校验超时（秒）
  - SKILLS_MCP_NATIVE_TIMEOUT_SECONDS：原生 claude mcp add/remove 超时（秒）
  - SKILLS_MCP_VERIFY_ATTEMPTS / SKILLS_MCP_VERIFY_INTERVAL_SECONDS：跨 CLI 校验重试次数/间隔（秒）
  - SKILLS_SYNC_MCP_THRESHOLD_MS：doctor JSON 门禁里 sync_mcp 的阈值（毫秒）

过滤语法（批量安装/卸载/发现命令）：
  - 多关键词：空格分隔，AND 过滤（如：docx pdf）
  - 正则：用 /.../ 包裹（如：/docx|pdf/）

本地技能：
  - add/npx 显式指定 --skill 时默认落入 imports（mode=manual），可用 --mode vendor 改为 vendor 管理。
  - manual/ 仅用于旧数据兼容；本仓自定义能力放 `overrides/custom/`，上游替换/补丁放 `overrides/patches/`，无 SKILL.md 的资源桥放 `overrides/resources/`。
  - 分类目录的叶子名会生成同名 `agent/<leaf>`；旧 `overrides/<leaf>` 扁平目录只兼容读取，跨分类同名会阻断构建。
  - “命令导入安装”支持多行输入 add / npx skills add / npx add-skill。
  - `安装` / `卸载` / `更新` / `构建生效` / `锁定` 等旧命令仍可使用。

目标仓审查：
  - `扫描` 只从已登记目标仓的扫描事实派生需求画像；新增技能/MCP候选必须基于该画像完成 preflight/dry-run。
  - 启动审查流程后，外层 AI 可以在本次流程内自主联网研究；联网不等于自动安装。
  - 每个 run 固定只有三个文件：不可编辑的 `snapshot.json`、唯一允许 AI 编辑的 `recommendations.json`、命令维护的 `receipt.json`；不得新增旁路报告或 markdown evidence。
  - 内置提示词只定义工作流，prompt contract version 已写入 `snapshot.json`；如需改默认提示词，请改 `src/Commands/AuditTargets.ps1` 或 `overrides/audit-outer-ai-prompt.md`。
  - 外层 AI 应先写完并自检 `recommendations.json`（schema、占位符、双理由、真实来源），再进入 preflight/dry-run；不得修改 snapshot 或 receipt。
  - `应用确认` 是单入口两阶段流程：先 dry-run，再要求输入确认口令 `APPLY <run-id>` 才执行落盘。
  - `应用` 默认只做 dry-run，且需显式确认口令 `我知道未落盘`；只有 `--apply --yes` 才会真正执行选中的新增/卸载。
  - 建议先执行 `预检`：会提前检查 `stale_snapshot` 与提示词契约版本，避免“先研究后阻断”。
  - `应用`/`应用确认` 会校验同目录 `snapshot.json` 与当前 live mappings、MCP、system/plugin 外部能力指纹；snapshot 缺失直接阻断，指纹漂移触发 stale_snapshot。
  - `stale_snapshot` 始终 fail closed；不存在确认口令或参数绕过。必须重新执行扫描并使用 fresh run。
  - `--out` 若指向已存在且非空目录，默认阻断，防止覆盖旧审查包；如确需复用，显式追加 `--force`。
  - `--run-id` / `--recommendations` 里出现 `<run-id>` 时会自动解析为最近可用 run；若无可用 run 才阻断并给出提示。
  - `状态` 从最近一次 `receipt.json` 的 workflow/dry_run/apply section 显示 `mode/success/persisted/changed_counts`。
  - 执行前会分别列出“技能新增/卸载”和“MCP 新增/卸载”四份带序号清单；dry-run 后向用户汇报时必须沿用原序号，并展示扫描画像依据。
  - `--add-indexes` / `--remove-indexes` 作用于技能清单；`--mcp-add-indexes` / `--mcp-remove-indexes` 作用于 MCP 清单；四份清单独立编号。

提示：如遇 PowerShell 脚本执行被拦，可在当前窗口临时放开：
  Set-ExecutionPolicy -Scope Process Bypass
'@ | Write-Host
}

function Resolve-AuditMenuRecommendationsPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return 'reports\skill-audit\<run-id>\recommendations.json'
    }
    return $path
}

function 目标仓管理菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 目标仓管理 ==="
        Write-Host "1) 查看目标仓列表"
        Write-Host "2) 新增目标仓"
        Write-Host "3) 修改目标仓"
        Write-Host "4) 删除目标仓"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("list") }
            "2" {
                $name = Read-HostSafe "目标仓名称"
                $path = Read-HostSafe "目标仓路径"
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("add", $name, $path)
                }
            }
            "3" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要修改的目标仓（输入 0 取消）" `
                    "未解析到有效序号，已取消修改。"
                if ($selection.canceled -or @($selection.items).Count -eq 0) {
                    Write-Host "已取消修改目标仓。"
                    continue
                }
                $name = [string]$selection.items[0].name
                $path = Read-HostSafe "新的目标仓路径"
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("update", $name, $path)
                }
            }
            "4" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要删除的目标仓（输入 0 取消）" `
                    "未解析到有效序号，已取消删除。"
                if ($selection.canceled -or @($selection.items).Count -eq 0) {
                    Write-Host "已取消删除目标仓。"
                    continue
                }
                $picked = $selection.items[0]
                $preview = @(
                    ("name: {0}" -f [string]$picked.name),
                    ("path: {0}" -f [string]$picked.path)
                ) -join "`n"
                if (-not (Confirm-WithSummary "将删除以下目标仓" $preview "确认删除该目标仓？" "Y")) {
                    Write-Host "已取消删除目标仓。"
                    continue
                }
                $name = [string]$picked.name
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    Invoke-AuditTargetsCommand @("remove", $name)
                }
            }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 审查高级菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 审查高级设置 ==="
        Write-Host "1) 初始化审查配置"
        Write-Host "2) 查看 AI 提示词"
        Write-Host "3) 编辑 AI 提示词"
        Write-Host "4) 直接执行建议（高级）"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("init") }
            "2" { Show-AuditOuterAiPromptTemplate }
            "3" { Edit-AuditOuterAiPromptTemplate }
            "4" {
                $path = Resolve-AuditMenuRecommendationsPath (Read-HostSafe "recommendations 文件路径（回车=最近 run）")
                Invoke-AuditTargetsCommand @("apply", "--recommendations", $path, "--apply", "--yes")
            }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 审查目标菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 目标仓审查 ==="
        Write-Host "流程：扫描目标仓 -> 审查包 -> 预检 -> 应用"
        Write-Host "1) 目标仓列表"
        Write-Host "2) 生成审查包"
        Write-Host "3) 预检建议"
        Write-Host "4) 应用建议（先 dry-run）"
        Write-Host "5) 查看最近状态"
        Write-Host "6) 目标仓管理"
        Write-Host "7) 高级设置"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("list") }
            "2" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                Write-Host "审查目标扫描固定汇总全部 enabled 目标仓。"
                Invoke-AuditTargetsCommand @("scan")
            }
            "3" {
                $path = Resolve-AuditMenuRecommendationsPath (Read-HostSafe "recommendations 文件路径（回车=最近 run）")
                Invoke-AuditTargetsCommand @("preflight", "--recommendations", $path)
            }
            "4" {
                $path = Resolve-AuditMenuRecommendationsPath (Read-HostSafe "recommendations 文件路径（回车=最近 run）")
                Invoke-AuditTargetsCommand @("apply-flow", "--recommendations", $path)
            }
            "5" { Invoke-AuditTargetsCommand @("status") }
            "6" { 目标仓管理菜单 }
            "7" { 审查高级菜单 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== Skills 管理器 ==="
        Write-Host "1) 浏览技能"
        Write-Host "2) 选择安装"
        Write-Host "3) 粘贴命令导入"
        Write-Host "4) 卸载技能"
        Write-Host "5) 重建并同步"
        Write-Host "6) 更新上游"
        Write-Host "7) 目标仓审查"
        Write-Host "8) MCP 服务"
        Write-Host "9) 技能库管理"
        Write-Host "10) 更多"
        Write-Host "98) 帮助"
        Write-Host "0) 退出"
        $c = Read-MenuChoice "请选择（回车退出）"
        switch ($c) {
            "1" { 发现 }
            "2" { 安装 }
            "3" { 命令导入安装 }
            "4" { 卸载 }
            "5" { 构建生效 }
            "6" { 更新 }
            "7" { 审查目标菜单 }
            "8" { MCP菜单 }
            "9" { 技能库管理菜单 }
            "10" { 更多菜单 }
            "98" { 帮助 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}
