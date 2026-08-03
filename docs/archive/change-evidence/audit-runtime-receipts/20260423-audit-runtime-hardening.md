# 2026-04-23 Audit Runtime Hardening

- Rule ID: R1/R2/R6/R8
- Risk Level: medium
- Scope: 审查目标扫描粒度、画像预检严格化、recommendations 空建议原因码、source 覆盖门槛、dry-run 机器摘要、自动证据落盘

## Basis
- 用户确认执行 6 项优化并要求直接本机落地。
- 现状问题：repo scan 事实粒度不足、画像时间戳未强校验、空建议无结构化原因码、dry-run 缺少机器可读摘要、运行证据记录依赖手工。

## Commands
- `./build.ps1`
- `Invoke-Pester -Path tests/Unit/AuditTargets.Tests.ps1`
- `Invoke-Pester -Path tests/E2E/SkillAudit.Tests.ps1`
- `./skills.ps1 发现`
- `./skills.ps1 doctor --strict --threshold-ms 8000`
- `./skills.ps1 构建生效`

## Key Output
- Unit: Passed 62, Failed 0
- E2E SkillAudit: Passed 3, Failed 0
- doctor(strict): pass
- 门禁顺序全部通过：build -> test -> contract/invariant -> hotspot

## Changes
- `src/Commands/AuditTargets.ps1`
  - 强化 user-profile 预检查：summary/structured 关键字段/last_structured_at 全量校验。
  - 扫描增强：增加 pyproject/.csproj/.sln/CI workflow 解析，补充 package manager/framework/build/test 命令识别。
  - prompt contract version 更新到 `audit-prompt-v20260422.3`。
- `src/Commands/AuditTargets.Template.ps1`
  - source-strategy 新增 `evidence_policy`。
  - 审查包校验新增 user-profile.summary 与 last_structured_at 约束。
  - recommendations template 新增 `empty_recommendation_reasons`。
- `src/Commands/AuditTargets.Plan.ps1`
  - recommendations 载入时自动归一化空建议原因码。
  - 新增来源覆盖统计函数。
  - 摘要输出支持空建议原因码。
- `src/Commands/AuditTargets.Apply.ps1`
  - 新增 source 覆盖门槛校验（按 source-strategy.evidence_policy）。
  - 失败阻断 `insufficient_source_coverage`。
  - dry-run 产出 `dry-run-summary.json`（保留原序号）。
  - 增加运行证据自动落盘。
- `src/Commands/AuditTargets.Bundle.ps1`
  - scan/discover 结束后自动写入运行证据。
- `tests/Unit/AuditTargets.Tests.ps1`
  - 补充新增能力测试：粒度扫描、空建议原因码、source 覆盖阻断、dry-run summary、预检时间戳。

## Rollback
- 代码回滚：撤销以上文件到变更前版本。
- 运行态回滚：删除新增证据文件与 `dry-run-summary.json`；重新执行 `./build.ps1` 与 `./skills.ps1 构建生效` 恢复一致性。
