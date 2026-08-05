# Implementation Plan: skills-manager vNext Phase 5

**program_id**: `skills-manager-vnext`
**current_phase**: `P5`
**task_truth**: `tasks/skills-manager-vnext-phase5.tasks.json`
**status**: repo_verified
**next_phase_admission**: hold
**active_maintenance_track**: maintenance_design
**maintenance_task_truth**: `tasks/skills-manager-vnext-maintenance-design.tasks.json`
**maintenance_pilot_truth**: `tasks/skills-manager-vnext-lean-delivery-pilot.json`
**maintenance_pilot_status**: collecting (0/10)
**active_correction_track**: capability_routing_correction
**correction_task_truth**: `tasks/skills-manager-vnext-capability-routing-correction.tasks.json`
**correction_status**: repo_verified
**active_discovery_redesign_track**: capability_discovery_redesign
**discovery_redesign_task_truth**: `tasks/skills-manager-vnext-capability-discovery-redesign.tasks.json`
**discovery_redesign_status**: repo_verified
**active_profile_maintenance_track**: profile_reconciliation_advisor
**profile_maintenance_task_truth**: `tasks/skills-manager-vnext-profile-reconciliation.tasks.json`
**profile_maintenance_status**: repo_verified
**active_profile_optimization_track**: profile_optimization_canary
**profile_optimization_task_truth**: `tasks/skills-manager-vnext-profile-optimization.tasks.json`
**profile_optimization_status**: repo_verified

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
| 5 | `SMV-MD-005` | coordination + Git truth | host-owned coordinator；read-only panel；shared seam single writer；CAS 只做 freshness |
| 6 | `SMV-MD-006` | sparse tool stack + pilot observations | disposition/context-adapter/skill lifecycle 完整；M1 仍 collecting 0/10 |
| 7 | `SMV-MD-007` | M0.2 verifier | evidence-group、policy literal、sample observation 与负向边界 fail-closed |
| 8 | `SMV-MD-008` | M0.2 closeout | 独立 evidence；产品索引/根契约同步；唯一 full gate；不声明 runtime/live |
| 9 | `SMV-MD-009` | TaskGraph + model policy | host-owned semantics；三档软锚点；Radar expiring snapshot；并行 admission 与 escalation |
| 10 | `SMV-MD-010` | PowerShell/typed-core architecture | 当前 PS 单一真源；C#/.NET thin-shell PoC 路线；TC0-TC3；拒绝重写/双真源 |
| 11 | `SMV-MD-011` | M0.3 verifier + closeout | 三组 evidence；模型/runtime/typed-core 边界 fail-closed；唯一 full gate；不声明 PoC/live |

M0.1/M0.2/M0.3/M1 bootstrap：North Star、native baseline、双证据流、删除候选、host-owned coordinator、single-writer write-set admission、Git CAS truth、工具 disposition、TaskGraph/model policy、Radar freshness、失败升级与 typed-core 迁移决策已落盘；M1 已获授权并进入 `collecting (0/10)`。后续只在真实任务达到证据停止点时追加 registry，不生成回溯性 synthetic 样本，也不把收集启动写成 pilot 已执行、Radar 有效、typed core 已实现或业务收益。

M0.2 execution contract：2–3 个 Agent 只可并行输出 read-only 设计候选，由一个 coordinator 综合决定；实现并行要求固定 base、依赖完成、exact write set 互斥、candidate 可独立验证和 integration owner 明确。共享文件、生成 seam、schema/migration、lock/config、Git index/ref 和同一外部状态使用单 writer/串行。lease 是 owner/write-set/base/recovery claim；Git CAS/hash 只检测 stale，不是文件锁、队列或 winner selector。本 track 不实现 scheduler/daemon/database，不安装 Trellis/AGOS/GBrain/code graph。

Tool admission：默认 `host-native + repo-native + Git + gates`；只有重复 workflow 进入 skill，分发需要进入 plugin，current external data/action 进入 MCP/connector，两个独立 repo-native 检索失败且语言/privacy/freshness/resource/supply-chain/rollback 完整时才评估 read-only context adapter。所有候选必须有 adopt/adapt/defer/reject、native equivalent、consumer、evaluation、maintenance cost 和 retirement trigger。

M0.3 model policy：用户拥有目标、价值排序、不可逆风险和外部授权；宿主 AI 负责 TaskGraph、串并行、模型/effort、spawn/wait/steer、升级、集成和最终综合；skills-manager 只提供 Radar/cost/risk proposal 与 deterministic admission。默认 `Sol xhigh / Sol medium / Luna max` 是可覆盖软锚点。一次 corrected retry 后仍失败则补证据/re-scope；仅模型能力不足才逐级升级；同一 issue 两次失败或两次升档由 supervisor 串行接管。shared seam、final integration 和 full gate 始终串行。

