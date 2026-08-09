# skills-manager vNext Phase 6 Checklist

**task truth**: `tasks/skills-manager-vnext-phase6.tasks.json`
**status**: host_evaluation_partial; 12/12 implemented; runtime migration completed; host_inventory_loaded observed at 122/122 (106/106 managed projection; two previously observed sites skills are external inventory drift); host_invocation_observed not_observed; final full receipt authority is `reports/quality-gates/current.json`; live_accepted not_accepted
**active_maintenance_track**: `maintenance_design`
**maintenance_task_truth**: `tasks/skills-manager-vnext-maintenance-design.tasks.json`
**maintenance_pilot_truth**: `tasks/skills-manager-vnext-lean-delivery-pilot.json`
**active_typed_core_track**: `typed_core_shadow_poc`
**typed_core_task_truth**: `tasks/skills-manager-vnext-typed-core-pilot.tasks.json`
**powershell_runtime_track**: `powershell7_runtime_migration`
**powershell_runtime_task_truth**: `tasks/skills-manager-vnext-powershell7-migration.tasks.json`
**active_profile_maintenance_track**: `profile_reconciliation_advisor`
**profile_maintenance_task_truth**: `tasks/skills-manager-vnext-profile-reconciliation.tasks.json`
**active_profile_optimization_track**: `profile_optimization_canary`
**profile_optimization_task_truth**: `tasks/skills-manager-vnext-profile-optimization.tasks.json`
**active_discovery_redesign_track**: `capability_discovery_redesign`
**discovery_redesign_task_truth**: `tasks/skills-manager-vnext-capability-discovery-redesign.tasks.json`

## P6 Host-Native Skill Lifecycle Reset checklist

- [x] `SMV-P6-001` 固化 admission、历史 supersession map、规划真源与负向 verifier。
- [x] `SMV-P6-002` 实现 HostCapabilitySnapshot 合同和有效来源优先级。
- [x] `SMV-P6-003` 实现 App Server、fresh CLI 和 config fallback adapters。
- [x] `SMV-P6-004` 从 legacy router 拆出 catalog compiler 与 eligibility policy。
- [x] `SMV-P6-005` 实现 token-aware 全 enabled metadata planner。
- [x] `SMV-P6-006` 实现 all-skills native projection、receipt 和 rollback。
- [x] `SMV-P6-007` 建立 metadata lint 与 direct/indirect/negative/no-skill corpus。
- [x] `SMV-P6-008` 实现 native invocation trace 和 truth ladder。
- [x] `SMV-P6-009` 完成 native-only 与 legacy path 的 zero-write shadow comparison。
- [x] `SMV-P6-010` 退役 profile reachability 并完成配置 round-trip migration。
- [x] `SMV-P6-011` 实现 opt-in strict App Server dispatch fallback。
- [x] `SMV-P6-012` 完成 staged removal、runner 稳定化、single-flight full closeout 与 truth-boundary evidence；fresh host 仍仅 `host_evaluation_partial`。

当前 P6 manifest 为 12/12 done，runtime projection 已完成；fresh App Server inventory 连续两次为 `122/122`，其中受管 projection `106/106`、`missing=0`，只证明 `host_inventory_loaded=observed`。旧快照中的 `sites:sites-building` 与 `sites:sites-hosting` 是外部宿主 inventory 漂移，不是仓库投影缺口。代表性 selection replay 为 7/7，但宿主不暴露 native injected/executed events，故最高真值仍是 `host_evaluation_partial`，`host_invocation_observed=not_observed`，`live_accepted=not_accepted`；不得声称全部技能面对所有任务必然正确命中。最终 full 只以本轮收口后生成的 immutable receipt 和 `reports/quality-gates/current.json` pointer 为权威。

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
- P5 maintenance hold 已由用户授权和 reachability failure evidence 解除；P6 已完成 12/12 repo-side closeout，宿主写入与 live acceptance 仍不在本次结果内。

## Maintenance design checklist

