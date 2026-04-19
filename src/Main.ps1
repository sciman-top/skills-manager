# Main Entry Point
# ----------------
# This file is used to assemble the final script.
# It includes the main dispatch logic.

if ($MyInvocation.InvocationName -ne '.') {
    try {
        switch ($Cmd) {
            "menu" { 菜单 }
            "初始化" { 初始化 }
            "新增技能库" { 新增技能库 }
            "删除技能库" { 删除技能库 }
            "发现" { 发现 }
            "发现技能" { 发现 }
            "命令导入安装" { 命令导入安装 }
            "add" { Add-ImportFromArgs (Merge-FilterAndArgs $Filter $args) }
            "npx" { Add-ImportFromArgs (Get-AddTokensFromNpx (Merge-FilterAndArgs $Filter $args)) }
            "安装" { 安装 }
            "从技能库选择安装" { 安装 }
            "卸载" { 卸载 }
            "卸载技能" { 卸载 }
            "选择" { 选择 }
            "构建生效" { 构建生效 }
            "构建并生效" { 构建生效 }
            "更新" { 更新 }
            "更新上游并重建" { 更新 }
            "锁定" { 锁定 }
            "生成锁文件" { 锁定 }
            "安装MCP" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                安装MCP $mcpTokens
            }
            "卸载MCP" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                卸载MCP $mcpTokens
            }
            "同步MCP" { 同步MCP }
            "mcp-install" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                安装MCP $mcpTokens
            }
            "mcp-uninstall" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                卸载MCP $mcpTokens
            }
            "mcp-sync" { 同步MCP }
            "审查目标" { Invoke-AuditTargetsCommand (Merge-FilterAndArgs $Filter $args) }
            "audit-targets" { Invoke-AuditTargetsCommand (Merge-FilterAndArgs $Filter $args) }
            "打开配置" { 打开配置 }
            "解除关联" { 解除关联 }
            "清理备份" { 清理备份 }
            "自动更新设置" { 自动更新设置 }
            "帮助" { 帮助 }
            "doctor" {
                $doctorTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $doctorTokens += $Filter }
                $doctorTokens += @($args)
                $doctorResult = Invoke-Doctor $doctorTokens
                $strictRequested = @($doctorTokens | Where-Object { ([string]$_).Trim().ToLowerInvariant() -eq "--strict" }).Count -gt 0
                if ($strictRequested -and $doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                    exit 2
                }
            }
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($env:SKILLS_DEBUG_STACK -eq "1") {
            $stack = $_.ScriptStackTrace
            if (-not [string]::IsNullOrWhiteSpace($stack)) {
                Write-Host ("[DEBUG_STACK] " + $stack) -ForegroundColor DarkYellow
            }
        }
        Log ("未处理错误：{0}" -f $msg) "ERROR"
        Write-Host ("❌ 发生错误：{0}" -f $msg) -ForegroundColor Red
        exit 1
    }
}
