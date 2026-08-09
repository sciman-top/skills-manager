# Host-native-first self-retiring engineering constitution design

**program_id**: `skills-manager-vnext`
**design_status**: `review_required_before_implementation`
**scope**: `repository_standard_path_only`
**decision_owner**: `user`
**semantic_coordinator**: `host_ai`
**executor**: `host_native_runtime`
**last_updated**: 2026-08-09

## 1. Decision

本项目把以下内容提升为同一组最高工程原则：

1. `host-native-first`：最大化宿主 AI 的原生推理、规划、编码、审查、协调和执行能力；本仓不得复制宿主已经拥有的语义选择、agent loop、模型/provider 路由、会话、权限、subagent、worktree 或调度能力。
2. `main-chain-first`：先跑通由用户、真实入口、关键 seam、可运行终态、直接证据和可回滚交付构成的最短真实主链，再按已观察失败稳定化、重构和优化。
3. `anti-overdesign`：没有真实重复、稳定外部协议、已证实风险或量化热点时，不新增抽象、治理层、adapter、schema、wrapper、测试矩阵或优化层。
4. `self-retiring`：本项目只在宿主能力不足时补足真实缺口；宿主能力增强、功能重叠、真实消费者消失或维护成本超过净收益时，相关能力必须触发有证据的弱化或退役处置；有兼容义务时先降级为兼容层，义务结束后最终退役。
5. `no-second-governance-plane`：不得为了执行上述原则再建立第二套治理系统、workflow runtime、scheduler、ledger、lease database、daemon、telemetry service 或中央 registry。

这些原则服从不可突破的保护顺序：

```text
user authority / safety / data integrity / compatibility / truth boundary
  > verified user outcome
  > host-native-first / main-chain-first / anti-overdesign / self-retiring
  > breadth / future flexibility / speculative performance optimization
```

## 2. Problem and evidence

现有 `AGENTS.md`、PRD、架构、Lean Delivery spec、Phase manifest、AgentWorkflow contract、planning verifier、full gate 和 CI 已分别表达上述语义，但还缺少一个窄且可追踪的实施设计，说明哪些内容属于长期原则、哪些进入任务合同、哪些可以机械阻断、哪些仍由宿主 AI 判断。

重复增加原则文档、总 verifier 或新 runtime 会制造新的双真源和维护面，直接违反本设计。实现必须复用以下现有 seam：

- `docs/product/skills-manager-vnext-prd.md`：产品 North Star 与稳定原则真源；
- `AGENTS.md`：仓库动作、门禁和回滚映射；
- `tasks/skills-manager-vnext-*.tasks.json`：当前 Phase、主链、任务和停止条件真源；
- `src/Domain/AgentWorkflow.ps1`：plain-object planning/admission contract；
- `scripts/verify-vnext-planning.ps1`：当前规划一致性 verifier；
- `scripts/verify-agent-workflow-advisory.ps1`：host ownership、zero-effect 和负向边界 verifier；
- `scripts/quality/run-local-quality-gates.ps1` 与 `.github/workflows/ci.yml`：唯一 closeout/full 编排路径；
- `tasks/skills-manager-vnext-lean-delivery-pilot.json`：真实任务 observe-only 净收益登记真源。

## 3. Goals

- 让 AI 编码任务在开始前声明真实用户结果、入口、当前主链 checkpoint、既有复用结论、最小方案、write set、最低充分验证和停止条件；只有 AI 能力、治理能力或长期维护面变更才要求宿主原生能力基线。
- 对新增 skill、plugin、MCP、adapter、schema 或长期维护面要求真实缺口、native baseline、消费者、维护成本和 retirement trigger。
- 保持宿主 AI 为唯一语义 coordinator；本仓只做确定性 schema、admission、evidence 和 safety guard。
- 让 `repo_verified`、host inventory/evaluation/invocation 与 `live_accepted` 保持独立证据层级。
- 让能力生命周期既能晋级，也能降级、兼容和删除；资产数量不是成功指标。
- 对 simple/direct-fix 保持轻量，不要求机械展开完整软件生命周期或生成多份 artifact。

## 4. Non-goals

- 不修改 Codex/Claude 宿主配置、hooks、权限、provider、auth、session、model 或 active profile。
- 不修改 GitHub branch protection、required checks 或远端管理策略。
- 不创建第二个 semantic router、agent coordinator、workflow engine 或治理 runtime。
- 不新增独立 constitution registry、通用 lifecycle database、telemetry service 或 dashboard。
- 不用代码行数、文件数、测试数、Agent 数或 token 数直接判定过度设计。
- 不把本设计、synthetic fixture、规划 verifier 或 repo gate 计作真实 pilot 收益。
- 不与当前并发中的 quality-gate timing/scheduler、P6 truth repair、watch retirement 或 host projection 改动混成一个实施切片。

