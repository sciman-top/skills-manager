# Implementation Plan: skills-manager vNext Phase 5

**program_id**: `skills-manager-vnext`
**current_phase**: `P5`
**task_truth**: `tasks/skills-manager-vnext-phase5.tasks.json`
**status**: repo_verified
**next_phase_admission**: hold
**active_maintenance_track**: maintenance_design
**maintenance_task_truth**: `tasks/skills-manager-vnext-maintenance-design.tasks.json`

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

## 7. Lean AI Software Delivery maintenance design

Goal：把 skills-manager 面向高效 AI 软件交付的总体方案落为 advisory planning contract，解决主链缺失、过度设计、角色接力、门禁膨胀、方向漂移和未经验证的“自学习”，同时不实现新的 runtime 或启动 P6。

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-MD-001` | product truth | FR/NFR/ADR 唯一；P5/P6 状态不变；无 runtime/pilot 已实现表述 |
| 2 | `SMV-MD-002` | spec + task contract | 四任务依赖、exact write set、rollback/done_when 完整；M1 不进入 manifest |
| 3 | `SMV-MD-003` | companion verifier | current pass；负向 fixture fail-closed；只读且无 network/host access |
| 4 | `SMV-MD-004` | truth closeout | 一份共享 evidence；新旧 verifier 通过；唯一 full gate 通过；只声明 M0 repo_verified |

Failure routing：文档/manifest 漂移先修当前真源；同一 verifier 缺陷连续失败两次后重审检查设计；未知工作树改动、P5 回归、P6 manifest、runtime write set 或 full gate 失败立即阻断收口。10-task observe-only pilot 只有另行授权后才进入 M1，不属于本计划的执行项。

Verification：迭代运行 focused planning tests 与两个 verifier；文件稳定后由 `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` 统一运行一次完整套件，随后执行 `git diff --check` 和 Git boundary 检查。不在 full gate 前后另行重复完整 suite。
