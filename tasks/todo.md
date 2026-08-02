# skills-manager vNext Phase 2 Checklist

**task truth**: `tasks/skills-manager-vnext-phase2.tasks.json`
**说明**: 本文件只显示状态；依赖、write set、测试、验证与回滚以 manifest 为准。

- [x] `SMV-P2-001` 建立 P2 spec、task truth 与 current-phase planning fixtures。
- [x] `SMV-P2-002` 实现 RulePatchPlan/diff/schema/sensitive contract。
- [x] `SMV-P2-003` 实现 freshness/root/reparse/token/fixture guards。
- [x] `SMV-P2-004` 实现 fixture-only atomic executor/receipt/rollback。
- [x] `SMV-P2-005` 完成 fault/concurrency/cleanup 恢复验证。
- [x] `SMV-P2-006` 接入 fixture-only CLI 与 MCP receipt adapter。
- [x] `SMV-P2-007` 完成代表 fixture、真实 hash guard 和 P2 closeout。

## Current boundary

- P0/P1：均已 repo_verified，历史真源保留。
- P2：7/7 repo_verified；真实 global/project/host 写入未授权，executor 仍仅允许 fixture root。
- P3：designed-only，不自动进入。
