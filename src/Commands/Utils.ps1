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
function Get-自动更新任务名 {
    return "skills-manager-weekly-update-friday-2000"
}
function Get-自动更新脚本路径 {
    return (Join-Path $Root "scripts/weekly-auto-update.ps1")
}
function Get-自动更新默认模式 {
    return "weekly"
}
function Get-自动更新默认时间 {
    return "20:00"
}
function Get-自动更新默认星期 {
    return "Friday"
}
function Get-自动更新星期别名映射 {
    return [ordered]@{
        "mon" = "Monday"; "monday" = "Monday"; "1" = "Monday"; "周一" = "Monday"; "星期一" = "Monday"
        "tue" = "Tuesday"; "tues" = "Tuesday"; "tuesday" = "Tuesday"; "2" = "Tuesday"; "周二" = "Tuesday"; "星期二" = "Tuesday"
        "wed" = "Wednesday"; "wednesday" = "Wednesday"; "3" = "Wednesday"; "周三" = "Wednesday"; "星期三" = "Wednesday"
        "thu" = "Thursday"; "thur" = "Thursday"; "thurs" = "Thursday"; "thursday" = "Thursday"; "4" = "Thursday"; "周四" = "Thursday"; "星期四" = "Thursday"
        "fri" = "Friday"; "friday" = "Friday"; "5" = "Friday"; "周五" = "Friday"; "星期五" = "Friday"
        "sat" = "Saturday"; "saturday" = "Saturday"; "6" = "Saturday"; "周六" = "Saturday"; "星期六" = "Saturday"
        "sun" = "Sunday"; "sunday" = "Sunday"; "7" = "Sunday"; "周日" = "Sunday"; "星期日" = "Sunday"; "周天" = "Sunday"; "星期天" = "Sunday"
    }
}
function Normalize-自动更新模式([string]$mode) {
    if ([string]::IsNullOrWhiteSpace($mode)) { return (Get-自动更新默认模式) }
    $v = $mode.Trim().ToLowerInvariant()
    if ($v -eq "daily" -or $v -eq "每天" -or $v -eq "每日") { return "daily" }
    if ($v -eq "weekly" -or $v -eq "每周") { return "weekly" }
    throw ("自动更新模式仅支持 daily 或 weekly：{0}" -f $mode)
}
function Normalize-自动更新时间([string]$at) {
    $value = if ([string]::IsNullOrWhiteSpace($at)) { Get-自动更新默认时间 } else { $at.Trim() }
    Need ($value -match "^\d{1,2}:\d{2}$") ("时间格式无效：{0}（请使用 HH:mm）" -f $value)
    $parts = $value.Split(":")
    $hour = [int]$parts[0]
    $minute = [int]$parts[1]
    Need ($hour -ge 0 -and $hour -le 23) ("小时无效：{0}（0-23）" -f $hour)
    Need ($minute -ge 0 -and $minute -le 59) ("分钟无效：{0}（0-59）" -f $minute)
    return ("{0:D2}:{1:D2}" -f $hour, $minute)
}
function Normalize-自动更新星期([string]$day) {
    $raw = if ([string]::IsNullOrWhiteSpace($day)) { Get-自动更新默认星期 } else { $day.Trim() }
    $key = $raw.ToLowerInvariant()
    $map = Get-自动更新星期别名映射
    if ($map.Contains($key)) { return [string]$map[$key] }
    $allowed = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    foreach ($item in $allowed) {
        if ($item.Equals($raw, [System.StringComparison]::OrdinalIgnoreCase)) { return $item }
    }
    throw ("星期无效：{0}（可用 Monday..Sunday / 周一..周日）" -f $day)
}
function Format-自动更新计划说明([string]$mode, [string]$at, [string]$dayOfWeek) {
    if ($mode -eq "daily") {
        return ("每天 {0}" -f $at)
    }
    return ("每周 {0} {1}" -f $dayOfWeek, $at)
}
function Get-自动更新任务描述([string]$mode, [string]$at, [string]$dayOfWeek) {
    return ("skills-manager 自动执行 更新 + 同步MCP | mode={0};at={1};day={2}" -f $mode, $at, $dayOfWeek)
}
function Parse-自动更新任务描述([string]$description) {
    $result = [ordered]@{
        found = $false
        mode = (Get-自动更新默认模式)
        at = (Get-自动更新默认时间)
        day = (Get-自动更新默认星期)
    }
    if ([string]::IsNullOrWhiteSpace($description)) { return [pscustomobject]$result }
    if ($description -notmatch "mode=([^;|]+)") { return [pscustomobject]$result }
    $result.mode = Normalize-自动更新模式 $Matches[1]
    if ($description -match "at=([^;|]+)") {
        $result.at = Normalize-自动更新时间 $Matches[1]
    }
    if ($description -match "day=([^;|]+)") {
        $result.day = Normalize-自动更新星期 $Matches[1]
    }
    $result.found = $true
    return [pscustomobject]$result
}
function 获取自动更新任务 {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return $null }
    try { return (Get-ScheduledTask -TaskName (Get-自动更新任务名) -ErrorAction Stop) }
    catch { return $null }
}
function 查看自动更新状态 {
    $taskName = Get-自动更新任务名
    $task = 获取自动更新任务
    if ($null -eq $task) {
        Write-Host ("自动更新：未启用（任务名：{0}）" -f $taskName) -ForegroundColor Yellow
        return
    }

    $info = $null
    try { $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop } catch {}
    $state = [string]$task.State
    $nextRun = "未知"
    $lastRun = "未知"
    if ($null -ne $info) {
        if ($info.NextRunTime -and $info.NextRunTime -gt [datetime]::MinValue) { $nextRun = $info.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss") }
        if ($info.LastRunTime -and $info.LastRunTime -gt [datetime]::MinValue) { $lastRun = $info.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss") }
    }
    $parsed = Parse-自动更新任务描述 ([string]$task.Description)
    $schedule = if ($parsed.found) { Format-自动更新计划说明 ([string]$parsed.mode) ([string]$parsed.at) ([string]$parsed.day) } else { "（旧任务：计划信息未记录）" }
    Write-Host ("自动更新：已启用（{0}，本机时间）" -f $schedule)
    Write-Host ("任务名：{0}" -f $taskName)
    Write-Host ("状态：{0}" -f $state)
    Write-Host ("下次运行：{0}" -f $nextRun)
    Write-Host ("上次运行：{0}" -f $lastRun)
}
function 启用自动更新([string]$Mode = "", [string]$At = "", [string]$DayOfWeek = "") {
    $taskName = Get-自动更新任务名
    $runnerPath = Get-自动更新脚本路径
    Need (Test-Path $runnerPath) ("缺少自动更新脚本：{0}" -f $runnerPath)
    Need (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    Need (Get-Command New-ScheduledTaskAction -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    Need (Get-Command powershell -ErrorAction SilentlyContinue) "未找到 powershell 可执行文件。"

    $modeNormalized = Normalize-自动更新模式 $Mode
    $atNormalized = Normalize-自动更新时间 $At
    $dayNormalized = if ($modeNormalized -eq "weekly") { Normalize-自动更新星期 $DayOfWeek } else { Get-自动更新默认星期 }

    if (Skip-IfDryRun "启用自动更新计划任务") { return }

    $pwsh = (Get-Command powershell -ErrorAction Stop).Source
    $args = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath)
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $args -WorkingDirectory $Root
    $trigger = if ($modeNormalized -eq "daily") {
        New-ScheduledTaskTrigger -Daily -At $atNormalized
    }
    else {
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayNormalized -At $atNormalized
    }
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $description = Get-自动更新任务描述 $modeNormalized $atNormalized $dayNormalized
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $description -Force | Out-Null
    Write-Host ("✅ 已启用自动更新：{0}（本机时间）。" -f (Format-自动更新计划说明 $modeNormalized $atNormalized $dayNormalized))
    查看自动更新状态
}
function 禁用自动更新 {
    $taskName = Get-自动更新任务名
    if (Skip-IfDryRun "禁用自动更新计划任务") { return }
    $task = 获取自动更新任务
    if ($null -eq $task) {
        Write-Host "自动更新任务不存在，无需禁用。"
        return
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host "✅ 已禁用自动更新任务。"
}
function 自动更新设置 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 自动更新设置 ==="
        Write-Host "目标：按计划自动执行【更新 + 同步MCP】"
        查看自动更新状态
        Write-Host "1) 启用/更新计划（daily/weekly）"
        Write-Host "2) 禁用"
        Write-Host "3) 查看状态"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" {
                $modeInput = Read-HostSafe ("计划模式（daily/weekly，默认 {0}）" -f (Get-自动更新默认模式))
                $atInput = Read-HostSafe ("执行时间（HH:mm，默认 {0}）" -f (Get-自动更新默认时间))
                $modeNormalized = Normalize-自动更新模式 $modeInput
                $dayInput = ""
                if ($modeNormalized -eq "weekly") {
                    $dayInput = Read-HostSafe ("每周几执行（Monday..Sunday 或 周一..周日，默认 {0}）" -f (Get-自动更新默认星期))
                }
                启用自动更新 -Mode $modeNormalized -At $atInput -DayOfWeek $dayInput
            }
            "2" { 禁用自动更新 }
            "3" { 查看自动更新状态 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function MCP菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== MCP 服务 ==="
        Write-Host "1) 新增 MCP 服务"
        Write-Host "2) 卸载 MCP 服务"
        Write-Host "3) 同步 MCP 配置"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
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
        Write-Host "4) 打开配置"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
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
        Write-Host "1) 一键工作流"
        Write-Host "2) 自动更新设置"
        Write-Host "3) 解除关联"
        Write-Host "4) 清理备份"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { Invoke-Workflow @() }
            "2" { 自动更新设置 }
            "3" { 解除关联 }
            "4" { 清理备份 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 帮助 {
    @"
Skills 管理器（中文菜单）

推荐使用顺序：
  1) 浏览技能：查看当前已接入来源中的可用技能
  2) 选择安装 / 粘贴命令导入：把技能加入白名单
  3) 重建并同步：重建 agent/ 并同步到 targets
  4) 更新上游：拉取上游后重建并同步
  5) 目标仓审查：生成审查包并应用建议

菜单分组：
  - MCP 服务：新增、卸载、同步 MCP
  - 技能库管理：新增/删除技能库、生成锁文件、打开配置
  - 更多：一键工作流、自动更新设置、解除关联、清理备份

主要功能说明：
  - 浏览技能：列出当前已接入技能库中的可用技能；只查看，不改配置
  - 选择安装：从当前来源中勾选技能，写入 mappings 白名单
  - 粘贴命令导入：解析 add / npx 命令；支持批量导入并自动构建生效
  - 卸载：从 mappings 移除技能；必要时清理 imports、legacy manual 目录和 overrides 备份
  - 新增技能库：向 vendors 写入仓库地址并初始化；留空则只初始化已配置 vendors
  - 删除技能库：移除 vendors 仓库；可选择保留已安装技能并转为 manual
  - 更新上游：拉取 vendor/imports 上游内容；保留本地改动，然后重建并同步
  - 重建并同步：使用当前本地配置重建输出并同步到 targets
  - 锁定：生成 skills.lock.json，记录当前 vendor/import commit
  - 清理无效映射：删除 mappings 中已失效项（源目录不存在或缺少标记文件）
  - 安装MCP：向 skills.json 登记 MCP 服务（stdio / sse / http），并自动同步
  - 卸载MCP：从 skills.json 移除 MCP 服务，并自动同步
  - 同步MCP：只同步 MCP 配置，不构建 skills
  - 一键工作流：按场景执行多步骤编排；支持 `--list`、`--no-prompt`、`--continue-on-error`
  - 目标仓审查：维护需求上下文、目标仓列表、审查包生成和建议应用
  - 自动更新设置：配置本机计划任务，按 daily/weekly + HH:mm 自动执行“更新 + 同步MCP”
  - 解除关联：移除 link 模式下创建的目录关联
  - 清理备份：删除仓库内 *.bak.* 文件和 .bak 目录（排除 vendor / agent / imports / .git）

说明：
  - 手动更新会访问上游仓库；如果你只想让本地改动重新输出，请用“构建并生效”。
  - 命令导入安装会先预检仓库可达性和技能路径，再执行导入。
  - 命令导入安装会自动补全 owner/repo URL；若技能不唯一，会提示候选路径。
  - 从技能库选择安装更适合浏览后再批量勾选；命令导入安装更适合直接粘贴已有命令。

命令行：
  .\skills.ps1 发现
  .\skills.ps1 发现技能
  .\skills.ps1 命令导入安装
  .\skills.ps1 安装
  .\skills.ps1 从技能库选择安装
  .\skills.ps1 卸载
  .\skills.ps1 卸载技能
  .\skills.ps1 新增技能库
  .\skills.ps1 删除技能库
  .\skills.ps1 add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]
  .\skills.ps1 npx "skills add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
  .\skills.ps1 npx "add-skill <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
  .\skills.ps1 一键 --list
  .\skills.ps1 一键 新手
  .\skills.ps1 一键 维护 --continue-on-error
  .\skills.ps1 一键 审查 --no-prompt
  .\skills.ps1 workflow all --no-prompt
  .\skills.ps1 更新
  .\skills.ps1 更新上游并重建
  .\skills.ps1 更新 -Plan
  .\skills.ps1 更新 -Upgrade
  .\skills.ps1 构建生效
  .\skills.ps1 构建并生效
  .\skills.ps1 锁定
  .\skills.ps1 生成锁文件
  .\skills.ps1 清理无效映射 [--yes] [--no-build]
  .\skills.ps1 prune-invalid-mappings [--yes] [--no-build]
  .\skills.ps1 解除关联
  .\skills.ps1 清理备份
  .\skills.ps1 自动更新设置
  .\skills.ps1 安装MCP <name> -- <command> [args...]          （推荐）
  .\skills.ps1 安装MCP <name> --cmd <command> [--arg <arg>...] （兼容）
  .\skills.ps1 安装MCP <name> --transport http --url <url> [--bearer-token-env-var <ENV>] 
  .\skills.ps1 卸载MCP <name>
  .\skills.ps1 同步MCP（可选：手动兜底）
  .\skills.ps1 审查目标 需求设置
  .\skills.ps1 审查目标 需求查看
  .\skills.ps1 审查目标 需求结构化 --profile <file>
  .\skills.ps1 审查目标 扫描 [--target <name>] [--out <dir>] [--force]
  .\skills.ps1 审查目标 发现新技能 [--query <text>] [--out <dir>] [--force]
  .\skills.ps1 审查目标 状态
  .\skills.ps1 审查目标 预检 --run-id <run-id>
  .\skills.ps1 审查目标 预检 --recommendations <file>
  .\skills.ps1 审查目标 修改 <name> <path>
  .\skills.ps1 审查目标 删除 <name>
  .\skills.ps1 审查目标 应用确认 --recommendations <file> [--allow-stale-snapshot] [--stale-ack "<token>"]
  .\skills.ps1 审查目标 应用 --recommendations <file> [--dry-run-ack "我知道未落盘"] [--allow-stale-snapshot] [--stale-ack "<token>"]
  .\skills.ps1 审查目标 应用 --recommendations <file> --apply --yes [--add-indexes "1,3"] [--remove-indexes "2"] [--mcp-add-indexes "1"] [--mcp-remove-indexes "2"] [--allow-stale-snapshot] [--stale-ack "<token>"]
  .\skills.ps1 doctor [--json] [--fix] [--dry-run-fix] [--strict] [--strict-perf] [--threshold-ms <ms>]
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

