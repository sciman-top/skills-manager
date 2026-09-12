# Main Entry Point
# ----------------
# This file is used to assemble the final script.
# It includes the main dispatch logic.

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Command-specific parsers own all remaining tokens, including --long-options.
        $args = @($CommandArgs)
        # These top-level aliases prevent PowerShell from treating --out as an
        # abbreviated common parameter. Restore them for every command-specific
        # parser so existing --mode/--out/--force/--json contracts remain intact.
        if (-not [string]::IsNullOrWhiteSpace($MigrationMode)) { $args += @('--mode', $MigrationMode) }
        if (-not [string]::IsNullOrWhiteSpace($MigrationOut)) { $args += @('--out', $MigrationOut) }
        if ($MigrationForce) { $args += '--force' }
        if ($MigrationJson) { $args += '--json' }
        $deprecatedCommandAliases = @{
            "发现技能" = "发现"
            "从技能库选择安装" = "安装"
            "卸载技能" = "卸载"
            "构建并生效" = "构建生效"
            "更新上游并重建" = "更新"
            "生成锁文件" = "锁定"
        }
        if ($deprecatedCommandAliases.ContainsKey($Cmd)) {
            $canonicalCmd = [string]$deprecatedCommandAliases[$Cmd]
            Write-Warning ("命令别名 '{0}' 已弃用；请改用 '{1}'。" -f $Cmd, $canonicalCmd)
            $Cmd = $canonicalCmd
        }
        switch ($Cmd) {
            "menu" { 菜单 }
            "初始化" { 初始化 }
            "新增技能库" { 新增技能库 }
            "删除技能库" { 删除技能库 }
            "发现" { 发现 }
            "命令导入安装" { 命令导入安装 }
            "add" { if (-not (Add-ImportFromArgs (Merge-FilterAndArgs $Filter $args))) { exit 1 } }
            "npx" { if (-not (Add-ImportFromArgs (Get-AddTokensFromNpx (Merge-FilterAndArgs $Filter $args)))) { exit 1 } }
            { $_ -in @("迁移", "migration") } { Invoke-MigrationCommand $args }
            { $_ -in @("迁移解锁", "migration-unlock") } { Invoke-MigrationUnlockCommand $args }
            { $_ -in @("迁移应用", "migration-apply") } { Invoke-MigrationApplyCommand $args }
            "安装" { 安装 }
            "卸载" { 卸载 (Merge-FilterAndArgs $Filter $args) }
            "选择" { 选择 }
            "构建生效" { 构建生效 -SkillProfile $SkillProfile -AllowUnverifiedProjection:$AllowUnverifiedHostProjection -SkipHostProjection:$SkipHostProjection }
            "更新" { 更新 }
            "check-updates" { $result = Invoke-CheckUpdatesCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output } }
            { $_ -in @("发行更新", "release-update") } { $result = Invoke-ReleaseUpdateCommand $args; if ($result -is [string]) { Write-Output $result } }
            { $_ -in @("发行更新调度", "release-update-schedule") } { $result = Invoke-ReleaseUpdateScheduleCommand $args; if ($result -is [string]) { Write-Output $result } }
            "锁定" { 锁定 }
            { $_ -in @("验证锁定", "verify-lock") } { 验证锁定 }
            { $_ -in @("清理无效映射", "prune-invalid-mappings") } { 清理无效映射 (Merge-FilterAndArgs $Filter $args) }
            { $_ -in @("安装MCP", "mcp-install") } {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                安装MCP $mcpTokens
            }
            { $_ -in @("卸载MCP", "mcp-uninstall") } {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                卸载MCP $mcpTokens
            }
            { $_ -in @("同步MCP", "mcp-sync") } {
                $mcpOptions = Parse-McpSyncPlanOptions (Merge-FilterAndArgs $Filter $args)
                if ($RunPlan -or [bool]$mcpOptions.plan) { Invoke-McpSyncPlan -Json:([bool]$mcpOptions.json) -OutPath ([string]$mcpOptions.out_path) }
                else { 同步MCP }
            }
            { $_ -in @("MCP配置", "mcp-profile") } { Invoke-McpProfileCommand (Merge-FilterAndArgs $Filter $args) }
            { $_ -in @("审查目标", "audit-targets") } { Invoke-AuditTargetsCommand (Merge-FilterAndArgs $Filter $args) }
            { $_ -in @("能力清单", "capability-inventory") } { $result = Invoke-CapabilityInventoryCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            { $_ -in @("规则审查", "rule-audit") } { $result = Invoke-RuleAuditCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            { $_ -in @("规则全域审查", "rule-estate-audit") } { $result = Invoke-RuleEstateAuditCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            { $_ -in @("规则全域计划", "rule-estate-plan") } { $result=Invoke-RuleEstatePlanCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("规则全域应用", "rule-estate-apply") } { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-RuleEstateApplyCommand $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("规则全域回滚", "rule-estate-rollback") } { $result=Invoke-RuleEstateRollbackCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("全局规则检查", "global-rules-check") } { $result=Invoke-GlobalRuleCommand check (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("全局规则计划", "global-rules-plan") } { $result=Invoke-GlobalRuleCommand plan (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("全局规则应用", "global-rules-apply") } { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-GlobalRuleCommand apply $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("全局规则回滚", "global-rules-rollback") } { $result=Invoke-GlobalRuleCommand rollback (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("规则计划", "rule-plan") } { $result=Invoke-RulePlanCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            { $_ -in @("规则应用", "rule-apply") } { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-RuleApplyCommand $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "打开配置" { 打开配置 }
            "解除关联" { 解除关联 }
            "清理备份" { 清理备份 }
            { $_ -in @("帮助", "help", "--help", "-h") } { 帮助 }
            "doctor" {
                $doctorTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $doctorTokens += $Filter }
                $doctorTokens += @($args)
                $doctorResult = Invoke-Doctor $doctorTokens
                # --json 契约：JSON 必须走 stdout（Write-Host 会被重定向/管道丢弃）。
                if (@($doctorTokens | Where-Object { ([string]$_).Trim().ToLowerInvariant() -eq "--json" }).Count -gt 0) {
                    Write-Output ($doctorResult | ConvertTo-Json -Depth 30)
                }
                $strictRequested = @($doctorTokens | Where-Object { ([string]$_).Trim().ToLowerInvariant() -eq "--strict" }).Count -gt 0
                if ($strictRequested -and $doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                    exit 2
                }
            }
        }
        exit 0
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
