#requires -Version 7.0
param(
    [ValidateSet("menu", "初始化", "新增技能库", "删除技能库", "发现", "发现技能", "命令导入安装", "安装", "从技能库选择安装", "卸载", "卸载技能", "选择", "构建生效", "构建并生效", "更新", "更新上游并重建", "锁定", "生成锁文件", "验证锁定", "verify-lock", "清理无效映射", "打开配置", "解除关联", "清理备份", "自动更新设置", "帮助", "help", "--help", "-h", "doctor", "add", "npx", "安装MCP", "卸载MCP", "同步MCP", "MCP配置", "mcp-profile", "mcp-install", "mcp-uninstall", "mcp-sync", "审查目标", "audit-targets", "能力清单", "capability-inventory", "plugin-inventory", "plugin-lint", "plugin-export", "plugin-eval", "规则审查", "rule-audit", "规则全域审查", "rule-estate-audit", "规则全域计划", "rule-estate-plan", "规则全域应用", "rule-estate-apply", "规则全域回滚", "rule-estate-rollback", "规则计划", "rule-plan", "规则应用", "rule-apply", "一键", "workflow", "prune-invalid-mappings")]
    [string]$Cmd = "menu",
    [string]$Filter = "",
    [switch]$DryRun,
    [switch]$Locked,
    [switch]$Plan,
    [switch]$Upgrade,
    [switch]$AllowUnverifiedHostProjection,
    [switch]$SkipHostProjection
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
}
catch {}