过滤语法（批量安装/卸载/发现命令）：
  - 多关键词：空格分隔，AND 过滤（如：docx pdf）
  - 正则：用 /.../ 包裹（如：/docx|pdf/）

本地技能：
  - add/npx 未指定 --skill 时仅新增技能库（vendor），不会自动安装整库技能。
  - add/npx 显式指定 --skill 时默认落入 imports（mode=manual），可用 --mode vendor 改为 vendor 管理。
  - manual/ 仅用于旧数据兼容；自定义改动请放入 overrides/。
  - “命令导入安装”支持多行输入 add / npx skills add / npx add-skill。
  - `安装` / `卸载` / `更新` / `构建生效` / `锁定` 等旧命令仍可使用。

目标仓审查：
  - 用户基本需求是全局长期上下文；目标仓是项目级上下文。外层 AI 必须同时基于两者判断技能保留、卸载与新增。
  - `发现新技能` 是不绑定目标仓的 profile-only 模式，复用同一套审查包、提示词、recommendations.json、dry-run/apply 流程。
  - 启动审查流程后，外层 AI 可以在本次流程内自主联网研究；联网不等于自动安装。
  - 设置用户基本需求后会自动进入结构化导入流程；回车使用默认路径 `reports\skill-audit\user-profile.structured.json`，不存在时会自动生成草稿文件。
  - 已内置“外层 AI 审查提示词”；生成审查包时会输出运行态 `outer-ai-prompt.md`，优先把它交给外层 AI，而不是只交 `ai-brief.md`。
  - 运行态 `ai-brief.md` / `outer-ai-prompt.md` 属于审查包产物；如需改默认提示词，请改 `src/Commands/AuditTargets.ps1` 或 `overrides/audit-outer-ai-prompt.md`，不要直接手改 run 目录产物。
  - 外层 AI 应先写完并自检 `recommendations.json`（schema、占位符、双理由、真实来源），再进入 dry-run。
  - `应用确认` 是单入口两阶段流程：先 dry-run，再要求输入确认口令 `APPLY <run-id>` 才执行落盘。
  - `应用` 默认只做 dry-run，且需显式确认口令 `我知道未落盘`；只有 `--apply --yes` 才会真正执行选中的新增/卸载。
  - 建议先执行 `预检`：会提前检查 `stale_snapshot` 与提示词契约版本，避免“先研究后阻断”。
  - `应用`/`应用确认` 会校验同目录 `installed-skills.json` 快照与当前 live mappings 指纹；若快照过期（stale_snapshot）会阻断并要求先重新 `审查目标 扫描`。
  - 仅在你明确接受风险时可加 `--allow-stale-snapshot` 跳过该阻断（报告会标记 stale 风险）。
  - 使用 `--allow-stale-snapshot` 时会触发红色警告并要求二次确认口令；非交互环境请用 `--stale-ack "<token>"` 提前传入。
  - `--out` 若指向已存在且非空目录，默认阻断，防止覆盖旧审查包；如确需复用，显式追加 `--force`。
  - 若路径里仍包含 `<run-id>` 这类占位符，命令会直接阻断并给出可用 run-id 提示。
  - `状态` 可查看最近一次 `apply-report.json` 的 `mode/success/persisted/changed_counts`。
  - 执行前会分别列出“技能新增/卸载”和“MCP 新增/卸载”四份带序号清单；dry-run 后向用户汇报时必须沿用原序号，并同时展示用户需求 / 目标仓两条简短依据。
  - `--add-indexes` / `--remove-indexes` 作用于技能清单；`--mcp-add-indexes` / `--mcp-remove-indexes` 作用于 MCP 清单；四份清单独立编号。

