# Implementation Plan: skills-manager vNext Phase 5

**program_id**: `skills-manager-vnext`
**current_phase**: `P5`
**task_truth**: `tasks/skills-manager-vnext-phase5.tasks.json`
**status**: repo_verified
**next_phase_admission**: hold

## 1. Goal

实现 Adaptive Capability Fabric：结构化理解任务、检索与策略判决、组合最小 capability DAG、复用会话能力、消费宿主实时只读快照，并由宿主原生执行。

## 2. Execution contract

- decision plane 统一，skills/MCP/apps/plugins/tools runtime 不统一。
- schema v3 保留 v2 consumer fields；stale/unknown/side-effect fail-closed。
- session/profile 只输出 plan/recommendation，`writes_performed=false`。
- stable App Server read methods only；partial source failure observable。

## 3. Ordered work

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-P5-001` | planning truth | P5 scope and official boundary |
| 2 | `SMV-P5-002` | task model + DAG | meta-query and coding graph green |
| 3 | `SMV-P5-003` | session + snapshot | live read-only multi-kind snapshot |
| 4 | `SMV-P5-004` | skill/corpus/docs | current truth and compatibility aligned |
| 5 | `SMV-P5-005` | closeout | ordered full gates and truth boundary |

## 4. Verification order

Use Phase 5 spec `## 12. Ordered verification`; full runs once after current files stabilize.

## 5. Completion rule

Five tasks done, current golden/fresh/live read-only probes and full gate pass, zero writes/side-effect violations. Repo, host and live acceptance remain separate.

Phase 5 已按本规则完成 5/5；当前宿主只读 snapshot 为 `host_loaded` 级证据，认证业务动作与 `live_accepted` 未执行。

## 6. Maintenance hold

- P4 lifecycle 已显式闭合；跨阶段 planning contract 会阻断历史 phase 未完成却推进当前 phase。
- 当前只维护 P5 seam、真实消费者和已测热点，不创建 P6 manifest，不预扩 schema 或治理层。
- P6 仅在路线图 admission 条件全部满足并获得用户明确授权后进入规划；未满足时继续直接修复 P5。
- 运行时 receipt 留在 ignored `reports/`，历史 receipt 归档；`docs/change-evidence/` 只保留 reviewed logical-slice evidence。