## 5. Alternatives

### 5.1 Adopt: narrow contract through existing seams

在现有产品真源、task manifest、AgentWorkflow、planning verifier、full gate 和 pilot 上增加最低必要字段与负向合同。优点是小、可删除、无新运行时、与 host-native ownership 一致。缺点是语义价值判断仍需 AI 或责任主体裁决。

### 5.2 Defer: diff-aware structural scanner

通过扫描新增文件、抽象、测试层或 gate 数量生成 overdesign finding。该方案只适合未来有足够误用样本后作为 warning；现在硬阻断会产生大量假阳性，也容易被拆文件规避。

### 5.3 Reject: central constitution/control plane

建立独立 policy engine、registry、scheduler、reviewer 或 telemetry service。它会复制现有 verifier、宿主 runtime 和 Git/CI 职责，增加双真源、延迟和维护成本，违反最高原则。

## 6. Normative product wording

PRD 中只增加一个短的最高原则条款，作为现有 `PP-001` 至 `PP-013` 的优先级解释，不复制它们的正文：

> 在授权、安全、数据、兼容和真值边界内，本项目最大化宿主 AI 原生能力并优先交付最短真实主链；无真实重复、稳定协议、已证实风险或量化热点，不新增抽象、治理或优化层。本项目仅补宿主原生能力的真实缺口；当原生能力覆盖、功能重叠、消费者消失或维护成本超过净收益时，相关能力必须依据可复核证据进入弱化或退役处置，有兼容义务时先转为 compatibility-only/deprecated，义务结束后最终 retired。不得为执行本条款建立第二套治理或运行控制面。

`AGENTS.md` 只增加一条项目动作映射，指向 PRD、当前 manifest、现有 verifier 和 full gate；不复制完整产品条款。

## 7. Delivery admission contract

### 7.1 Reuse existing task fields

现有 task 字段继续作为基础：

- `id` / `goal` / `depends_on`；
- `write_set`；
- `implementation_steps`；
- `verification`；
- `rollback`；
- `done_when`；
- `stop_conditions`；
- `evidence_group`。

### 7.2 Minimum new planning fields

只对当前 Phase 的新任务或被本切片修改的任务要求以下字段：

```json
{
  "delivery_stage": "main_chain",
  "user_outcome": "用户通过真实入口可以完成的结果",
  "entrypoint": "真实命令、UI、接口或宿主入口",
  "main_chain_checkpoint": "本切片完成后可直接验证的主链节点",
  "reuse_decision": "adopt",
  "minimum_sufficient_verification": ["最低能证明本风险的验证"]
}
```

约束：

- `delivery_stage` 只允许 `discovery | main_chain | stabilize | refactor | release | operate`。
- `reuse_decision` 只允许 `adopt | adapt | defer | reject`。
- `main_chain_checkpoint` 必须指向当前 manifest 的主链和实际入口，不得使用 artifact 数量代替用户结果。
- `minimum_sufficient_verification` 不能把 full gate 复制到每个迭代任务；full 仍只在 closeout 运行一次。
- simple/direct-fix 可以使用一行 `user_outcome`、一个入口、一个 checkpoint、一个复用决定和受影响验证，不要求 `native_baseline`、完整 spec、ADR 或 lifecycle artifact。
- 只有任务改变 AI capability、治理能力或 7.3 所列长期维护面时，才必须增加 `native_baseline`：

```json
{
  "native_baseline": {
    "equivalent": "none_or_named_host_capability",
    "observed_gap": "当前真实缺口",
    "evidence": ["repo_or_official_evidence_reference"]
  }
}
```

### 7.3 Conditional complexity admission

只有新增以下长期维护面时才要求 `complexity_admission`：skill、plugin、MCP、adapter、schema、module seam、wrapper、长期 gate、daemon/service 或通用优化层。

```json
{
  "complexity_admission": {
    "kind": "two_real_repetitions",
    "evidence_refs": ["tracked_evidence_reference"],
    "native_equivalent": "none_or_named_capability",
    "real_consumers": ["consumer_a"],
    "maintenance_cost": "bounded_description",
    "retirement_trigger": "observable_removal_condition"
  }
}
```

`kind` 只允许：

- `two_real_repetitions`；
- `stable_external_protocol`；
- `proven_safety_or_data_seam`；
- `measured_hotspot`。