M0.3 technology path：当前 PS7/生成 bundle 继续是唯一运行真源，5.1 只做 bounded smoke。候选目标是 C#/.NET typed core + PowerShell thin shell，不是全仓重写。下一可执行里程碑 `TC0` 只选择一个 read-only pure seam、两个真实 caller 与固定 corpus，形成 SDK pin/protocol/parity/rollback proposal；`TC1` PoC、`TC2` 单 seam 迁移和 `TC3` retain/revise/retire 都保持 conditional/not_started，需独立授权和证据。

Failure routing：文档/manifest/registry 漂移先修当前真源；同一 verifier 缺陷连续失败两次后重审检查设计；Radar stale 回退 native default；子任务失败按 FailurePacket 判断 task/context/tool/capacity，不把权限问题伪装成模型问题；typed-core parity/分发/rollback 不达标则删除 PoC。未知工作树改动、P5 回归、P6 manifest、runtime write set、host/model mutation 或 full gate 失败立即阻断收口。M1 达到 10 个真实样本并完成人工 review 前保持 collecting/observe-only。

Verification：迭代运行 focused planning tests 与两个 verifier；文件稳定后由 `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` 统一运行一次完整套件，随后执行 `git diff --check` 和 Git boundary 检查。不在 full gate 前后另行重复完整 suite。

## 8. Native-first capability routing correction

Goal：将 P4/P5 的 lexical semantic router 退役为兼容 discovery/policy kernel，由宿主 AI 依据完整请求、对话和 skill metadata 做唯一语义判断；在低风险能力上保持无感使用，在安装、认证、写入和激活上保持可见边界。

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-CR-001` | root cause + architecture | 真实反例可复现；官方/社区 disposition 与 ADR-SMV-017 完整；P5/P6 历史边界不变 |
| 2 | `SMV-CR-002` | discovery/policy + profiles + corpus | 零脚本 semantic auto-selection；否定提及不触发；focused tests/corpus/profile budgets 通过 |
| 3 | `SMV-CR-003` | product/planning truth | PRD/架构/路线图/spec/manifest/plan/todo/AGENTS 一致；M1 未执行，P6 hold |
| 4 | `SMV-CR-004` | fresh host + closeout | build、16-profile probe、只读 host replay、planning/full gate；恢复 default；一份 evidence；commit/push |

Failure routing：误选先修 skill metadata/profile 或删除 router 行为，不增加词法规则；同类反例两次回到 ownership 设计；stale/unknown/needs_activation fail-closed；host invocation 不可观测时标记 partial；未知工作树、profile 未恢复、P5 planning 回归、P6 manifest、host mutation 或 full gate 失败立即阻断。

Verification：按 correction spec 的 build -> focused tests -> routing/config/integrity contracts -> 16-profile fresh probe -> bounded host replay -> planning contracts -> one full gate 顺序执行。27-case corpus 只证明 repo discovery/policy；host replay 与 business `live_accepted` 单独分层。

## 9. Hierarchical capability discovery redesign

Goal：消除 profile-first cold discovery 的触发循环；由 resident metadata 触发专业 cold 请求，先展示 domain purpose，再由宿主语义选择 domain/candidate，最后进入确定性 policy 和完整 `SKILL.md` 冷加载。

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-HD-001` | baseline + architecture | default cold trigger 4/8 与强制 chain 8/8 分层；ADR-SMV-020；不恢复 lexical router |
| 2 | `SMV-HD-002` | domain discovery + compatibility | purpose/DomainHint/candidate domains；ProfileHint 兼容；focused router/verifier green |
| 3 | `SMV-HD-003` | fresh host acceptance | 32 selection + 8 cold-load；router/target raw read、policy、profile restore、tokens/duration |
| 4 | `SMV-HD-004` | product truth + closeout | PRD/architecture/roadmap/spec/manifest/README/evidence；one full gate；Git parity |

Failure routing：漏触发先修 resident description 并保护 native/no-skill negatives；domain/candidate 误选修 purpose/skill metadata；同类失败两次回到架构，不加 lexical ranking。profile 未恢复、P6 manifest、host mutation、未知工作树或 full gate failure 阻断收口。

Verification：`build -> affected Pester -> routing/config/integrity/planning contracts -> fresh host corpus -> one full gate -> default/P5/P6/Git boundary`。32/32 和 8/8 只声明 `host_evaluation_partial`；cold-load token 未下降，不写成成本优化或 business `live_accepted`。

