# 2026-04-22 audit precheck + prompt short + run-id hint

- 规则ID: R1/R2/R6/R8
- 风险等级: 中低风险（仅审查流程前置校验、提示词模板与错误提示增强）

## 依据
- 问题现象：存在 run 目录但缺少 `audit-meta.json` 时，`<run-id>` 自动解析会直接失败，且报错不够聚焦“先扫描”。
- 问题现象：`user_profile.summary` 为空时，流程可继续但会增加外层 AI 产出不稳定性。
- 目标：
  - 在 `扫描/发现新技能` 前自动做画像预检查并尽量自修复。
  - `<run-id>` 无有效候选时给出明确阻断提示和缺失文件证据。
  - 提供更短的默认 outer prompt，适配 Codex/Claude 代理执行。

## 变更
- 代码：`src/Commands/AuditTargets.ps1`
  - 将 `Get-DefaultAuditOuterAiPrompt` 改为短版执行提示词（覆盖 run-id、预检查、只读输入、产出约束、自检+dry-run、汇报格式）。
  - 新增画像预检查函数：
    - `Get-AuditFallbackSummaryFromRawText`
    - `Test-AuditStructuredProfileComplete`
    - `New-AuditPrecheckStructuredProfile`
    - `Ensure-AuditUserProfilePrecheck`
  - `Get-AuditPromptContractVersion` 升级为 `audit-prompt-v20260422.2`。
  - `Resolve-AuditRunIdInput` / `Resolve-AuditPathRunIdPlaceholder` 传入 required-files 级别的 hint。
  - `Get-AuditRunIdHintText` 支持按 required files 输出“可用 run / 不可用 run(缺失项)”并统一提示 `先执行 .\skills.ps1 审查目标 扫描`。
- 代码：`src/Commands/AuditTargets.Bundle.ps1`
  - `Invoke-AuditTargetsScan` 与 `Invoke-AuditSkillDiscovery` 入口改为先调用 `Ensure-AuditUserProfilePrecheck`。
- 测试：`tests/Unit/AuditTargets.Tests.ps1`
  - 新增 `Shows scan hint when placeholder cannot find required run files`。
  - 新增 `Auto-fills empty summary during profile precheck before scan`。
  - 同步 built-in prompt 断言到短版内容。

## 执行命令
1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`
5. `Invoke-Pester -Path tests/Unit/AuditTargets.Tests.ps1`
6. `Invoke-Pester -Path tests/E2E/SkillAudit.Tests.ps1`

## 关键输出
- `Build success: D:\CODE\skills-manager\skills.ps1`
- `doctor --strict` 通过（`Your system is ready for skills-manager.`）
- `构建生效` 完成（构建 89 项技能并完成目标关联）
- `AuditTargets.Tests.ps1`：Passed 59 / Failed 0
- `SkillAudit.Tests.ps1`：Passed 3 / Failed 0

## 回滚
1. 回退文件：
   - `src/Commands/AuditTargets.ps1`
   - `src/Commands/AuditTargets.Bundle.ps1`
   - `tests/Unit/AuditTargets.Tests.ps1`
   - `skills.ps1`（由 build 生成）
2. 回滚后执行：
   - `./build.ps1`
   - `./skills.ps1 doctor --strict --threshold-ms 8000`
