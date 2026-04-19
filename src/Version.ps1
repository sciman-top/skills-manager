#requires -Version 5.1
param(
    [ValidateSet("menu", "初始化", "新增技能库", "删除技能库", "发现", "发现技能", "命令导入安装", "安装", "从技能库选择安装", "卸载", "卸载技能", "选择", "构建生效", "构建并生效", "更新", "更新上游并重建", "锁定", "生成锁文件", "打开配置", "解除关联", "清理备份", "自动更新设置", "帮助", "doctor", "add", "npx", "安装MCP", "卸载MCP", "同步MCP", "mcp-install", "mcp-uninstall", "mcp-sync", "审查目标", "audit-targets")]
    [string]$Cmd = "menu",
    [string]$Filter = "",
    [switch]$DryRun,
    [switch]$Locked,
    [switch]$Plan,
    [switch]$Upgrade
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
}
catch {}