提示：如遇 PowerShell 脚本执行被拦，可在当前窗口临时放开：
  Set-ExecutionPolicy -Scope Process Bypass
"@ | Write-Host
}

function 审查目标菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 目标仓审查 ==="
        Write-Host "1) 查看需求"
        Write-Host "2) 编辑需求"
        Write-Host "3) 目标仓列表"
        Write-Host "4) 生成审查包"
        Write-Host "5) 应用建议（推荐）"
        Write-Host "6) 查看最近状态"
        Write-Host "7) 新增目标仓"
        Write-Host "8) 修改目标仓"
        Write-Host "9) 删除目标仓"
        Write-Host "10) 导入结构化需求"
        Write-Host "11) 初始化审查配置"
        Write-Host "12) 查看 AI 提示词"
        Write-Host "13) 编辑 AI 提示词"
        Write-Host "14) 直接执行建议（高级）"
        Write-Host "15) 发现新技能（不绑定目标仓）"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("profile-show") }
            "2" { Invoke-AuditTargetsCommand @("profile-set") }
            "3" { Invoke-AuditTargetsCommand @("list") }
            "4" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                Write-Host "留空将扫描全部 enabled 目标仓。"
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要扫描的目标仓（输入 0 或直接回车=全部 enabled）" `
                    "未解析到有效序号，已取消生成审查包。"
                if ($selection.canceled) {
                    Invoke-AuditTargetsCommand @("scan")
                    continue
                }
                $picked = @($selection.items)
                if ($picked.Count -eq 0) {
                    Invoke-AuditTargetsCommand @("scan")
                }
                else {
                    Invoke-AuditTargetsCommand @("scan", "--target", [string]$picked[0].name)
                }
            }
            "5" {
                $path = Read-HostSafe "recommendations 文件路径"
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("apply-flow", "--recommendations", $path)
                }
            }
            "6" { Invoke-AuditTargetsCommand @("status") }
            "7" {
                $name = Read-HostSafe "目标仓名称"
                $path = Read-HostSafe "目标仓路径"
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("add", $name, $path)
                }
            }
            "8" {
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
            "9" {
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
            "10" {
                $defaultPath = Get-AuditStructuredProfileDefaultPath
                $profile = Read-HostSafe ("请输入结构化 profile 文件路径（回车使用默认：{0}）" -f $defaultPath)
                if ([string]::IsNullOrWhiteSpace($profile)) {
                    Invoke-AuditTargetsCommand @("profile-structure")
                }
                else {
                    Invoke-AuditTargetsCommand @("profile-structure", "--profile", $profile)
                }
            }
            "11" { Invoke-AuditTargetsCommand @("init") }
            "12" { Show-AuditOuterAiPromptTemplate }
            "13" { Edit-AuditOuterAiPromptTemplate }
            "14" {
                $path = Read-HostSafe "recommendations 文件路径"
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("apply", "--recommendations", $path, "--apply", "--yes")
                }
            }
            "15" {
                $query = Read-HostSafe "发现查询（可留空）"
                if ([string]::IsNullOrWhiteSpace($query)) {
                    Invoke-AuditTargetsCommand @("discover-skills")
                }
                else {
                    Invoke-AuditTargetsCommand @("discover-skills", "--query", $query)
                }
            }
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
        $c = Read-HostSafe "请选择"
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