- [x] `SMV-MD-001` 同步 Lean AI Software Delivery PRD、架构、路线图和产品索引。
- [x] `SMV-MD-002` 落盘 maintenance spec、manifest、实施计划和 checklist。
- [x] `SMV-MD-003` 实现 companion planning verifier 和负向单元测试。
- [x] `SMV-MD-004` 同步根契约、共享 evidence、运行有序门禁并限定 truth closeout。
- [x] `SMV-MD-005` 固化 host-owned coordinator、read-only panel、single-writer shared seam 与 Git CAS freshness 语义。
- [x] `SMV-MD-006` 固化稀疏工具栈、社区 disposition、context-adapter admission 与 M1 observation contract。
- [x] `SMV-MD-007` 增强 evidence-group、M0.2 policy 和 sample observation 的 fail-closed verifier/tests。
- [x] `SMV-MD-008` 同步 M0.2 产品/根契约/evidence，运行唯一 full gate 并限定 truth closeout。
- [x] `SMV-MD-009` 固化 host-owned TaskGraph、Sol xhigh/medium/low 三档软锚点、Radar-independent 编排、并发 admission 和失败升级合同。
- [x] `SMV-MD-010` 固化 PowerShell thin shell + C#/.NET typed-core 条件性架构、TC0-TC3、兼容与回滚门禁。
- [x] `SMV-MD-011` 增强 M0.3 verifier/tests，同步索引/根契约/README/evidence 并完成唯一 full gate 收口。
- [x] M0.1 补齐 North Star、native baseline、双证据流、删除评审与 pilot 计数合同。
- [ ] M1 收集并 review 10 个真实 observe-only 样本（当前 0/10）。

M0/M0.2/M0.3 maintenance design planning package 为 11/11 `repo_verified`；M1 已获授权并保持 `collecting (0/10)`，但没有任何真实样本、并行/工具/模型策略收益、pilot 完成或业务收益声明。coordinator/lease/model-router runtime、仓库 custom-agent/host config mutation和社区工具安装均未发生；活动档位已经收敛为 Sol xhigh/medium/low，Radar refresh 已禁用且不参与编排。旧 Luna/Terra native subagent 与 Radar Scheduled run 仅保留对应 surface 的历史 receipt。typed-core TC0/TC1 只完成 shadow PoC，PowerShell 领域实现未替换。当前 shell 支持面已独立收敛为 PS7-only；M3/TC3 conditional、TC2/P6 admission/业务 `live_accepted` 均未执行。

## PowerShell 7 runtime migration checklist

- [x] `SMV-PS7-001` 冻结当前消费者、官方生命周期、PS7-only 决策与历史事实边界。
- [x] `SMV-PS7-002` 将 source、generated bundle、installer、CMD wrapper 和受管 subprocess 收敛为 `pwsh` fail-closed。
- [x] `SMV-PS7-003` 删除 5.1 CI/smoke，迁移 focused tests 与通用 PowerShell automation 指导。
- [x] `SMV-PS7-004` 同步 PRD、架构、路线图、runbook、release、plan/todo 与回滚合同。
- [x] `SMV-PS7-005` 以 runtime-policy verifier、focused tests、generated-sync 和 full gate 完成 `repo_verified` 收口。

本 track 只改变当前 shell runtime support：最低 PowerShell 7.0、推荐 7.6 LTS、缺少 `pwsh` 时 fail-closed。它不改写历史 Phase manifest，不证明所有下游消费者已迁移，不启动 TC2/P6，也不把 Windows PowerShell 5.1 描述为已被微软停止支持。

## Agent workflow advisory runtime checklist

- [x] `SMV-AWA-001` 冻结 user/host/repo/native runtime 分责、TaskGraph/FailurePacket v1、legacy Radar read-only compatibility 和 P6/host/live 边界。
- [x] `SMV-AWA-002` 实现 canonical write path、completion receipt、Radar upstream freshness/non-empty/observation-only 与 FailurePacket correction validators。
- [x] `SMV-AWA-003` 实现 one-group barrier waves、parallel admission、三档 host proposal/local outcome validation 和 bounded escalation/readmission。
- [x] `SMV-AWA-004` 接入 PS7 `agent-plan/agent-validate`，真实 bundle envelope 固定 provider/native/write counters 0。
- [x] `SMV-AWA-005` 建立 verifier/negative tests、产品/根/README/evidence 同步并以唯一 full gate 收口。

该 adjacent track 为 5/5 `repo_verified / repo_advisory_only`：只证明仓库合同与 CLI。当前活动三档为 `Sol xhigh / Sol medium / Sol low`，均由宿主按任务语义提案并受当前 surface availability 约束；Radar automation 已删除，旧 Luna/Terra/Radar probe 仅为历史只读 receipt。它不证明任意项目必然自动委派、模型策略有普遍净收益或业务 `live_accepted`。

## Typed-core Operation Contract checklist

- [x] `SMV-TC-001` 冻结 `OperationPlan/Receipt v1` read-only seam、三个 caller、四个 corpus hash、protocol/SDK/rollback。
- [x] `SMV-TC-002` 实现 package-free .NET 10 shadow validator，完成 4/4 corpus parity 和 4/4 request negatives，保持零生产引用。
- [x] `SMV-TC-003` 完成三种发布观测、planning verifier/tests、产品/根状态、evidence 与唯一 full gate 收口。