Post-closeout follow-up：canonical inventory 增删/description/path 变化现在由 projection seam 写 ignored reconciliation signal；profile-only/no-op 不触发，宿主据 signal 进入既有 advisor/canary，而不是脚本静默改 profile。evaluator 已拆分 cached/uncached/tool rounds；两个 1-case A/B 否决了负收益的 combined shell-round 方案，保留 separate 正确性链与 focused replay 成本策略。本段不新增 track task count。

Natural-limit hardening：未知 domain 零候选、显式 skill 仍可 policy validate；candidate truncation 可见；current snapshot 覆盖静态 skill/MCP availability。验证使用 30-case deterministic corpus、相关 Pester 与本地 production-config replay，不新增 task/track，不把 JSON bytes 缩减写成 provider token 或 live acceptance。

Portable-catalog correction：projection 生成 router 相邻 catalog 并覆盖全部 canonical cold skill；专用 cross-repo test 从 repo 外 CWD 验证无 manifest/config/policy 耦合、非空 domain/candidate 与 zero-write，corpus verifier 保持 hermetic。该 correction 不新增 task/track，不自动修改 profile，不改变 32/32、8/8、M1/P6/live truth。

## 10. Profile reconciliation advisor

Goal：在 skill 新增、删除或 metadata 变化后，由宿主 AI 提出语义归属，仓库确定性发现 profile drift、校验 freshness/对象/预算/policy，并只输出 zero-write dry-run change-set。

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-PR-001` | ownership + contract | ADR-SMV-018、proposal/output/failure/retirement 边界完整；不恢复 lexical router |
| 2 | `SMV-PR-002` | planner + CLI/script + tests | current diagnostic pass；fresh proposal exact actions；negative findings fail-closed；zero-write |
| 3 | `SMV-PR-003` | product/planning truth | PRD/architecture/roadmap/spec/manifest/plan/todo/README/AGENTS 一致；P5/P6/M1 不变 |
| 4 | `SMV-PR-004` | ordered closeout | affected contracts + one full gate；default profile；一份 evidence；commit/push |

Failure routing：stale hash 重新生成 proposal；unknown/protected/no-op/conflict 修 proposal；预算超限减少 membership 而不提高 8,000 ceiling；同一 finding 两次回到 profile purpose。任何 `skills.json`/host mutation、P6 manifest、active profile 漂移、unknown worktree 或 full gate failure 阻断收口。

Verification：`build -> SkillProfileReconciliation.Tests.ps1 -> current advisor JSON -> routing/config/integrity/planning contracts -> one full gate -> Git boundary`。本 track 不执行 reviewed apply、M1 pilot 或 business live acceptance。

## 11. Bounded profile optimization canary

Goal：在 plan-only advisor 后，由当前宿主 AI 生成最小语义 proposal，再以非活动 profile canary、fresh-task replay、receipt 和失败回滚实现低打扰闭环；不恢复 lexical router，不把 `active_profile` 伪装成 Codex 原生热切换。

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-PO-001` | root cause + contract | FR-SEL-015/016、NFR-SAF-004、ADR-SMV-019 和官方 native boundary 完整；P5/P6 不变 |
| 2 | `SMV-PO-002` | handoff + transaction + replay | 最多 5 skill/10 action；active profile target fail-closed；atomic receipt/rollback；focused tests green |
| 3 | `SMV-PO-003` | host replay + closeout | 代表自然语言 fresh replay、恢复 default、产品/任务/evidence、唯一 full gate、Git parity |

Failure routing：stale/unknown/no-op/conflict 修 proposal；active target 改为新任务边界的非活动 canary；replay coverage/expectation 失败自动回滚；rollback target 漂移停止写入。同类语义失败两次回到 skill description/profile purpose，不增加 lexical 规则。

Verification：`build -> advisor/transaction/benchmark focused tests -> current advisor + benchmark plan -> profile/config/routing/planning contracts -> bounded real host replay -> one full gate -> default/P6/Git boundary`。host replay 只声明 partial，M1/P6/live acceptance 不在本 track。

Closeout：3/3 tasks `repo_verified`；72/72 affected tests、27/27 routing corpus、16/16 fresh profile visibility 和唯一 full gate 通过，`doc-coauthoring -> content` 的 6/6 replay 为 `host_evaluation_partial_pass`。当前/恢复 profile 均为 `default`；该 track 收口时 M1 未执行，当前独立 registry 已进入 collecting 0/10；P6 hold 与 business `live_accepted` 不变。
