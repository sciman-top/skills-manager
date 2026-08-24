# Main Entry Point
# ----------------
# This file is used to assemble the final script.
# It includes the main dispatch logic.

if ($MyInvocation.InvocationName -ne '.') {
    try {
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
            "add" { Add-ImportFromArgs (Merge-FilterAndArgs $Filter $args) }
            "npx" { Add-ImportFromArgs (Get-AddTokensFromNpx (Merge-FilterAndArgs $Filter $args)) }
            "安装" { 安装 }
            "卸载" { 卸载 (Merge-FilterAndArgs $Filter $args) }
            "选择" { 选择 }
            "构建生效" { 构建生效 -SkillProfile $SkillProfile -AllowUnverifiedProjection:$AllowUnverifiedHostProjection -SkipHostProjection:$SkipHostProjection }
            "更新" { 更新 }
            "check-updates" { $result = Invoke-CheckUpdatesCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output } }
            "锁定" { 锁定 }
            "验证锁定" { 验证锁定 }
            "verify-lock" { 验证锁定 }
            "清理无效映射" { 清理无效映射 (Merge-FilterAndArgs $Filter $args) }
            "prune-invalid-mappings" { 清理无效映射 (Merge-FilterAndArgs $Filter $args) }
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
            "同步MCP" {
                $mcpOptions = Parse-McpSyncPlanOptions (Merge-FilterAndArgs $Filter $args)
                if ($RunPlan -or [bool]$mcpOptions.plan) { Invoke-McpSyncPlan -Json:([bool]$mcpOptions.json) -OutPath ([string]$mcpOptions.out_path) }
                else { 同步MCP }
            }
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
            "mcp-sync" {
                $mcpOptions = Parse-McpSyncPlanOptions (Merge-FilterAndArgs $Filter $args)
                if ($RunPlan -or [bool]$mcpOptions.plan) { Invoke-McpSyncPlan -Json:([bool]$mcpOptions.json) -OutPath ([string]$mcpOptions.out_path) }
                else { 同步MCP }
            }
            "MCP配置" { Invoke-McpProfileCommand (Merge-FilterAndArgs $Filter $args) }
            "mcp-profile" { Invoke-McpProfileCommand (Merge-FilterAndArgs $Filter $args) }
            "审查目标" { Invoke-AuditTargetsCommand (Merge-FilterAndArgs $Filter $args) }
            "audit-targets" { Invoke-AuditTargetsCommand (Merge-FilterAndArgs $Filter $args) }
            "能力清单" { $result = Invoke-CapabilityInventoryCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            "capability-inventory" { $result = Invoke-CapabilityInventoryCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            "规则审查" { $result = Invoke-RuleAuditCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            "rule-audit" { $result = Invoke-RuleAuditCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            "规则全域审查" { $result = Invoke-RuleEstateAuditCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            "rule-estate-audit" { $result = Invoke-RuleEstateAuditCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output $result.output } else { Write-Host $result.output }; if ($result.exit_code -ne 0) { exit $result.exit_code } }
            "规则全域计划" { $result=Invoke-RuleEstatePlanCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "rule-estate-plan" { $result=Invoke-RuleEstatePlanCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "规则全域应用" { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-RuleEstateApplyCommand $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "rule-estate-apply" { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-RuleEstateApplyCommand $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "规则全域回滚" { $result=Invoke-RuleEstateRollbackCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "rule-estate-rollback" { $result=Invoke-RuleEstateRollbackCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "全局规则检查" { $result=Invoke-GlobalRuleCommand check (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "global-rules-check" { $result=Invoke-GlobalRuleCommand check (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "全局规则计划" { $result=Invoke-GlobalRuleCommand plan (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "global-rules-plan" { $result=Invoke-GlobalRuleCommand plan (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "全局规则应用" { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-GlobalRuleCommand apply $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "global-rules-apply" { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-GlobalRuleCommand apply $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "全局规则回滚" { $result=Invoke-GlobalRuleCommand rollback (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "global-rules-rollback" { $result=Invoke-GlobalRuleCommand rollback (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "规则计划" { $result=Invoke-RulePlanCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "rule-plan" { $result=Invoke-RulePlanCommand (Merge-FilterAndArgs $Filter $args);if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "规则应用" { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-RuleApplyCommand $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "rule-apply" { $tokens=Merge-FilterAndArgs $Filter $args;if($RunPlan){$tokens=@('--plan')+@($tokens)};$result=Invoke-RuleApplyCommand $tokens;if($result.json){Write-Output $result.output}else{Write-Host $result.output};if($result.exit_code -ne 0){exit $result.exit_code} }
            "打开配置" { 打开配置 }
            "解除关联" { 解除关联 }
            "清理备份" { 清理备份 }
            "帮助" { 帮助 }
            "help" { 帮助 }
            "--help" { 帮助 }
            "-h" { 帮助 }
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
