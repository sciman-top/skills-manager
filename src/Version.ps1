#requires -Version 7.0
param(
    [ValidateSet("menu", "初始化", "新增技能库", "删除技能库", "发现", "发现技能", "命令导入安装", "安装", "从技能库选择安装", "卸载", "卸载技能", "选择", "构建生效", "构建并生效", "更新", "更新上游并重建", "check-updates", "锁定", "生成锁文件", "验证锁定", "verify-lock", "清理无效映射", "打开配置", "解除关联", "清理备份", "帮助", "help", "--help", "-h", "doctor", "add", "npx", "迁移", "migration", "迁移解锁", "migration-unlock", "迁移应用", "migration-apply", "安装MCP", "卸载MCP", "同步MCP", "MCP配置", "mcp-profile", "mcp-install", "mcp-uninstall", "mcp-sync", "审查目标", "audit-targets", "能力清单", "capability-inventory", "规则审查", "rule-audit", "规则全域审查", "rule-estate-audit", "规则全域计划", "rule-estate-plan", "规则全域应用", "rule-estate-apply", "规则全域回滚", "rule-estate-rollback", "全局规则检查", "global-rules-check", "全局规则计划", "global-rules-plan", "全局规则应用", "global-rules-apply", "全局规则回滚", "global-rules-rollback", "规则计划", "rule-plan", "规则应用", "rule-apply", "prune-invalid-mappings")]
    [Parameter(Position = 0)]
    [string]$Cmd = "menu",
    [string]$Filter = "",
    [switch]$DryRun,
    [switch]$Locked,
    [Alias('Plan')]
    [switch]$RunPlan,
    [switch]$Upgrade,
    [string]$SkillProfile = "",
    [switch]$AllowUnverifiedHostProjection,
    [switch]$SkipHostProjection,
    [Alias('mode')]
    [string]$MigrationMode = '',
    [Alias('out')]
    [string]$MigrationOut = '',
    [Alias('force')]
    [switch]$MigrationForce,
    [Alias('json')]
    [switch]$MigrationJson,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs = @()
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
}
catch {}