字段缺失或证据不可复核时保持 `design_only/defer`，不得通过 standard implementation admission。

## 8. Workflow ordering

模式不是瀑布，但以下依赖必须成立：

```text
Discovery evidence
  -> Main-chain checkpoint
  -> Stabilize observed failures
  -> Refactor characterized behavior
  -> Release exact-current-source full receipt
  -> Operate/live evidence or a new Discovery input
```

- `stabilize` 只能处理已观察失败或边界行为；不能以猜测扩展容错矩阵。
- `refactor` 必须依赖已通过的主链 checkpoint 和行为 characterization。
- `release` 必须使用最终稳定 source 的唯一 full gate receipt。
- 当前主链或用户结果变化时回到 `discovery/main_chain`，不继续局部补丁。
- 同一 `issue_id` 第二次失败时进入 clarify/re-plan，不继续无限重试或扩大范围。

## 9. Host-native ownership and non-overlap

标准责任保持：

```text
user intent        = authority owner
host AI            = semantic coordinator
skills-manager     = evidence and deterministic policy advisor
native runtime     = executor
Git/tests/probes   = truth adjudicator
```

每个新能力在 admission 前必须回答：

1. 宿主或官方是否已经提供等价能力？
2. 本仓是否仍有可验证的独特缺口？
3. 该缺口能否由现有 module/interface 直接解决？
4. 新能力是否引入第二语义 owner、双真源或宿主行为冲突？
5. 宿主能力覆盖后如何降级和删除？

宿主能力存在且没有独特缺口时，默认 `adopt` 原生能力并 `reject` 本仓重复实现。宿主能力只覆盖部分缺口时使用 `adapt`，把本仓限制为窄 adapter、verifier、migration 或 evidence seam。

## 10. Self-retiring lifecycle

### 10.1 Lifecycle

```text
candidate
  -> replay
  -> shadow
  -> bounded_canary
  -> reviewed_promotion
  -> retain | revise | compatibility_only | deprecated | retired
```

### 10.2 Retirement triggers

任一条件触发重新评审：

- 宿主出现稳定、可验证且当前 surface 可用的等价能力；
- 相对 native-only baseline 没有可复核净收益；
- 经有界观察和消费者盘点后确认真实消费者消失；仅仅缺少遥测或使用记录不能单独证明无人使用；
- 误触发、漏触发、人工纠正或失败成本上升；
- 维护成本、上下文、延迟、供应链或安全成本超过收益；
- 来源 stale、许可证或完整性风险不可接受；
- 当前能力只剩历史兼容价值。

模型版本升级、一次演示或静态 capability 宣称不自动证明覆盖。自动化可以发现候选、生成 comparison 和 retirement plan；运行路径的降级、迁移和删除仍要求 reviewed evidence、精确 write set、rollback 和 receipt。

### 10.3 Retirement sequence

```text
active
  -> compatibility_only/read_only (when compatibility is still required)
  -> migration and round-trip verification (when consumers or persisted state exist)
  -> deprecated marker (when a deprecation window is required)
  -> remove ordinary runtime path
  -> negative regression proving absence
  -> retain historical evidence
```

这些中间状态按真实消费者、兼容和数据义务选择，不为形式完整机械走全流程；没有消费者、持久化状态或兼容义务时，可以在 reviewed evidence、精确 write set、rollback 和 receipt 下直接退役。历史 spec/manifest/evidence 不重写为新状态。退役只改变当前 runtime、config、generated seam 和当前状态真源。

## 11. Deterministic enforcement

### 11.1 Planning verifier

扩展现有 `scripts/verify-vnext-planning.ps1`，不新增总 verifier。它只校验可机械判定内容：

- 新/修改任务的最小 planning 字段完整；仅适用任务要求 `native_baseline`；
- stage、reuse disposition 和 complexity kind 枚举有效；
- `stabilize/refactor/release` 依赖顺序成立；
- 新增长期维护面时 complexity admission 与 retirement trigger 存在；
- current main-chain、stop conditions 和 full receipt authority 未漂移；
- generated/cache/runtime 路径不进入任务 write set。

### 11.2 AgentWorkflow contract

`src/Domain/AgentWorkflow.ps1` 只在 existing TaskGraph interface 上承接必要的 stage/admission 投影；不读取网络、环境、时钟、host config 或 provider，不调度 agent。`agent-plan/agent-validate` 的 `provider_calls/native_mutations/writes` 继续固定为 0。

