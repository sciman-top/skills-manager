# skills-manager vNext Phase 5 Checklist

**task truth**: `tasks/skills-manager-vnext-phase5.tasks.json`
**active_maintenance_track**: `maintenance_design`
**maintenance_task_truth**: `tasks/skills-manager-vnext-maintenance-design.tasks.json`
**active_profile_maintenance_track**: `profile_reconciliation_advisor`
**profile_maintenance_task_truth**: `tasks/skills-manager-vnext-profile-reconciliation.tasks.json`

- [x] `SMV-P5-001` 建立 P5 Adaptive Capability Fabric 规划真源。
- [x] `SMV-P5-002` 实现 task model、schema v3 与 capability DAG。
- [x] `SMV-P5-003` 实现 session 稳定性、preheat recommendation 与 App Server 只读快照。
- [x] `SMV-P5-004` 同步 resident skill、corpus、PRD、架构、路线图和兼容验证。
- [x] `SMV-P5-005` 完成 ordered acceptance 与 truth closeout。
- [x] 闭合 P4 lifecycle，并增加跨阶段未闭合阻断。
- [x] 消除 closeout 重复 full-suite 声明，并用 planning contract 防复发。
- [x] 归档 115 份历史 runtime receipt，阻断 active evidence ledger 再次膨胀。
- [x] 增加测试耗时画像，为后续优化提供真实热点。
- [x] 将 P6 admission 置为 hold，禁止无真实失败证据的 phase/schema 扩张。

## Current boundary

- P0-P4 保持历史 `repo_verified` 真源。
- P5 已完成 5/5 `repo_verified`；live read-only snapshot 与 full closeout 已通过。
- Plugin/MCP install、OAuth、host writes、profile/session mutation、ChatGPT web local projection 和 business `live_accepted` 不在自动执行面。
- 当前进入 P5 maintenance hold；不创建 P6 task manifest，除非路线图 admission 条件全部满足且用户明确授权。

## Maintenance design checklist

- [x] `SMV-MD-001` 同步 Lean AI Software Delivery PRD、架构、路线图和产品索引。
- [x] `SMV-MD-002` 落盘 maintenance spec、manifest、实施计划和 checklist。
- [x] `SMV-MD-003` 实现 companion planning verifier 和负向单元测试。
- [x] `SMV-MD-004` 同步根契约、共享 evidence、运行有序门禁并限定 truth closeout。

M0 仅为 maintenance design planning package `repo_verified`；M1-M3 仍为 `conditional`。10-task pilot、runtime/host mutation、P6 admission 和 business `live_accepted` 均未执行。

## Capability routing correction checklist

- [x] `SMV-CR-001` 复现真实误路由，核对官方/社区依据并确定 native-first 架构。
- [x] `SMV-CR-002` 实现 discovery/policy kernel、profile 调整、自然语言 corpus 和 focused tests。
- [x] `SMV-CR-003` 同步 PRD、架构、路线图、spec、manifest、plan、todo 与根契约。
- [x] `SMV-CR-004` 完成 build、16-profile probe、只读 host replay、planning/full gate、evidence 与 Git 收口。

该 checklist 已按 P5-local defect correction 完成 4/4 `repo_verified`，不改写 P5 5/5 历史状态。M1 10-task pilot 未执行，P6 继续 hold；deterministic corpus 与 profile 可见性不等于 host-native 普遍正确或 business `live_accepted`。

## Profile reconciliation advisor checklist

- [x] `SMV-PR-001` 确定 host-owned semantics、deterministic validation 和 plan-only 边界。
- [x] `SMV-PR-002` 实现 current diagnostics、proposal change-set、CLI/script 与 focused tests。
- [x] `SMV-PR-003` 同步产品、路线图、索引、manifest、plan/todo 与根契约。
- [x] `SMV-PR-004` 完成有序门禁、共享 evidence、限定真值和 Git 收口。

本 track 已完成 4/4 `repo_verified`，但不自动修改 profile、不切换 `active_profile`，也不保证宿主 proposal 的普遍语义正确；P5/P6/M1 truth 保持不变。
