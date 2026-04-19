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
    Write-Host ("自动更新：已启用（每周五 20:00，本机时间）")
    Write-Host ("任务名：{0}" -f $taskName)
    Write-Host ("状态：{0}" -f $state)
    Write-Host ("下次运行：{0}" -f $nextRun)
    Write-Host ("上次运行：{0}" -f $lastRun)
}
function 启用自动更新 {
    $taskName = Get-自动更新任务名
    $runnerPath = Get-自动更新脚本路径
    Need (Test-Path $runnerPath) ("缺少自动更新脚本：{0}" -f $runnerPath)
    Need (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    Need (Get-Command New-ScheduledTaskAction -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    Need (Get-Command powershell -ErrorAction SilentlyContinue) "未找到 powershell 可执行文件。"

    if (Skip-IfDryRun "启用自动更新计划任务") { return }

    $pwsh = (Get-Command powershell -ErrorAction Stop).Source
    $args = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath)
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $args -WorkingDirectory $Root
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At "20:00"
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "skills-manager 每周五 20:00 自动执行 更新 + 同步MCP" -Force | Out-Null
    Write-Host "✅ 已启用自动更新：每周五 20:00（本机时间）。"
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
        Write-Host "目标：每周五 20:00 自动执行【更新 + 同步MCP】"
        查看自动更新状态
        Write-Host "1) 启用（每周五 20:00）"
        Write-Host "2) 禁用"
        Write-Host "3) 查看状态"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { 启用自动更新 }
            "2" { 禁用自动更新 }
            "3" { 查看自动更新状态 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 帮助 {
    @"
Skills 管理器（中文菜单）

推荐使用顺序：
  1) 接入来源：新增技能库，或粘贴 add / npx 命令导入单个技能
  2) 发现：查看已接入技能库中的可用技能
  3) 安装：
     - 命令导入安装：粘贴一条或多条 add / npx skills add / npx add-skill 命令
     - 从技能库选择安装：从已接入技能库中勾选技能，写入 mappings 白名单
  4) 构建并生效：重建 agent/，并同步到 targets
  5) 更新：拉取上游后重建并同步

主要功能说明：
  - 发现：列出当前技能库中的可用技能；只查看，不改配置
  - 命令导入安装：解析 add / npx 命令；支持批量导入并自动构建生效
  - 从技能库选择安装：勾选技能，追加到 mappings 并自动构建生效
  - 卸载：从 mappings 移除技能；必要时清理 imports、legacy manual 目录和 overrides 备份
  - 新增技能库：向 vendors 写入仓库地址并初始化；留空则只初始化已配置 vendors
  - 删除技能库：移除 vendors 仓库；可选择保留已安装技能并转为 manual
  - 更新：拉取 vendor/imports 上游内容；保留本地改动，然后重建并同步
  - 构建并生效：使用当前本地配置与文件源重建输出并同步；可配合 -Locked 校验锁文件
  - 锁定：生成 skills.lock.json，记录当前 vendor/import commit
  - 安装MCP：向 skills.json 登记 MCP 服务（stdio / sse / http），并自动同步
  - 卸载MCP：从 skills.json 移除 MCP 服务，并自动同步
  - 同步MCP：只同步 MCP 配置，不构建 skills
  - 审查目标：登记目标仓、生成审查包、应用外层 AI 写入的 recommendations.json
  - 自动更新设置：配置本机计划任务，每周五 20:00 自动执行“更新 + 同步MCP”
  - 打开配置：打开 skills.json
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
  .\skills.ps1 更新
  .\skills.ps1 更新上游并重建
  .\skills.ps1 更新 -Plan
  .\skills.ps1 更新 -Upgrade
  .\skills.ps1 构建生效
  .\skills.ps1 构建并生效
  .\skills.ps1 锁定
  .\skills.ps1 生成锁文件
  .\skills.ps1 打开配置
  .\skills.ps1 解除关联
  .\skills.ps1 清理备份
  .\skills.ps1 自动更新设置
  .\skills.ps1 安装MCP <name> -- <command> [args...]          （推荐）
  .\skills.ps1 安装MCP <name> --cmd <command> [--arg <arg>...] （兼容）
  .\skills.ps1 安装MCP <name> --transport http --url <url> [--bearer-token-env-var <ENV>] 
  .\skills.ps1 卸载MCP <name>
  .\skills.ps1 同步MCP（可选：手动兜底）
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

提示：如遇 PowerShell 脚本执行被拦，可在当前窗口临时放开：
  Set-ExecutionPolicy -Scope Process Bypass
"@ | Write-Host
}

function 菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== Skills 管理器 ==="
        Write-Host "技能操作"
        Write-Host "1) 发现技能（浏览已接入技能库）"
        Write-Host "2) 命令导入安装（粘贴一条或多条 add / npx 命令）"
        Write-Host "3) 从技能库选择安装（勾选后写入白名单）"
        Write-Host "4) 卸载技能（移除白名单并清理相关本地项）"
        Write-Host "5) 构建并生效（按当前配置重建并同步）"
        Write-Host "6) 更新上游并重建（拉取后重建并同步）"
        Write-Host ""
        Write-Host "来源与配置"
        Write-Host "7) 新增技能库（写入 vendors 并初始化）"
        Write-Host "8) 删除技能库（移除 vendor 并重建）"
        Write-Host "9) 打开配置（skills.json）"
        Write-Host "10) 生成锁文件（skills.lock.json）"
        Write-Host ""
        Write-Host "MCP 管理"
        Write-Host "11) 安装MCP（登记 MCP 服务并自动同步）"
        Write-Host "12) 卸载MCP（移除 MCP 服务并自动同步）"
        Write-Host "13) 同步MCP（仅重新同步 MCP 配置）"
        Write-Host ""
        Write-Host "维护"
        Write-Host "14) 解除关联（仅 link 模式需要）"
        Write-Host "15) 清理备份（删除仓库内 *.bak.* / .bak，排除 vendor/agent/imports/.git）"
        Write-Host "16) 自动更新设置（每周五 20:00 自动执行 更新 + 同步MCP）"
        Write-Host "98) 帮助"
        Write-Host "0) 退出"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { 发现 }
            "2" { 命令导入安装 }
            "3" { 安装 }
            "4" { 卸载 }
            "5" { 构建生效 }
            "6" { 更新 }
            "7" { 新增技能库 }
            "8" { 删除技能库 }
            "9" { 打开配置 }
            "10" { 锁定 }
            "11" { 安装MCP }
            "12" { 卸载MCP }
            "13" { 同步MCP }
            "14" { 解除关联 }
            "15" { 清理备份 }
            "16" { 自动更新设置 }
            "98" { 帮助 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}
