# 2026-04-22 audit run-id fresh selection

- 规则ID: R1/R2/R6/R8
- 风险等级: 低风险（仅 run-id 自动解析择优逻辑与单测增强）

## 依据
- 问题现象：`--recommendations reports/skill-audit/<run-id>/recommendations.json` 在存在更新但过期的 run（stale snapshot）时，可能自动解析到 stale run，导致 dry-run 直接阻断。
- 目标：保持 `stale_snapshot` 门禁不放松，同时减少自动解析命中过期 run 的概率。

## 变更
- 代码：`Get-AuditLatestRunId` 增加候选分层选择。
  - 优先：可校验且非 stale（快照与 prompt contract 均匹配）的 run。
  - 次优：无法校验新鲜度的 run（unknown）。
  - 最后：已判定 stale 的 run。
- 测试：新增单测 `Prefers latest fresh run over newer stale run when resolving <run-id>`。

## 执行命令
1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`
5. `Invoke-Pester -Script tests/Unit/AuditTargets.Tests.ps1`

## 关键输出
- `Build success: D:\CODE\skills-manager\skills.ps1`
- `doctor --strict` 通过（`Your system is ready for skills-manager.`）
- `构建生效` 完成（构建 89 项技能并完成目标关联）
- `AuditTargets.Tests.ps1`：Passed 56 / Failed 0

## 回滚
1. 回退文件：
   - `src/Commands/AuditTargets.ps1`
   - `tests/Unit/AuditTargets.Tests.ps1`
   - `skills.ps1`（由 build 生成）
2. 回滚后执行：
   - `./build.ps1`
   - `./skills.ps1 doctor --strict --threshold-ms 8000`
