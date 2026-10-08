#requires -Version 7.0
param(
    [ValidateSet("menu", "初始化", "新增技能库", "删除技能库", "发现", "发现技能", "命令导入安装", "安装", "从技能库选择安装", "卸载", "卸载技能", "选择", "构建生效", "构建并生效", "更新", "更新上游并重建", "check-updates", "release-update", "发行更新", "release-update-schedule", "发行更新调度", "锁定", "生成锁文件", "验证锁定", "verify-lock", "清理无效映射", "打开配置", "解除关联", "清理备份", "帮助", "help", "--help", "-h", "doctor", "ai-risk-control", "风险控制", "add", "npx", "迁移", "migration", "迁移解锁", "migration-unlock", "迁移应用", "migration-apply", "安装MCP", "卸载MCP", "同步MCP", "MCP配置", "mcp-profile", "mcp-install", "mcp-uninstall", "mcp-sync", "审查目标", "audit-targets", "ai-coding", "AI编码", "能力清单", "capability-inventory", "规则审查", "rule-audit", "规则全域审查", "rule-estate-audit", "规则全域计划", "rule-estate-plan", "规则全域应用", "rule-estate-apply", "规则全域回滚", "rule-estate-rollback", "全局规则检查", "global-rules-check", "全局规则计划", "global-rules-plan", "全局规则应用", "global-rules-apply", "全局规则回滚", "global-rules-rollback", "规则计划", "rule-plan", "规则应用", "rule-apply", "prune-invalid-mappings")]
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

# --- 惰性库加载器（由 build.ps1 生成；改 src/，勿改此块）---
$script:SkillsLibPackPlan = @{
'menu' = @('Application.HostRegistry.ps1', 'Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.CapabilityInventory.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Application.RuleDiscovery.ps1', 'Application.RuleDiagnostics.ps1', 'Application.RuleAdvisor.ps1', 'Application.RuleAudit.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Application.GlobalRuleProjection.ps1', 'Application.RulePatchGuard.ps1', 'Application.RulePatchExecutor.ps1', 'Commands.Doctor.ps1', 'Commands.AiCoding.ps1', 'Commands.AiRiskControl.ps1', 'Commands.Install.ps1', 'Commands.Update.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1', 'Commands.Migration.ps1', 'Commands.ReleaseUpdate.ps1', 'Commands.Capability.ps1', 'Commands.RuleAudit.ps1', 'Commands.RuleEstate.ps1', 'Commands.GlobalRules.ps1', 'Commands.RulePatch.ps1', 'Commands.AuditTargets.ps1', 'Commands.AuditTargets.Template.ps1', 'Commands.AuditTargets.Snapshot.ps1', 'Commands.AuditTargets.TargetState.ps1', 'Commands.AuditTargets.Plan.ps1', 'Commands.AuditTargets.Bundle.ps1', 'Commands.AuditTargets.Apply.ps1', 'Commands.AuditTargets.Workflow.ps1', 'Commands.AuditTargets.Args.ps1', 'Commands.SkillProjection.ps1')
'初始化' = @('Commands.Install.ps1')
'新增技能库' = @('Commands.Install.ps1')
'删除技能库' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'发现' = @('Commands.Install.ps1')
'命令导入安装' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'add' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'npx' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'迁移' = @('Application.SkillSupply.ps1', 'Commands.Install.ps1', 'Commands.Migration.ps1')
'migration' = @('Application.SkillSupply.ps1', 'Commands.Install.ps1', 'Commands.Migration.ps1')
'迁移解锁' = @('Application.SkillSupply.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Migration.ps1')
'migration-unlock' = @('Application.SkillSupply.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Migration.ps1')
'迁移应用' = @('Application.SkillSupply.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Migration.ps1')
'migration-apply' = @('Application.SkillSupply.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Migration.ps1')
'安装' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'卸载' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'选择' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'构建生效' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'更新' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Update.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'check-updates' = @('Commands.Install.ps1', 'Commands.Update.ps1')
'发行更新' = @('Commands.Install.ps1', 'Commands.ReleaseUpdate.ps1')
'release-update' = @('Commands.Install.ps1', 'Commands.ReleaseUpdate.ps1')
'发行更新调度' = @('Commands.Install.ps1', 'Commands.ReleaseUpdate.ps1')
'release-update-schedule' = @('Commands.Install.ps1', 'Commands.ReleaseUpdate.ps1')
'锁定' = @('Commands.Install.ps1', 'Commands.Update.ps1')
'验证锁定' = @('Commands.Install.ps1', 'Commands.Update.ps1')
'verify-lock' = @('Commands.Install.ps1', 'Commands.Update.ps1')
'清理无效映射' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'prune-invalid-mappings' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'安装MCP' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'mcp-install' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'卸载MCP' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'mcp-uninstall' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'同步MCP' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'mcp-sync' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'MCP配置' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'mcp-profile' = @('Application.SkillProjection.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1')
'审查目标' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Doctor.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1', 'Commands.AuditTargets.ps1', 'Commands.AuditTargets.Template.ps1', 'Commands.AuditTargets.Snapshot.ps1', 'Commands.AuditTargets.TargetState.ps1', 'Commands.AuditTargets.Plan.ps1', 'Commands.AuditTargets.Bundle.ps1', 'Commands.AuditTargets.Apply.ps1', 'Commands.AuditTargets.Workflow.ps1', 'Commands.AuditTargets.Args.ps1', 'Commands.SkillProjection.ps1')
'audit-targets' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Doctor.ps1', 'Commands.Install.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1', 'Commands.AuditTargets.ps1', 'Commands.AuditTargets.Template.ps1', 'Commands.AuditTargets.Snapshot.ps1', 'Commands.AuditTargets.TargetState.ps1', 'Commands.AuditTargets.Plan.ps1', 'Commands.AuditTargets.Bundle.ps1', 'Commands.AuditTargets.Apply.ps1', 'Commands.AuditTargets.Workflow.ps1', 'Commands.AuditTargets.Args.ps1', 'Commands.SkillProjection.ps1')
'ai-coding' = @('Commands.AiCoding.ps1')
'AI编码' = @('Commands.AiCoding.ps1')
'能力清单' = @('Application.SkillProjectionPlanning.ps1', 'Application.CapabilityInventory.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Commands.Install.ps1', 'Commands.Capability.ps1')
'capability-inventory' = @('Application.SkillProjectionPlanning.ps1', 'Application.CapabilityInventory.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Commands.Install.ps1', 'Commands.Capability.ps1')
'规则审查' = @('Application.HostRegistry.ps1', 'Application.RuleDiscovery.ps1', 'Application.RuleDiagnostics.ps1', 'Application.RuleAdvisor.ps1', 'Application.RuleAudit.ps1', 'Commands.Install.ps1', 'Commands.RuleAudit.ps1', 'Commands.AuditTargets.ps1', 'Commands.AuditTargets.Snapshot.ps1')
'rule-audit' = @('Application.HostRegistry.ps1', 'Application.RuleDiscovery.ps1', 'Application.RuleDiagnostics.ps1', 'Application.RuleAdvisor.ps1', 'Application.RuleAudit.ps1', 'Commands.Install.ps1', 'Commands.RuleAudit.ps1', 'Commands.AuditTargets.ps1', 'Commands.AuditTargets.Snapshot.ps1')
'规则全域审查' = @('Application.HostRegistry.ps1', 'Application.RuleDiscovery.ps1', 'Application.RuleDiagnostics.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'rule-estate-audit' = @('Application.HostRegistry.ps1', 'Application.RuleDiscovery.ps1', 'Application.RuleDiagnostics.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'规则全域计划' = @('Application.RuleDiscovery.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'rule-estate-plan' = @('Application.RuleDiscovery.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'规则全域应用' = @('Application.RuleDiscovery.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'rule-estate-apply' = @('Application.RuleDiscovery.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'规则全域回滚' = @('Application.RuleDiscovery.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'rule-estate-rollback' = @('Application.RuleDiscovery.ps1', 'Application.RuleEstateMutation.ps1', 'Commands.Install.ps1', 'Commands.RuleEstate.ps1')
'全局规则检查' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'global-rules-check' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'全局规则计划' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'global-rules-plan' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'全局规则应用' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'global-rules-apply' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'全局规则回滚' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'global-rules-rollback' = @('Application.HostRegistry.ps1', 'Application.GlobalRuleProjection.ps1', 'Commands.Install.ps1', 'Commands.GlobalRules.ps1')
'规则计划' = @('Application.RuleDiscovery.ps1', 'Commands.Install.ps1', 'Commands.RulePatch.ps1')
'rule-plan' = @('Application.RuleDiscovery.ps1', 'Commands.Install.ps1', 'Commands.RulePatch.ps1')
'规则应用' = @('Application.RuleDiscovery.ps1', 'Application.RulePatchGuard.ps1', 'Application.RulePatchExecutor.ps1', 'Commands.Install.ps1', 'Commands.RulePatch.ps1')
'rule-apply' = @('Application.RuleDiscovery.ps1', 'Application.RulePatchGuard.ps1', 'Application.RulePatchExecutor.ps1', 'Commands.Install.ps1', 'Commands.RulePatch.ps1')
'打开配置' = @('Commands.Install.ps1')
'解除关联' = @('Commands.Install.ps1')
'清理备份' = @('Commands.Install.ps1')
'帮助' = @()
'help' = @()
'--help' = @()
'-h' = @()
'ai-risk-control' = @('Commands.AiRiskControl.ps1', 'Commands.Install.ps1')
'风险控制' = @('Commands.AiRiskControl.ps1', 'Commands.Install.ps1')
'doctor' = @('Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Commands.Doctor.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ProfileAndSafety.ps1')
'发现技能' = @('Commands.Install.ps1')
'从技能库选择安装' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'卸载技能' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'构建并生效' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'更新上游并重建' = @('Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Commands.Install.ps1', 'Commands.Update.ps1', 'Commands.Mcp.ps1', 'Commands.SkillProjection.ps1')
'生成锁文件' = @('Commands.Install.ps1', 'Commands.Update.ps1')
}
$script:SkillsLibRoot = Join-Path $PSScriptRoot 'skills.lib'
if (-not (Test-Path -LiteralPath $script:SkillsLibRoot -PathType Container)) { throw ("skills_lib_missing: {0}；请先运行 build.ps1 重新生成或重新安装" -f $script:SkillsLibRoot) }
$script:SkillsLibBase = @('Infrastructure.AtomicFile.ps1', 'Infrastructure.CodexCli.ps1', 'Domain.SkillMetadata.ps1', 'Core.ps1', 'Domain.OperationPlan.ps1', 'Domain.ExecutionAdmission.ps1', 'Domain.SkillCatalog.ps1', 'Domain.Receipt.ps1', 'Domain.RuleDocument.ps1', 'Domain.RuleResponsibility.ps1', 'Domain.RulePatchPlan.ps1', 'Git.ps1', 'Config.ps1', 'Lock.ps1', 'Commands.Utils.ps1')
foreach ($__lib in $script:SkillsLibBase) { . (Join-Path $script:SkillsLibRoot $__lib) }
$script:SkillsLibPacks = @('Application.HostRegistry.ps1', 'Application.SkillSupply.ps1', 'Application.AgentBuild.ps1', 'Application.SkillProjectionPlanning.ps1', 'Application.CapabilityInventory.ps1', 'Application.SkillCatalogCompiler.ps1', 'Application.SkillEligibilityPolicy.ps1', 'Application.SkillProjection.ps1', 'Application.NativeSkillProjection.ps1', 'Application.NativeSkillProjectionCoordinator.ps1', 'Application.NativeAgentBridge.ps1', 'Application.RuleDiscovery.ps1', 'Application.RuleDiagnostics.ps1', 'Application.RuleAdvisor.ps1', 'Application.RuleAudit.ps1', 'Application.RuleEstate.ps1', 'Application.RuleEstateMutation.ps1', 'Application.GlobalRuleProjection.ps1', 'Application.RulePatchGuard.ps1', 'Application.RulePatchExecutor.ps1', 'Commands.Doctor.ps1', 'Commands.AiCoding.ps1', 'Commands.AiRiskControl.ps1', 'Commands.Install.ps1', 'Commands.Update.ps1', 'Commands.Mcp.HostAdapters.ps1', 'Commands.Mcp.ProfileAndSafety.ps1', 'Commands.Mcp.ps1', 'Commands.Migration.ps1', 'Commands.ReleaseUpdate.ps1', 'Commands.Capability.ps1', 'Commands.RuleAudit.ps1', 'Commands.RuleEstate.ps1', 'Commands.GlobalRules.ps1', 'Commands.RulePatch.ps1', 'Commands.AuditTargets.ps1', 'Commands.AuditTargets.Template.ps1', 'Commands.AuditTargets.Snapshot.ps1', 'Commands.AuditTargets.TargetState.ps1', 'Commands.AuditTargets.Plan.ps1', 'Commands.AuditTargets.Bundle.ps1', 'Commands.AuditTargets.Apply.ps1', 'Commands.AuditTargets.Workflow.ps1', 'Commands.AuditTargets.Args.ps1', 'Commands.SkillProjection.ps1')
if ($MyInvocation.InvocationName -eq '.') {
    # Dot-source 模式（测试加载）保持全量函数面。
    foreach ($__lib in $script:SkillsLibPacks) { . (Join-Path $script:SkillsLibRoot $__lib) }
}
else {
    # 计划缺失时回退全量（fail-closed）。
    $__packs = $script:SkillsLibPackPlan[$Cmd]
    if ($null -eq $__packs) { $__packs = $script:SkillsLibPacks }
    foreach ($__lib in @($__packs)) { . (Join-Path $script:SkillsLibRoot $__lib) }
}

# Main Entry Point
# ----------------
# This file is used to assemble the final script.
# It includes the main dispatch logic.

function Write-CommandResult($Result) {
    # 分发层统一输出协议：JSON 走 stdout（ASCII 转义，可重定向），非 JSON
    # 走控制台；非零 exit_code 转为进程退出码。
    if ($Result.json) { Write-Output (ConvertTo-AsciiJson $Result.output) }
    else { Write-Host $Result.output }
    if ($Result.exit_code -ne 0) { exit $Result.exit_code }
}

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
            "check-updates" { Write-CommandResult (Invoke-CheckUpdatesCommand (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("发行更新", "release-update") } { $result = Invoke-ReleaseUpdateCommand $args; if ($result -is [string]) { Write-Output (ConvertTo-AsciiJson $result) } }
            { $_ -in @("发行更新调度", "release-update-schedule") } { $result = Invoke-ReleaseUpdateScheduleCommand $args; if ($result -is [string]) { Write-Output (ConvertTo-AsciiJson $result) } }
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
            { $_ -in @("ai-coding", "AI编码") } { $result = Invoke-AiCodingCommand (Merge-FilterAndArgs $Filter $args); if ($result.json) { Write-Output (ConvertTo-AsciiJson $result.output) } else { Write-Output $result.output } }
            { $_ -in @("能力清单", "capability-inventory") } { Write-CommandResult (Invoke-CapabilityInventoryCommand (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("规则审查", "rule-audit") } { Write-CommandResult (Invoke-RuleAuditCommand (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("规则全域审查", "rule-estate-audit") } { Write-CommandResult (Invoke-RuleEstateAuditCommand (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("规则全域计划", "rule-estate-plan") } { Write-CommandResult (Invoke-RuleEstatePlanCommand (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("规则全域应用", "rule-estate-apply") } {
                $tokens = Merge-FilterAndArgs $Filter $args
                if ($RunPlan) { $tokens = @('--plan') + @($tokens) }
                Write-CommandResult (Invoke-RuleEstateApplyCommand $tokens)
            }
            { $_ -in @("规则全域回滚", "rule-estate-rollback") } { Write-CommandResult (Invoke-RuleEstateRollbackCommand (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("全局规则检查", "global-rules-check") } { Write-CommandResult (Invoke-GlobalRuleCommand check (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("全局规则计划", "global-rules-plan") } { Write-CommandResult (Invoke-GlobalRuleCommand plan (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("全局规则应用", "global-rules-apply") } {
                $tokens = Merge-FilterAndArgs $Filter $args
                if ($RunPlan) { $tokens = @('--plan') + @($tokens) }
                Write-CommandResult (Invoke-GlobalRuleCommand apply $tokens)
            }
            { $_ -in @("全局规则回滚", "global-rules-rollback") } { Write-CommandResult (Invoke-GlobalRuleCommand rollback (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("规则计划", "rule-plan") } { Write-CommandResult (Invoke-RulePlanCommand (Merge-FilterAndArgs $Filter $args)) }
            { $_ -in @("规则应用", "rule-apply") } {
                $tokens = Merge-FilterAndArgs $Filter $args
                if ($RunPlan) { $tokens = @('--plan') + @($tokens) }
                Write-CommandResult (Invoke-RuleApplyCommand $tokens)
            }
            "打开配置" { 打开配置 }
            "解除关联" { 解除关联 }
            "清理备份" { 清理备份 }
            { $_ -in @("帮助", "help", "--help", "-h") } { 帮助 }
            { $_ -in @("ai-risk-control", "风险控制") } {
                $riskTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $riskTokens += $Filter }
                # The top-level -Plan alias is shared by other commands; pass it
                # through so ai-risk-control can keep its command-local plan API.
                if ($RunPlan -and $PSBoundParameters.ContainsKey('RunPlan')) { $riskTokens += '--plan' }
                $riskTokens += @($args)
                $riskResult = Invoke-AiRiskControlCommand $riskTokens
                Write-Output (ConvertTo-AsciiJson ($riskResult | ConvertTo-Json -Depth 30))
                if ($riskResult -and $riskResult.PSObject.Properties.Match('exit_code').Count -gt 0 -and [int]$riskResult.exit_code -ne 0) {
                    exit ([int]$riskResult.exit_code)
                }
            }
            "doctor" {
                $doctorTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $doctorTokens += $Filter }
                $doctorTokens += @($args)
                $doctorResult = Invoke-Doctor $doctorTokens
                # --json 契约：JSON 必须走 stdout（Write-Host 会被重定向/管道丢弃）。
                if (@($doctorTokens | Where-Object { ([string]$_).Trim().ToLowerInvariant() -eq "--json" }).Count -gt 0) {
                    Write-Output (ConvertTo-AsciiJson ($doctorResult | ConvertTo-Json -Depth 30))
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