若 task manifest 已是当前任务真源，AgentWorkflow input 应引用或投影该任务，而不是再维护一份长期状态；测试必须覆盖冲突输入 fail-closed。

### 11.3 Full gate and CI

现有 full gate 已调用 planning 和 agent-workflow verifier，因此不增加新的 quality-gate step。CI 继续调用唯一 full gate。仓库内可以保证“标准路径被调用时 fail-closed”，但无法仅靠仓库文件证明 GitHub required-check/branch protection；后者保持本设计范围外。

## 12. Error handling

- 缺 native baseline、真实缺口或复杂度依据：`defer/design_only`。
- 宿主能力状态未知：保持 unknown，不按模型版本猜测已覆盖。
- 发现第二语义 owner、双真源或宿主冲突：阻断并缩减到 adapter/verifier/evidence seam。
- 主链未通但非产品 artifact 增长：停止并回到 main-chain checkpoint。
- 同一风险被多层重复证明：保留最低充分层，删除或降级其余证明。
- 当前 full receipt stale：只能报告 stale，不得复制历史 `passed`。
- repo evidence 不足以证明 host invocation/live acceptance：保持当前 truth level。
- retirement apply 失败：保持原 runtime path，使用本切片 rollback；不得留下半退役状态。

## 13. Verification design

### 13.1 Focused positive cases

- simple/direct-fix 使用最小字段且不声明 `native_baseline` 时通过；
- main-chain task 有用户结果、入口、checkpoint、native baseline 和最低验证时通过；
- 已证明稳定协议或两个真实消费者的新 seam 通过 complexity admission；
- compatibility-only retirement plan 保留迁移、round-trip、rollback 和历史证据。

### 13.2 Focused negative cases

- 缺 `user_outcome`、entrypoint 或 main-chain checkpoint；
- 将 artifact 数量写成用户结果；
- 主链未通过即进入 refactor/release；
- 新增 adapter/schema/skill 但没有 native baseline、消费者或 retirement trigger；
- 将模型升级或一次演示当作原生覆盖证据；
- 增加第二 semantic router、scheduler、registry 或 provider runtime；
- 把 full gate 复制进每个迭代任务；
- 把 repo/fixture evidence 提升为 host invocation/live accepted。

### 13.3 Closeout

实施期间只运行受影响 Pester 和 planning/agent-workflow contract。全部 source、fixture、manifest 和文档稳定后，只运行一次 repository full gate；通过条件是 exact-current-source full receipt 有效。真实业务收益继续由既有 M1 10-task pilot observe，不作为本次 repo contract closeout 的伪造证明。

## 14. Implementation slices

### Slice 1: constitution and contract

- PRD 增加最高原则与冲突优先级；
- `AGENTS.md` 增加一条项目动作映射；
- 当前 task schema/fixture 增加最低 planning 字段；
- planning verifier 与 focused tests fail-closed；
- 不触碰 quality scheduling、host、provider 或外部系统。

### Slice 2: AgentWorkflow projection

- 仅在 current manifest/TaskGraph 之间建立窄投影；
- 保持 zero-effect command envelope；
- 添加 conflicting duplicate truth 和 stage-order negative cases。

### Slice 3: lifecycle and closeout evidence

- 复用现有 pilot、disposition 和 change-evidence；
- 不创建 lifecycle registry；
- 运行 affected gates，文件稳定后运行唯一 full gate；
- 记录最大 claim 为 repo contract enforced，host/live 与真实净收益保持独立。

## 15. Acceptance

- 最高原则有唯一规范性正文和短项目映射，没有新双真源。
- simple/direct-fix 保持最小字段和最短反馈路径。
- 新增长期能力必须有 native baseline、真实缺口、复杂度依据和 retirement trigger。
- standard planning path 对缺失字段、错误 stage 顺序、第二治理面和 truth promotion fail-closed。
- AgentWorkflow 仍由 host AI 决策、native runtime 执行，repo command 零 provider/native/write effect。
- full gate 仍是唯一 closeout 编排，不新增重复 gate。
- 当前并发 quality/P6/watch 改动未被本设计切片修改、回退或提交。
- M1 未完成前不宣称真实效率或普遍净收益。

## 16. Rollback

- 设计阶段：只撤销本 spec commit。
- Slice 1：撤销 PRD/AGENTS/task/verifier/test 的本切片增量。
- Slice 2：撤销 AgentWorkflow 投影和对应 fixture/test，保留现有 v1 contract。
- Slice 3：撤销 lifecycle/evidence 增量，不删除历史证据。
- 任一切片失败都不回退当前并发改动，不修改宿主或远端配置。