TC0/TC1 为 3/3 `repo_verified`、`shadow_only`；PowerShell runtime `authoritative`，TC2/生产集成 `not_started`，M1 仍为 0/10，P6 hold，live acceptance not_run。self-contained 体积约 73–80 MB，只是描述性成本证据，不构成默认分发决策。

## Capability routing correction checklist

- [x] `SMV-CR-001` 复现真实误路由，核对官方/社区依据并确定 native-first 架构。
- [x] `SMV-CR-002` 实现 discovery/policy kernel、profile 调整、自然语言 corpus 和 focused tests。
- [x] `SMV-CR-003` 同步 PRD、架构、路线图、spec、manifest、plan、todo 与根契约。
- [x] `SMV-CR-004` 完成 build、16-profile probe、只读 host replay、planning/full gate、evidence 与 Git 收口。

该 checklist 已按 P5-local defect correction 完成 4/4 `repo_verified`，不改写 P5 5/5 历史状态。该 track 收口时 M1 未执行；当前独立 registry 为 collecting 0/10，P6 继续 hold。deterministic corpus 与 profile 可见性不等于 host-native 普遍正确或 business `live_accepted`。

## Hierarchical capability discovery redesign checklist

- [x] `SMV-HD-001` 建立 default cold baseline、强制 treatment 和层级发现架构。
- [x] `SMV-HD-002` 实现 domain purpose catalog、DomainHint、candidate provenance 和兼容 policy。
- [x] `SMV-HD-003` 完成 32-case selection 与 8-case cold-load fresh host acceptance。
- [x] `SMV-HD-004` 同步产品/规划/evidence，运行有序门禁并完成 Git 收口。

本 track 完成 4/4 `repo_verified`；selection 32/32、cold-load 8/8 只属于 `host_evaluation_partial`。active profile 恢复 `default`；P5 5/5、P6 hold 与 business `live_accepted` 不变；M1 当前独立 collecting 0/10。cold-load input token 未下降，不宣称成本优化。

Post-closeout follow-up：canonical inventory delta signal 与 cached/uncached/tool-round 指标已实现；profile-only/no-op 不触发。两个真实 A/B 已否决 combined command 优化并恢复 separate 链，只保留按需 cold discovery、1–2 case focused replay 和全量 corpus 仅用于结构变化/closeout；不新增 task，也不宣称普遍 token 降低。

Natural-limit hardening 已完成：unknown-domain fail-closed、truncation signal、current skill/MCP snapshot override、host-facing compact projection；deterministic corpus 30/30。剩余宿主语义波动、固定上下文与 invocation trace 缺口保持外部边界。

Portable-catalog correction 已实现为既有 follow-up：完整 canonical cold inventory 随 router 包投影，跨仓 discovery 不再要求本仓 manifest/config/policy 或 profile 预热；专用 cross-repo test 覆盖 repo 外 CWD，corpus verifier 不依赖 ignored deployment state。该项不增加 track/task count，M1/P6/live truth 不变。

## Profile reconciliation advisor checklist

- [x] `SMV-PR-001` 确定 host-owned semantics、deterministic validation 和 plan-only 边界。
- [x] `SMV-PR-002` 实现 current diagnostics、proposal change-set、CLI/script 与 focused tests。
- [x] `SMV-PR-003` 同步产品、路线图、索引、manifest、plan/todo 与根契约。
- [x] `SMV-PR-004` 完成有序门禁、共享 evidence、限定真值和 Git 收口。

本 track 已完成 4/4 `repo_verified`，但不自动修改 profile、不切换 `active_profile`，也不保证宿主 proposal 的普遍语义正确；P5/P6 truth 保持不变，M1 当前独立 collecting 0/10。

## Bounded profile optimization checklist

- [x] `SMV-PO-001` 确定 host semantics、deterministic canary、fresh-task 和 active profile 边界。
- [x] `SMV-PO-002` 实现 host handoff、bounded apply、atomic receipt、replay acceptance、rollback 和 focused tests。
- [x] `SMV-PO-003` 完成自然语言 host replay、产品同步、共享 evidence、唯一 full gate 与 Git 收口。

本 track 已完成 3/3 `repo_verified`，真实代表 prompt replay 为 `host_evaluation_partial_pass`；P5 仍为 5/5，P6 继续 hold，M1 当前独立 collecting 0/10，business `live_accepted` 未执行。不得将该局部结果外推为普遍语义正确。
