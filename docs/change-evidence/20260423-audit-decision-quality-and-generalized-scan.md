# 2026-04-23 审查目标：通用扫描与决策质量门禁

## 规则与归宿
- Rule IDs: `R1,R2,R3,R6,R8`
- 当前落点: `src/Commands/AuditTargets*.ps1`, `tests/Unit/AuditTargets.Tests.ps1`
- 目标归宿: `审查目标` 扫描/建议/应用链路对“非特定仓库”场景可迁移，且建议具备可验证决策依据

## 风险分级
- 风险等级: 中
- 影响面: 审查包生成、recommendations 模板与校验、dry-run/apply 阻断逻辑、repo 扫描事实提取
- 兼容策略: 保持原有命令入口不变，仅新增字段与更严格校验

## 执行命令与关键输出
1. `./build.ps1`
   - `Build success: D:\CODE\skills-manager\skills.ps1`
2. `Invoke-Pester -Path ./tests/Unit/AuditTargets.Tests.ps1`
   - `Passed: 65 Failed: 0`
3. `./skills.ps1 发现`
   - 输出 96 项映射清单，无异常退出
4. `./skills.ps1 doctor --strict --threshold-ms 8000`
   - `skills.json: Valid JSON + contract`
   - `Your system is ready for skills-manager.`
5. `./skills.ps1 构建生效`
   - `构建完成：agent/ (共 89 项技能)`
   - 各客户端 `skills` 目录链接重建成功

## 变更要点
- 新增 `decision-insights.json` 产物并接入 brief/prompt/bundle 必需文件。
- 新增 `decision_quality_policy` 与 `keyword_trace` 约束，dry-run/apply 预检失败时阻断执行。
- 扩展 repo 通用扫描信号：`Makefile`、Java、Ruby、PHP、Container、Monorepo。
- 支持 `overrides/audit-source-strategy.json` 深度合并覆盖。
- 新增/更新单测覆盖上述能力。

## 缺陷修复（本次自修复）
- 现象: `Applies source-strategy override from overrides directory` 用例失败。
- 根因: 对 `System.Collections.Generic.List[object]` 使用 `@(...)` 触发 PowerShell 动态绑定异常。
- 修复:
  - `return @($arr)` -> `return $arr.ToArray()`
  - `foreach ($patch in @($patches))` -> `foreach ($patch in $patches)`
- 验证: 单测从 `Failed: 1` 收敛到 `Failed: 0`。

## 回滚动作
1. 回滚本次涉及文件到变更前版本（按提交或文件级还原）。
2. 重新执行:
   - `./build.ps1`
   - `./skills.ps1 发现`
   - `./skills.ps1 doctor --strict --threshold-ms 8000`
   - `./skills.ps1 构建生效`
3. 若需临时止血，可先禁用 `decision_quality_policy` 严格项（通过 `overrides/audit-source-strategy.json`），待修复完成后恢复。
