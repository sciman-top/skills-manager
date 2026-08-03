# 2026-04-25 audit source observations

## Goal
- 当前落点：`审查目标` 外层 AI 来源策略、`recommendations.json` schema v2 模板与 dry-run 校验。
- 目标归宿：让外层 AI 在判断技能/MCP 新增、卸载、排除时，必须留下候选来源观察，尤其对 MCP 补充 provider/security evidence 边界。
- 风险等级：中。原因是扩展审查契约与 dry-run 阻断策略，但保持 schema_version=2，旧 recommendations 缺少 `source_observations` 时仍能加载。

## Changes
- `source-strategy.json` 默认来源新增：
  - `mcp-provider-docs`
  - `security-and-permission-notes`
- `evidence_policy` 新增 `require_source_observations_for_changes`。
- `recommendations.template.json` 新增 `source_observations` 示例。
- `Load-AuditRecommendations` 规范化 `source_observations`，并允许旧文件默认空数组。
- dry-run/apply 在策略开启时阻断“有技能/MCP 变更但没有匹配 source_observations”的建议。
- `Set-ContentUtf8` 新增受限宿主 fallback：新文件直接写入；已有文件 atomic replace 失败到最后一次重试时回退为直接写入。

## Verification
- `.\build.ps1`
  - exit_code: `0`
  - key_output: `Build success: D:\CODE\skills-manager\skills.ps1`
- `.\skills.ps1 审查目标 发现新技能 --query "mcp evidence test" --out reports\skill-audit\codex-source-observation-check-20260425-183144`
  - exit_code: `0`
  - key_output: generated `source-strategy.json`, `recommendations.template.json`, `outer-ai-prompt.md`
  - evidence: generated source strategy includes `mcp-provider-docs`, `security-and-permission-notes`, and `require_source_observations_for_changes=true`
- `.\skills.ps1 审查目标 应用 --recommendations <generated>\recommendations.json --dry-run-ack "我知道未落盘"` with one add recommendation and empty `source_observations`
  - exit_code: `1`
  - key_output: `insufficient_source_coverage` and `变更建议需要对应 source_observations`
- `.\skills.ps1 审查目标 应用 --recommendations <generated>\recommendations.json --dry-run-ack "我知道未落盘"` with no-op recommendations
  - exit_code: `0`
  - key_output: `DRY-RUN 完成：未修改任何技能映射或 MCP 配置`
- `.\skills.ps1 发现`
  - exit_code: `0`
  - key_output: rendered 96 discoverable entries
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - exit_code: `0`
  - key_output: `Your system is ready for skills-manager.`
- `.\tests\check-generated-sync.ps1 -AllowDirtyWorktree`
  - exit_code: `0`
  - key_output: `生成产物与当前 src 一致`
- `git diff --check`
  - exit_code: `0`
  - key_output: no whitespace errors

## N/A / Blocked
- `Invoke-Pester -Script .\tests\Unit\AuditTargets.Tests.ps1`
  - classification: `gate_na`
  - reason: current host has no `Pester` module; `tests/run.ps1` declares Pester as required.
  - alternative_verification: build, generated package smoke test, dry-run block/pass probes, `发现`, and `doctor --strict`.
  - evidence_link: this file.
  - expires_at: `2026-05-02`
- `.\skills.ps1 构建生效`
  - classification: `platform_na`
  - reason: current Codex desktop sandbox denies move/delete over `agent/` and `.txn`, causing `build-txn:agent-backup => Access to the path is denied`.
  - alternative_verification: `.\build.ps1`, `.\skills.ps1 发现`, `.\skills.ps1 doctor --strict --threshold-ms 8000`, and audit dry-run smoke tests passed.
  - evidence_link: this file.
  - expires_at: `2026-05-02`

## Rollback
- Revert `src/Core.ps1`, `src/Commands/AuditTargets.ps1`, `src/Commands/AuditTargets.Template.ps1`, `src/Commands/AuditTargets.Plan.ps1`, `src/Commands/AuditTargets.Apply.ps1`, `tests/Unit/AuditTargets.Tests.ps1`, and regenerated `skills.ps1`.
- Re-run gates in order: `.\build.ps1` -> `.\skills.ps1 发现` -> `.\skills.ps1 doctor --strict --threshold-ms 8000` -> `.\skills.ps1 构建生效`.
