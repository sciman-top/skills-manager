# skills-manager vNext 工程架构

**program_id**: `skills-manager-vnext`
**architecture_version**: 1
**status**: accepted-direction
**最后更新**: 2026-08-09

## 1. 架构结论

当前实现继续采用“PowerShell 7 模块化单体 + build-time 单文件 bundle + 文件型 versioned contracts + host adapters”。曾评估的“versioned protocol + 可选 C#/.NET typed core + PowerShell thin compatibility shell”只保留为历史决策；TC0/TC1 `OperationPlan/Receipt v1` shadow PoC 已因零消费者、无可比返工净收益和持续 SDK/full-gate 成本退役，现有 PowerShell 仍是唯一运行真源。

本项目位于宿主和能力来源之间，负责本地 inventory、选择、plan、显式 apply 和 evidence；宿主继续负责 agent execution、auth、permission、session、plugin/connector runtime 和 native loading。

```text
Official directories / Git / local inputs / host inventory
                         |
                    Source adapters
                         |
        +----------------+----------------+
        |                                 |
 Capability Catalog                Rule Advisor
        |                                 |
        +--------- Desired State ---------+
                         |
                  Operation Planner
                         |
              explicit Apply + freshness
                         |
                    Host adapters
                         |
          repo verify / native probe / receipt
```

## 2. 当前架构事实

- `build.ps1` 按固定顺序拼装 `src/*.ps1`，输出根 `skills.ps1`。
- `skills.json` 同时承载 vendors、mappings、imports、targets、skill projection 和 MCP 配置。
- `src/Commands/Install.ps1`、`Mcp.ps1`、`AuditTargets*.ps1` 包含应用、IO、宿主适配和显示逻辑。
- Pester 承担 unit/E2E，Python verifier 承担 dependency baseline，PowerShell scripts 承担生成同步、完整性、路由和 doctor contract。
- `reports/skill-projection/current.json`、audit bundles 和 change evidence 已提供部分 manifest/evidence 模式。

当前问题既包含 bounded context、应用层和 IO seam 不够明确，也包含 PowerShell 动态类型、解析/引用规则、编码/进程调用和 AI 生成脚本容易产生的语法脆弱性。历史 5.1/7 双运行时窗口还放大了 quoting、encoding 和测试矩阵成本；当前已将受支持 runtime 收敛到 PS7-only。该收敛不能证明 PowerShell 永远是长期领域核心的最优载体，但当前先收紧 seam 和 protocol；历史 typed-core PoC 已退役，不再为保留技术选项而维持第二实现。

## 3. Bounded contexts

### 3.1 `CapabilityCatalog`

职责：发现和规范化 skill、plugin、MCP descriptor 的身份、来源、版本、兼容和 lifecycle。

不负责：profile 选择、宿主写入、OAuth、运行 MCP server。

核心类型：

```text
CapabilityDescriptor
  id
  kind: skill | plugin | mcp
  name
  source
  version_or_revision
  checksum
  license
  trust_tier
  lifecycle_status
  host_compatibility[]
  components[]
```

### 3.2 `SkillProjection`

职责：保留当前 skill source、canonical selection、alias、profile budget、Junction 和 Codex path enable/disable。

不负责：plugin 安装、规则优化、删除非受管技能根。

### 3.3 `McpGovernance`

职责：保留当前 MCP server/profile/target，生成受控工具面和宿主 projection plan。

不负责：服务托管、连接器账号、凭据保存或业务级验收。

### 3.4 `RuleAdvisor`

职责：发现规则、建立加载候选链、静态诊断、repo truth 核对、建议 surface、生成 patch plan。

不负责：中央规则库、无审阅的跨仓同步、权限 enforcement、Phase 1 中的任何写入。工作区自动发现生成当前 inventory/drift 和 target-set hash，不成为目标仓权威真源；Phase 2 follow-through 只消费 reviewed change-set。

核心类型：

```text
RuleDocument
  id
  host
  scope: global | repo | subtree | override
  responsibility: common | platform_delta | project_action | deterministic_enforcement | task_local
  path
  owner
  content_hash
  byte_size
  precedence
  source_of_truth
  findings[]
  verification_state
```

`RuleDocument` 不继承 `CapabilityDescriptor`。两者只通过 planner 的 `target_ref` 被操作。

规则全域写入采用轻量 saga，而不是跨仓分布式事务：

```text
reviewed change-set
  -> dynamic target-set snapshot
  -> preflight all (allowlist/target hash/target-set/lock)
  -> atomic apply one target
  -> persist action receipt
  -> next target or fail-fast
  -> resume from receipt / rollback one action
```

全局和项目目标都使用精确文件名 allowlist。目标仓文件仍是真源；控制仓只保存 review、plan、receipt、backup 和 evidence。仓内无关 dirty paths 在 plan/receipt 中观察并保留，只有目标规则文件 freshness 参与阻断。先前成功的目标不会因后续失败自动回滚，避免模拟跨 Git 仓的 all-or-rollback。

规则协同的最小分析单位不是某个固定 heading，而是 `RuleResponsibility`：

```text
RuleResponsibility
  constraint_id
  common_intent
  platform_deltas[]
  project_actions[]
  enforcement_refs[]
  coverage: covered | gap | conflict | duplicated | not_applicable
  evidence[]
```

`covered` 需要共同意图、适用平台差异和至少一个可执行项目动作互相兼容；只有共同规则或只有项目命令都不构成 1+1>2。结构 profile 只帮助发现，不改变宿主真实 precedence，也不替代 native probe。

### 3.5 `TargetAudit`

职责：扫描目标仓事实、用户画像、当前能力和推荐候选，为 capability/rule plan 提供证据。

不负责：把 AI recommendation 直接当作 apply authority。

#### 3.5.1 `ReferencePortfolio`

职责：把官方资料、第一方源码、本地参考棚和社区候选建模为可逆证据组合；管理 `discover / conditional-not-cloned / on-demand read-only / secondary / core-mainline / historical-compatibility / retire` 状态、来源锁定、消费者、采纳决定、刷新和删除前置条件。

不负责：成为 runtime/install 真源、通用联网爬虫、社区项目自动安装器、目标仓知识权威或 `D:\CODE\external` 中央管理器。宿主拥有语义搜索和外部读取；本仓只保存 reviewed metadata、确定性 policy、刷新工具和 receipt，并只写 manifest-owned 的 `skills-manager-references` 子树。

`ReferenceCandidate` 是尚未取得长期镜像资格的来源；`ReferenceShelfEntry` 是 manifest 管理的证据项；`RuntimeSource` 是 `skills.json` 管理的安装来源。三者生命周期独立，降级参考项不能隐式删除 runtime source，删除 runtime source 也不能靠 reference review 越级授权。

### 3.6 `OperationPlanning`

职责：为所有受管写入提供一致的 plan、freshness、apply、receipt 和 rollback envelope。

不负责：理解每个领域的业务决策。领域模块负责产生 actions 和领域 verification，planner 负责通用安全边界。

### 3.7 `PluginDistribution`

职责：消费调用方提供的 official/personal/workspace plugin 快照；验证 `.codex-plugin/plugin.json`、component path 和供应链字段；在 marked fixture 内导出一个 Codex skills-only package；输出分层 eval。

不负责：plugin install/remove/enable、marketplace mutation、OAuth/token、connector/MCP runtime、public submission、在线 model eval 或 host/session 管理。

首个实现只支持一个稳定外部协议和一个写入边界：`codex-plugin skills_only` + `.skills-manager-fixture`。其他 exporter 必须重新满足 docs/help/fixture 与重复分发证据。

### 3.8 `CapabilitySelection`

职责：把宿主原生 skill/tool 语义匹配放在第一层；只在用户显式查询能力、当前可见能力无匹配或需要跨 profile 冷发现时，按 caller-provided profile hint 返回有界候选，再对宿主明确选中的 capability 执行路径 containment、freshness、availability、side-effect、approval 和 activation policy。

不负责：自然语言分类、task/domain/confidence 推断、lexical ranking、二次模型调用、profile mutation、MCP/plugin install 或 enable、OAuth、provider/model/session routing、宿主 restart、工具执行和 live acceptance。

```text
visible skill/native tool
  -> host AI native semantic match
  -> use directly

no visible match / explicit capability discovery
  -> profile-scoped candidate discovery
  -> host AI adjudication with full request/context/negation
  -> deterministic capability policy
  -> native load/use or visible approval/activation step

CapabilityDiscoveryInput
  query
  profile_hints[]?
  host_selected_candidates[]?
  host_exclusions[]?
  projection_manifest
  host_snapshot?
  session_snapshot?

CapabilityDiscoveryPolicyResult
  decision_owner = host_ai
  semantic_routing_performed = false
  candidates[]
  selected[]
  excluded[]
  activation_plan[]
  task_type/domain = host_adjudicated
  confidence = null
  writes_performed = false
```

`query` 只作为审计上下文返回，不参与词法语义评分。普通文本中的 capability 名称也不构成选择授权，因为它可能位于否定句；只有 `$skill`/`@skill` 语法或宿主显式传入的 candidate 才能进入 policy。`ActivationPlan` 的 action 至少区分 `use_active_skill | load_skill | load_skill_with_approval | use_available_mcp | use_available_capability | request_approval | request_mcp_activation | request_activation`。只有 read-only skill，或已 available 且 `read_only | external_read` 的非 skill capability 可以 `auto_allowed=true`。

“无感切换”限定为同一任务内使用已可见、已可用且低副作用的能力；不等于静默修改 profile、安装 plugin/MCP、认证、写配置或执行外部写操作。profile 只在新任务边界作为预热候选包；当前任务发现不到合适能力时回退宿主原生推理，不阻塞主链。

#### Historical profile reconciliation compatibility

P5 曾实现 `host_ai proposal -> deterministic plan -> bounded canary -> replay/rollback`，但 P6 已取消 profile reachability authority，真实收益也未证明足以维持第二套语义归属流程。当前 active bundle 不再计算 unrouted/overlap、校验 proposal 或生成 membership change-set；所有 legacy proposal 和 canary `Apply`/`Accept` 入口固定返回 `status=deprecated`、零写入。

当前只保留三项有限兼容职责：`Get-SkillProfileCompatibilityView` 以 `reachability_authority=none` 读取旧字段，versioned migration 将旧结构搬入 `profile_compatibility`，历史 migration/canary receipt 可在 hash 与 backup 一致时执行 stale-safe rollback。它们不调用 provider、不切换 active profile，也不参与 native skill 选择；历史 spec/manifest/evidence 保留点时真值。

### 3.9 `LeanDeliveryAdvisory`

职责：在复杂 AI 软件交付任务中，将现有产品文档、task manifest、能力目录和证据解释为当前阶段的 Product Baseline、delivery mode、Slice Contract、责任 lens、停止条件与 capability DAG 建议。

不负责：执行 agent loop、持久化长期任务状态、调用模型、创建固定角色 Agent、调度 daemon、修改宿主配置、审批权限或把建议自动升级为 runtime policy。

该 context 在 maintenance track 中只有文档和 planning verifier，不新增 `src/` 模块或 runtime schema。逻辑视图复用现有字段：

```text
ProductBaselineView
  goal/user/problem/outcome        <- PRD goal + JTBD + task.goal
  scope/non_goals/constraints      <- spec + task.out_of_scope/preconditions
  success_and_truth_level          <- done_when + verification + evidence boundary
  open_questions/assumptions       <- spec decisions + checkpoint notes

SliceContractView
  task_id/mode/goal                <- task.id + plan slice + task.goal
  write_set/dependencies           <- task.write_set + task.depends_on
  tests/verification/rollback      <- existing task arrays
  checkpoint/stop_conditions       <- plan exit checkpoint + spec failure routing
```

不创建持久化 `ProductBaseline` 或 `SliceContract` 大对象；只有 10-task pilot 证明两个以上真实消费者需要稳定 machine-readable exchange 时，才评估 P5-local metadata，而且不得在 maintenance track 中升级 schema major。

完整生命周期数据流：

```text
rough product intent
  -> Discovery: baseline + <=3 material questions
  -> PRD / architecture / spec / roadmap
  -> task manifest + current Slice Contract
  -> capability selection + minimum ordered DAG
  -> host-native implementation loop
  -> affected verification + checkpoint
  -> Stabilize / Refactor only from observed defects or hotspots
  -> single closeout gate
  -> release / operate evidence
  -> reviewed learning candidate
  -> replay / shadow / canary / promote-or-retire
```

#### Lifecycle modes

| Mode | 进入信号 | 首要输出 | 退出 checkpoint | 默认禁止 |
| --- | --- | --- | --- | --- |
| `Discovery` | 用户目标、范围或验收仍会改变方案 | Product Baseline、最多三项关键澄清、可验证最小主链 | 用户/证据足以选择一个可逆方案 | 写大量代码、预建平台层 |
| `Main-chain` | baseline 稳定且首条价值链未跑通 | 最短端到端实现和一个可观察结果 | 真实输入沿主路径通过最低充分验证 | 完整治理矩阵、无消费者抽象 |
| `Stabilize` | 主链已通且出现具体缺陷/失败模式 | 根因修复、边界行为、必要测试 | 已观察失败不可复现且无关键回归 | 猜测式性能/容错扩张 |
| `Refactor` | 重复、热点或耦合已有量化证据 | 行为保持的结构改善 | characterization/contract 保持且复杂度证据改善 | 以目录美观为由重写 |
| `Release` | 产品切片已达到声明的完成等级 | 构建、发布、回滚和 truth-bound evidence | 唯一 closeout gate 与目标环境检查完成 | 把 repo gate 外推为 live acceptance |
| `Operate` | 产品已有真实用户或运行环境 | 监控、事件分流、低风险维护和反馈 | 事件闭合或形成新的 Discovery 输入 | 无授权生产写入、隐式自修改 |

模式不是线性瀑布；证据表明用户/问题/方案错误时回到 `Discovery`，主链回归时回到 `Main-chain`。只有当前模式改变能力需求时才重新路由，不在每个任务机械串联全部 workflow skills。

#### Bounded autonomy loop

```text
observe repo/user truth
  -> choose current mode and smallest safe slice
  -> execute within declared write set and authority
  -> run affected verification
  -> compare with checkpoint
     -> pass: record evidence and continue
     -> recoverable first failure: diagnose and retry once
     -> same issue second failure: re-plan baseline/slice
     -> scope/risk/auth/direction change: ask user
     -> destructive/live boundary: stop for explicit authority
```

循环有四类硬停止条件：write set/授权越界、用户价值或验收方向改变、同一问题两次失败、需要生产/凭据/付费/不可逆动作。token 使用量、固定轮数或“角色尚未发言”都不是继续执行的理由。

#### Responsibility lenses and multi-agent seam

主 Agent 是单一结果 owner；按风险选择 lens，而不是默认创建角色：

| Lens | 何时启用 | 最小问题 |
| --- | --- | --- |
| product/business | 用户、价值、范围或优先级不清 | 为谁解决什么，什么不做，最早可验证价值是什么？ |
| project/delivery | 多切片、依赖或外部协调存在 | 当前关键路径、checkpoint 和阻断是什么？ |
| UX/accessibility | 存在用户交互或内容呈现 | 关键旅程、空/错/等待状态和可访问性是否成立？ |
| architecture/data | 新边界、协议、持久化或迁移出现 | 最小稳定 seam、兼容、数据与回滚是什么？ |
| implementation | 已进入具体端/模块 | 怎样用现有模式完成主链且保持模块边界？ |
| quality/security | 已知失败模式、权限、供应链或敏感数据出现 | 最低充分证据与 fail-closed 条件是什么？ |
| release/operations | 需要发布、生产或长期维护 | 环境差异、观测、回滚、owner 和 live 验收是什么？ |

只有可独立、边界明确且不会写同一文件集的探索/测试/审查才分派多 Agent。每个共享 seam 保持单 writer；并行写入使用独立 worktree/branch，集成 Agent 负责冲突、全局验证和 truth closeout。角色名称不构成授权，子 Agent 结论仍需当前仓证据复核。

#### User intent surfaces

本项目只保留四类稳定用户意图，不要求重写现有 CLI：`Discover` 发现官方/社区/本地能力与仓库事实；`Advise` 生成最小组合、规则/规划建议与退役判断；`Transact` 仅在既有显式 token、freshness、backup/receipt/rollback seam 内执行受管投影或 change-set；`Verify` 分层证明 repo、host 与 live 状态。Lean Delivery 只消费 `Discover + Advise + Verify`，不会借 advisory 自动取得 `Transact` 权限。Goal、subagents、scheduled tasks、memory、App Server/SDK 继续由宿主所有；其原生能力覆盖本项目 seam 时触发适配或删除。

#### Skill learning and tool combination

经验演进状态为：

```text
task note -> skill_candidate -> replayed -> shadowed -> canary
          -> reviewed_promoted -> retained/revised/retired
```

晋级至少需要两个代表用例、一个失败/反例、明确触发/禁止触发、可验证输出和相对无 skill baseline 的净收益。未经 review 的模型总结只进入 task note；宿主原生能力覆盖、触发误报、维护成本高于收益或长期无消费者时退役。

工具组合保持松耦合：ChatGPT/Codex/Claude 是推理与执行主体；skills-manager 提供发现、选择、规则建议、规划一致性和 evidence；Obsidian 可作为用户拥有的知识库；Hermes/OpenHands/LangGraph 属于可选外置 runtime；Spec Kit/Superpowers 提供可借鉴的工作流结构。组合通过普通 Markdown/JSON/Git/明确导出交接，不共享隐式数据库，不复制 auth/session，不要求任一外置工具成为产品运行前提。

### 3.10 `EngineeredAgentWorkflow`

职责：把宿主原生 coordinator、只读设计评议、可执行切片、Git/worktree 隔离、candidate integration 和最终门禁解释为一个可审查工作流；对 task manifest、plan、Git 和 evidence 的现有字段做逻辑投影，并由 planning verifier 检查关键不变量。

不负责：创建或调度 worker、维护任务队列/lease service、持久化 agent 状态、接管 subagent/session、自动合并、替代 Git、授予写入/发布/生产权限。该 context 在 M0.2 仍只有文档、task/registry contract、verifier 和 tests，不新增 `src/` module 或 runtime schema。

```text
WorkSliceCoordinationView
  task_id
  result_owner
  mode: single_agent | read_only_panel | isolated_parallel | sequential_shared_write
  base_revision
  depends_on[]
  exact_write_set[]
  authority
  verification[]
  rollback[]
  stop_conditions[]

ToolDispositionView
  source/revision/license/trust
  problem_evidence[]
  native_equivalent
  real_consumers[]
  disposition: adopt | adapt | defer | reject
  integration_mode
  data_auth_write_boundary
  evaluation
  maintenance_cost
  retirement_trigger
  truth_level
```

这两个 view 不成为新的持久大对象。`WorkSliceCoordinationView` 来自现有 task/plan + 当前 branch/worktree/base commit；`ToolDispositionView` 进入 spec、reviewed evidence 或既有 M1 sample observation。只有两个以上真实消费者需要稳定机器交换时，才评估 P5-local additive metadata，且不得在 maintenance track 中升级 schema major。

#### Coordinator and design-panel protocol

```text
product goal / repo truth
  -> coordinator fixes baseline and decision question
  -> optional 2-3 read-only proposals (independent assumptions/trade-offs)
  -> coordinator synthesizes one accepted decision
  -> slice DAG + exact write sets + base revision
  -> admission
       single agent, or
       isolated worktree writers with disjoint paths, or
       sequential single writer for shared seams
  -> candidate commits/patches
  -> topology-ordered integration by one owner
  -> affected gates
  -> one full closeout gate + truth boundary
```

设计 panel 只产生候选论证，不取得修改 spec、代码、issue、外部系统或 live 状态的权限。coordinator 负责消解冲突、明确未决问题和保存最终决定；“多数 Agent 同意”不是证据，仓库事实、官方协议、测试和用户目标才是裁决输入。

#### Write-set admission and lease semantics

并行 admission 必须同时满足：任务依赖已满足；base revision 固定；每个 writer 有一个结果 owner；tracked/untracked/generated/external write set 均已声明；路径互斥可机械或人工复核；每个 candidate 可独立构建/测试/丢弃；集成顺序和最终 owner 已确定。任一条件不满足就使用单 writer 或串行。

`lease` 在本设计中是 coordinator 发出的有界 admission claim：

```text
owner + task_id + exact_write_set + base_revision
      + issued_at + expires_or_recovery_condition + revoke/reassign rule
```

它不是 OS 文件锁、Git 功能、成功承诺或自动仲裁。当前实现复用宿主任务/agent assignment、plan/handoff 和 worktree/branch；不落独立 lease registry。过期不会删除 candidate，reassign 前必须确认旧 writer 已停止并复核 worktree/branch/target hash，避免两个活跃 writer 继续写同一路径。

以下写入默认串行：同一文件或目录所有权不清；同一生成链的 source/generated 对；schema + migration；共享 lock/config；Git index/ref；同一外部 API/数据库对象；依赖前序输出才能确定内容的任务。仅“Git 能合并”或“模型认为冲突概率低”不能批准并行。

#### Git freshness and CAS semantics

Git 是版本真值主干、candidate transport 和 integration evidence。CAS 只取其严格含义：例如 `git update-ref <ref> <new> <old>` 或 remote `--force-with-lease` 在 ref 仍等于预期 old object 时才更新；文件级 freshness 继续使用 `before_hash`。`Git CAS is not a file lock or task queue`：它不排队文件编辑、不提供公平 lease、不知道业务 owner，也不意味着“谁先提交谁说了算”。stale/merge conflict 只是在 admission 失败后检测问题，不能替代 coordinator 的单 writer 和集成裁决。

candidate 集成顺序固定为：验证 candidate 的 base 与 declared write set；检查目标分支和相关文件 freshness；按依赖顺序 merge/cherry-pick/apply；由 integration owner 处理冲突并运行 affected verification；全部稳定后才运行唯一 full gate。子 Agent 的提交、测试 pass 或 ref 更新成功最高只证明 candidate 局部状态。

#### Tool-stack doctrine and adapter admission

| Surface | 默认职责 | 何时增加 | 不得替代 |
| --- | --- | --- | --- |
| prompt/thread | 一次性目标、假设、write set 与授权 | 当前任务需要 | 持久仓库规则 |
| `AGENTS.md` | 稳定仓库约定、命令、门禁和 review expectation | 跨会话重复且仓库特有 | 权限系统、长 runbook |
| skill | 可复用、窄触发、可验证 workflow | 至少两个代表任务 + 反例 + baseline 净收益 | 通用模型推理、实时数据 |
| plugin | 可安装分发的 skills/tools/hooks/MCP bundle | 已有重复分发对象与供应链 owner | marketplace/runtime/auth |
| MCP/connector | 实时外部数据和授权动作 | 任务确需外部 current truth/action | repo 文档、静态 workflow |
| hook/script/CI | 可重复 mechanical enforcement | prose 规则重复失效且命令 seam 稳定 | 语义产品判断 |
| Git/worktree | 版本真值、candidate 隔离、集成与回滚证据 | 所有代码写入主链 | scheduler、文件 lease、live acceptance |
| knowledge/code-graph adapter | 只读补充检索、关系或影响分析 | 两个独立真实任务证明 repo-native baseline 不足 | 源码/任务/验收真源 |

当前 GPT-5.6 默认投影采用轻量组合：宿主原生 Plan、Goal、Review、agent 和 worktree 控制不再由固定 skill 链复制。`using-superpowers`、`brainstorming`、`writing-plans`、`executing-plans`、`subagent-driven-development`、`dispatching-parallel-agents`、`using-git-worktrees`、`requesting-code-review` 和 `finishing-a-development-branch` 从 native discovery mappings 退役；vendor checkout 仍可作为只读参考，不等于安装或卸载宿主能力。保留 `systematic-debugging`、`verification-before-completion`、`receiving-code-review` 等窄 validator，并用 reviewed patch 将 `test-driven-development` 收窄到显式 strict TDD，将 `research` 收窄到 decision-relevant、read-only、显式持久化。该组合由 `config/native-skill-activation-corpus.json` 的正/负样本和 `verify-capability-routing.ps1` 验证，不能越级证明 host invocation 或 live acceptance。

知识库/代码图 adapter 的 admission 必须一起证明：目标语言和关系类型确实覆盖；最小 read root 与敏感数据策略；index source revision、captured_at 和 stale/rebuild 行为；CPU/RAM/disk/token/latency baseline；package/revision/license 与外部调用；zero-write/read-only canary；卸载、索引删除和回退 repo-native `rg`/symbols/tests/docs 的路径。任一项未知则 `defer`，不得因可视化效果或 star 数进入默认 profile/MCP。

当前参考 disposition：Trellis 适配 repo-based spec/task/journal，但 defer AGPL/自动控制面安装；AGOS 适配 `write_scope`、candidate/ledger/merge-gate 词汇，但 reject Alpha runtime 接管；OptSkills 只适配 replay/distill/eval/checkpoint 原理，不把数学优化系统当通用 workflow upgrader；GBrain、CodeGraphContext、Understand Anything 都保持 external/defer，直到真实任务、PowerShell/语言覆盖、隐私和资源门禁成立。“souljourney lightweight workflows”来源未唯一定位，按 unknown source fail-closed。

### 3.11 Retired `ModelAndAgentPolicyAdvisor`

历史 M0.3 和 Agent Workflow advisory 曾把通用 TaskGraph、模型 proposal、并行 admission、FailurePacket 与 Radar 兼容解析接入仓库。该面没有发现本仓外消费者，且其职责已由宿主原生 Plan、Goal、模型选择、subagent/worktree 和失败恢复覆盖，因此当前 source、CLI、fixture、tests、verifier 与默认 gate 全部删除。

历史 spec、manifest 和 evidence 原样保留用于追溯，不进入 build 或当前 truth source。当前架构只保留一条负向边界：skills-manager 可以为自身 capability/rule/projection 写入提供领域专属 plan/receipt/rollback，但不得重建通用 AI 工程编排、模型路由、agent admission、Radar 或第二治理面。宿主行为和业务效果仍由宿主/真实工作流独立取证。

### 3.12 Retired `TypedCoreBoundary`

TC1 的 `operation_contract_validation_v1` shadow 实现已删除。其历史合同证明了 PowerShell/C# parity，但没有证明生产迁移、AI 返工下降或分发净收益；当前不保留 C# source、SDK pin、shadow verifier/test 或第二实现。`PowerShell remains a compatibility shell, not the domain-policy source of truth` 只作为历史目标边界保留，不描述当前实现。

未来若出现新的、无法由窄 PowerShell seam 解决的独立失败，必须重新证明真实消费者、对比基线、分发/回滚和单一实现 owner；在此之前，versioned protocol、plain-object validator 和现有 PowerShell/Pester 是唯一当前路径。

## 4. 目标源码结构

结构按渐进迁移建立，不要求 Phase 0 一次移动全部旧函数：

```text
src/
  Domain/
    Capability.ps1
    RuleDocument.ps1
    OperationPlan.ps1
    Receipt.ps1
  Application/
    CapabilityInventory.ps1
    RuleAdvisor.ps1
    OperationPlanner.ps1
  Adapters/
    Sources/
      GitSource.ps1
      LocalSource.ps1
      OfficialDirectorySource.ps1
    Hosts/
      CodexHost.ps1
      ClaudeHost.ps1

      GeminiHost.ps1
      TraeHost.ps1
  Infrastructure/
    JsonFiles.ps1
    Hashing.ps1
    AtomicWrite.ps1
    Redaction.ps1
    NativeProcess.ps1
  Commands/
  Main.ps1
```

迁移规则：

- 新文件先由 `build.ps1` 按依赖顺序加入 bundle。
- 旧 public/CLI function 保留薄 wrapper；每个切片只迁移一个有测试覆盖的 seam。
- 不为了目录对称创建空模块。
- 不引入 PowerShell class hierarchy；优先使用 plain object + validator function，维持窄 seam 和确定性 JSON 合同；无需再为 PS 5.1 或已退役 typed-core candidate 维持双实现。
- 领域函数尽量 pure：输入对象，返回对象；IO、Write-Host、exit 和环境变量读取留在 adapter/command 层。

## 5. OperationPlan contract

### 5.1 Plan

```json
{
  "schema_version": 1,
  "operation_id": "op-<timestamp>-<nonce>",
  "domain": "mcp|skill_projection|rules|plugin",
  "mode": "dry_run|apply",
  "created_at": "RFC3339",
  "source_revision": "optional git revision",
  "targets": [
    {
      "target_ref": "stable domain identifier",
      "path": "absolute or repo-relative normalized path",
      "before_hash": "sha256 or absent",
      "desired_hash": "sha256",
      "owner": "domain adapter"
    }
  ],
  "actions": [
    {
      "action_id": "stable within plan",
      "type": "create|update|delete|native_command",
      "target_ref": "...",
      "summary": "redacted summary",
      "risk": "low|medium|high"
    }
  ],
  "preconditions": [],
  "verification": [],
  "rollback": []
}
```

计划不保存 token、完整连接串、OAuth material 或未脱敏进程参数。

### 5.2 Freshness

Apply 前必须逐目标检查：

1. path 仍在本次授权 root 内。
2. target owner 与执行 adapter 一致。
3. 当前 hash 与 `before_hash` 一致；原本不存在的目标仍不存在。
4. source/config revision 未漂移，或领域 validator 明确允许 additive drift。
5. 所需 native CLI/version/capability 仍满足 precondition。

任何失败都返回 stale/blocked，不部分写入未开始的 action。

### 5.3 Receipt

```json
{
  "schema_version": 1,
  "operation_id": "same as plan",
  "status": "dry_run|applied|partial|failed|rolled_back",
  "started_at": "RFC3339",
  "completed_at": "RFC3339",
  "actions": [],
  "backups": [],
  "verification": {
    "static_validated": "pass|fail|not_run|not_applicable",
    "repo_gates_passed": "pass|fail|not_run|not_applicable",
    "host_loaded": "pass|fail|not_run|not_applicable",
    "live_accepted": "pass|fail|not_run|not_applicable"
  },
  "rollback": []
}
```

`host_loaded` 不得由静态配置解析自动置为 pass；`live_accepted` 不得由 native list/smoke 自动置为 pass。

## 6. 写入与事务

- Repo 内文件：写临时文件、解析验证、atomic replace、保留 before hash。
- 规则 repo apply：CLI 根必须与 plan 中 Git 根完全一致，只接受 `AGENTS.md`、`AGENTS.override.md`、`CLAUDE.md`；create/update 使用不同 freshness 前置条件和 `APPLY_RULE_REPO_PATCH` token。
- Host-local 文件：限制在 adapter 声明的受管块/路径，写前备份到 host-local ignored backup root。
- Native CLI：记录经过脱敏的 argv、exit code 和关键输出；优先原生命令而非手写完整宿主配置解析。
- 多目标 operation：先完成全部 preflight，再按 action 顺序写；出现失败后仅回滚本 operation 已应用 action。
- 不用 Git reset/checkout 作为产品 rollback；rollback 是精确文件/受管块恢复。
- 运行态 plan/receipt 默认写入忽略目录，只有无敏感信息的 change evidence 可提交。

## 7. Host adapter contract

每个 host adapter 必须声明：

| 字段 | 含义 |
| --- | --- |
| `host_id` | `codex`、`claude`、`gemini`、`trae` 等稳定 ID |
| `supported_surfaces` | skills/plugin/MCP/rules 中真实支持的集合 |
| `read_paths` | 允许读取的文件/目录 |
| `managed_write_paths` | 允许写入的精确路径或受管块 |
| `native_commands` | list/install/enable/verify 等已由 help 证明的命令 |
| `trust_boundary` | 用户级、项目级、managed/admin 或 hosted boundary |
| `activation_boundary` | 当前 session、fresh session、restart 或 unknown |
| `verification_levels` | adapter 能真实证明的最高层级 |

适配原则：

- Codex/ChatGPT 的 public product 语义以官方 manual/docs 和当前可调用能力为准。
- ChatGPT hosted surface 不继承本机文件或 sandbox；没有 connector/plugin/API 证据时不得声称已投影。
- Plugin install/enable 优先调用官方目录或 CLI；本项目不反向生成官方商店状态。
- 不支持的能力返回 `platform_na`，不通过隐式 fallback 写其他配置。

## 8. Rule advisor pipeline

```text
Discover -> Classify -> Build candidate load chain -> Parse -> Diagnose
         -> Verify repo facts -> Select smallest surface -> Produce findings
         -> Patch plan (Phase 2) -> Explicit apply -> Fresh native probe
```

诊断规则分四类：

1. `structural`：文件名、scope、precedence、size、BOM、wrapper、required headings。
2. `semantic`：重复、冲突、层级错位、不可执行表述、把建议当权限。
3. `repo_truth`：命令/path/gate 与当前代码、CI、README 不一致。
4. `host_truth`：官方加载语义、config/help/schema 或 native probe 不支持。

责任覆盖另输出五态：`covered`、`gap`、`conflict`、`duplicated`、`not_applicable`。它与 finding severity 分离，避免把“结构不同”直接判为错误。

Semantic findings 在没有 deterministic evidence 时只能是 recommendation，不作为 blocker。命令/path/encoding/schema 等 deterministic finding 才能 fail gate。

默认 profile 可以建议 common/platform/project 分区、全局与项目体量预算及薄 wrapper，但 profile 必须可配置。宿主官方加载模型、目标仓规模或真实差异不匹配时，应给出 `adapt` 或 `defer`，不能为了模板一致性改写仓库。

根规则内容再按变化频率分层：稳定 `normative` 约束和 `advisory` 入口留在全局/项目根；项目命令、路径、阻断和回滚属于 `project_action`；任务计数、Phase gate、host/live 状态属于 dynamic state，只在 manifest/spec/evidence 维护并在执行前 fresh read。`RuleEstate` 对当前 2.0 profile 静态校验 A/C/D parity、B delta 独立、release、预算、项目 `1/A/B/C/D` 与 Claude 首行 wrapper；它不推断语义正确性，也不把 `filesystem_applied` 提升为 `host_loaded/live_accepted`。

## 9. 配置与 schema

- `skills.json` 在兼容窗口内继续是 skill/MCP runtime truth，不加入 rules 文本或 host auth/model 设置。
- Phase 0 为 `skills.json` 建立 schema 和 migration/version policy；先 observe 再 enforce。
- Rule advisor 配置只在 Phase 1 有真实字段后建立独立文件，禁止预建空的万能 `rulesets.json`。
- Operation plan/receipt 分别拥有独立 schema version。
- task manifest 属于 planning contract，不属于产品 runtime config。

## 10. 技术栈决策

### 10.1 当前条件下的最优性

不存在脱离目标、约束和时间尺度的单一“全局最优技术栈”。这里把全局最优定义为：在所有已知目标上位于 Pareto 前沿，并保留最大未来选择权的参考架构；任何一项继续改善都会显著损害成本、可靠性、兼容、交付速度或可逆性中的至少一项。

若暂时忽略本仓迁移成本，一个更接近全局最优的长期参考形态是：protocol-first 的稳定 domain contracts、可替换的 source/host adapters、无宿主状态的 planning engine、显式事务/证据协议，以及按真实规模选择的 CLI/TUI/API 和可选本地索引。跨平台 typed core 仍是可重评方向，但不是当前 backlog；database、daemon、remote control、extension SDK 等只有触发条件成立后才进入实现。

当前约束下的适配性最优把已验证事实纳入目标函数：Windows-first、现有 PowerShell/Pester 投资、单文件便携分发、当前用户规模、CLI/Junction/Git 密集工作和兼容成本，同时正视 AI 生成 PowerShell 的解析、动态类型、quoting、encoding 和 native-process 成本。已通过 PS7-only 删除双运行时差异成本；当前运行真值仍是 PowerShell 7。历史 typed-core PoC 已退役，当前优先收紧 protocol/validator seam，不保留第二实现。

| 维度 | 全局最优参考 | 当前适配性最优 |
| --- | --- | --- |
| 优化范围 | 已知及合理未来场景 | 当前用户、仓库和近两个 Phase |
| 迁移成本 | 可作为长期投资处理 | 作为真实高权重成本 |
| 不确定性 | 用可替换边界保留选择权 | 延迟未被证据证明的能力 |
| 技术选择 | 可接受 typed core/多入口/可选索引 | 当前 PowerShell + versioned protocol；typed core 仅 future re-admission |
| 验收 | 跨平台、规模、生态和演进性 | 兼容、门禁、可回滚和真实工作流 |
| 主要风险 | 过早平台化 | 被当前实现锁死、错过重评时点 |

| 方案 | 现有兼容/迁移风险 | Windows 与 native CLI 适配 | 分发复杂度 | 长期类型/并发能力 | 当前决定 |
| --- | --- | --- | --- | --- | --- |
| PowerShell 模块化单体 + 单文件 bundle | 高兼容、低迁移风险；AI 生成/维护脆弱性继续累积 | 高 | 低 | 中 | 当前运行真源；冻结新增复杂领域语义 |
| C#/.NET typed core + PowerShell thin shell | 中；需 protocol、双跑 corpus、wrapper 与分发迁移 | 高 | 中；可 framework-dependent 或 self-contained | 高 | 历史 PoC 已退役；新独立失败和净收益证据出现后重评 |
| C#/.NET 全量重写 | 低兼容；一次性迁移/回归风险高 | 高 | 中 | 高 | 拒绝；只允许逐 seam strangler migration |
| TypeScript/Node CLI | 中低兼容；增加 Node/npm/runtime/打包 | 中 | 中高 | 高 | 当前拒绝；宿主 UI/plugin 成为主面时重评 |
| Python CLI/core | 中；venv/解释器/打包/Windows path/encoding 增加部署面 | 中 | 中高 | 高 | 只保留数据/eval helper，不作为默认核心 |
| Rust native CLI | 低兼容；团队/FFI/构建迁移成本高 | 高 | 中 | 很高 | defer；性能/单文件安全瓶颈有证据时重评 |
| daemon/API + database | 破坏 local single-process 边界 | 中 | 高 | 高 | 无需求证据，拒绝 |

改进方向不是重写，而是依次完成：纯 Domain contract、Application orchestration、Infrastructure/Host adapter seam、结构化 plan/receipt、兼容 wrapper 和 characterization tests。typed-core PoC 曾完成但因没有生产/仓外消费者和净收益证据而退役；只有新的独立失败再满足 correctness、AI edit failure/rework、性能、分发和回滚净收益时，才重新准入一个可删除 seam。

选择算法固定为：先列 hard constraints 和不可接受结果；再比较满足约束方案的用户价值、总拥有成本、风险、可逆性和 option value；删除被支配方案；选择能完成下一真实里程碑的最小 Pareto 方案；最后为未选择的更重方案记录量化重评触发。全局参考用于检查方向，适配性方案用于决定当前实现。

### 10.2 运行与工程工具

- Runtime：PowerShell 7-only；最低 7.0、推荐 7.6 LTS。`src`、generated bundle、installer、CMD wrapper、CI、tests 和 subprocess 只允许 `pwsh`，缺失时 fail-closed。
- Source/build：`src/*.ps1` 模块化源码 + `build.ps1` 确定性 bundle + 根 `skills.ps1` 便携入口。
- Typed-core candidate：历史本机探针和 TC1 分发观测只作历史证据；当前仓库不 pin .NET SDK，不保留 C# candidate。新的候选必须先完成独立 admission，不能由旧 PoC 状态自动恢复。
- Contracts：UTF-8 JSON、显式 `schema_version`、plain object validator 和稳定 finding/exit contract；具体 schema validator 在 `SMV-P0-003` 以当前依赖事实选定。
- Tests：Pester 4.10.1 unit/E2E、fixture/golden/characterization/fault injection，以及 Python dependency baseline verifier。
- Distribution/state：Git、lock/manifest、文件 hash、ignored plan/receipt/backup；不增加数据库或常驻服务。
- Integration：优先 native CLI/plugin/connector，缺少原生入口时才使用精确 scoped file adapter。

### `ADR-SMV-001 Keep PowerShell modular monolith`

决定：作为当前实现与兼容期决策，继续使用 PowerShell、按模块 seam 演进并保留单文件发行；ADR-SMV-027 的 typed-core PoC 方向已完成一次历史评估并退役。ADR-SMV-001 不再被解释为“所有未来逻辑永久使用 PowerShell”，但当前没有第二实现。

理由：当前主要工作是 Windows 文件、Git、Junction、CLI 和宿主配置；现有测试/发布投资大，重写不会直接改善产品价值。

重评触发：非 Windows 成为核心使用量、需要常驻 API/并发服务、类型/性能缺陷无法通过 seam 修复，或 AI 生成 PowerShell 的解析/兼容/返工成本已有重复真实证据。最后一项已满足 planning/PoC 准入，但未满足生产迁移准入。

### `ADR-SMV-002 PowerShell 7-only runtime`

决定：开发、CI、安装、CLI wrapper、生成 bundle 和受管子进程只支持 PowerShell 7；最低 7.0、推荐 7.6 LTS。删除 Windows PowerShell 5.1 fallback、兼容 smoke 和现行支持声明，缺少 `pwsh` 时 fail-closed。

理由：项目已经以 PS7 完成 build/test/full gate，5.1 只提供重复维护成本而不再提供独特产品价值。单一 runtime 能直接减少 AI 生成脚本在 parser、quoting、encoding、native process 和错误传播上的分叉。此决定是项目支持策略，不是“微软已停止支持 Windows PowerShell 5.1”的事实声明。

迁移/回滚：消费者 side-by-side 安装 PowerShell 7 并把调用改为 `pwsh -NoProfile ...`；发布前由 runtime-policy verifier 证明零活跃 fallback。回滚只撤销本迁移切片并恢复最后已验证版本，不允许在当前代码中临时重新启用 `powershell.exe`。

### `ADR-SMV-026 Host-owned task and model policy`

决定：用户拥有目标与不可逆授权，宿主 AI 负责语义、任务图、串并行、模型/推理强度、失败恢复和最终综合；skills-manager 不再输出通用 model policy、agent admission 或 escalation 建议，只约束自身产品领域的确定性写入边界。

理由：宿主拥有完整对话、当前可用模型和执行线程；在本仓复制 scheduler/router 会产生过期价格/能力数据、双重控制面和权限漂移。确定性 verifier 仍可阻断 DAG cycle、shared write overlap、stale base/snapshot、unknown model、缺验证/owner/预算和 truth 越级。

### `ADR-SMV-027 Protocol-first typed core with PowerShell thin shell`

决定：当前 PowerShell 运行真值保持不变，但新复杂领域语义不再默认追加到脚本单体。先稳定 versioned JSON/exit/finding protocol，再以 C#/.NET read-only PoC 证明 typed core；接受后按一个 seam 一次的 strangler pattern 迁移，PowerShell 保留安装/兼容/host adapter shell。

理由：C#/.NET 与 Windows、native CLI、single-file/self-contained 分发和现有 .NET SDK 最匹配，能用编译器、nullable/类型、结构化并发和成熟测试降低 AI 生成脚本的语法/运行时缺陷；相比 Node/Python/Rust，它在本仓的 runtime 增量、Windows 适配和迁移风险上处于更合适的 Pareto 点。直接重写会丢失现有 CLI/Pester/兼容证据，因此明确拒绝。

PoC acceptance：同一 corpus 的结构化输出/exit/finding parity；至少两个真实 caller；AI 修改的一次通过率、返工、测试时间和启动/分发成本有 baseline；旧 wrapper 与 rollback 通过；无双写/双配置/daemon/provider/host mutation。任一项失败则删除 PoC 并继续收紧 PowerShell seam。当前 TC1 已按该删除条件退役。

### `ADR-SMV-028 Operation contract validation as the first shadow seam`

决定：TC0 选择 `OperationPlan/Receipt v1` validation 作为第一个 typed-core seam；TC1 用 .NET 10 LTS + `System.Text.Json` 的 package-free console 通过 versioned stdin/stdout JSON shadow 运行。生产 PowerShell、CLI 和 bundle 不引用 candidate；TC2 前 PowerShell 保持 authoritative。

理由：该 seam 是纯 in-process module，曾有三个内部 caller、四个固定 fixture 和稳定 finding/exit contract，能以小接口隐藏足够验证复杂度。4/4 corpus 与 4/4 protocol negative 已通过，但 self-contained 73–80 MB、无生产/仓外消费者且未证明 AI 返工净收益；因此 TC1 仅作为历史 shadow 结果保留，当前实现已退役。

### `ADR-SMV-029 Runtime-independent agent workflow advisory contracts`

决定：在不改变 ADR-SMV-026 ownership 的前提下，把 M0.3 文档态合同实现为三个窄 seam：`Domain/AgentWorkflow.ps1` 以 TaskGraph v2 校验 delivery stage、admission scope、用户结果、主链 checkpoint、原生基线、按需 complexity/retirement evidence、`execution_mode` 与 canonical task ID，同时只读兼容 TaskGraph v1 与历史 RadarSnapshot v2；`Application/ModelAndAgentPolicy.ps1` 生成 one-group barrier waves，以 `max_parallel=2 / max_delegations=4 / max_xhigh_per_wave=1` 约束委派，并用 completion + execution receipt 绑定实际 custom agent/model/effort/terminal/token observation，同时保留三档 Sol host proposal validation 和 bounded escalation；`Commands/AgentWorkflow.ps1` 只读取仓内 JSON 并输出 `repo_advisory_only` envelope。FailurePacket 保持 v1；`agent-plan/agent-validate` 的 effect counters 固定为 0，实际 spawn/wait/steer/worktree/model application 继续由 Codex native runtime 执行。

理由：仅文档无法机械阻止循环依赖、伪造 completed task、路径父子重叠、serial/high-risk 混 wave、过量 delegate/双 xhigh、缺 proposal 的静默 medium fallback、proposal 与实际 spawn 错配、终态仍显示 processing、stale upstream Radar、空 local outcome 屏蔽失败、无 FailurePacket 升档或 corrected retry 自动并发；引入 scheduler/provider runtime 又会复制宿主能力。小型 plain-object contract 能复用既有 OperationPlan finding/redaction helper、PS7 bundle 和 full gate，并为未来 typed-core seam 保持稳定 JSON 边界。token usage 当前只观察，不实现硬熔断。

退役/扩展：Codex 原生若公开等价的可验证 TaskGraph/admission/model proposal/failure trace，本 seam 缩减为 compatibility verifier 或删除；真实 M1 replay 无相对 native-only 净收益时同样删除。Radar live fetch、跨进程 coordinator、provider routing 或 host config mutation 不在本 ADR 内，只有 P6 admission 和用户新授权后才可评估。

当前处置（2026-08-09）：原生 Plan/Goal/subagent/worktree 已覆盖核心职责，且仓库外消费者搜索为零；retirement trigger 已满足，三个 source seam、CLI、fixtures、tests、verifier 和默认 gate 均已删除。历史 spec/manifest/evidence 保留。

### `ADR-SMV-003 Separate domain models`

决定：Capability、RuleDocument、Profile 不建立通用继承树；共享 OperationPlan/Receipt envelope。

理由：三者 identity、lifecycle、trust 和 apply 语义不同；过早统一会制造 nullable mega-object。

### `ADR-SMV-004 Official-first host integration`

决定：先调用 native CLI/plugin/connector；只有无原生入口时才维护精确配置段。

理由：降低宿主格式漂移、认证复制和深耦合。

### `ADR-SMV-005 No service or database`

决定：当前不建设 daemon、Web API、数据库、RBAC 或远程控制面。

理由：单用户本地工作流没有证据需要这些成本；文件、Git、lock 和 receipt 足够。

### `ADR-SMV-006 Advisory-first rules`

决定：Phase 1 规则能力严格只读；Phase 2 才允许显式单目标 apply。

理由：规则优化包含语义判断，自动跨仓写入的误伤和真值漂移风险高。

2026-08-02 follow-through：`rule-estate-audit` 将动态 Git 目标、registry drift、global common/platform delta、规则 release 和责任覆盖汇总为 zero-write report；`rule-estate-plan/apply/rollback` 通过 fixture/E2E 与一次用户显式授权的真实 11 文件 rollout，证明 reviewed global/project multi-target plan、全量预检、逐目标 receipt、fail-fast、resume 与单目标 rollback。Codex fresh-process load 为 9/9；Claude load 为 `platform_na`；`live_accepted` 仍未执行。

2026-08-09 adversarial hardening：coverage 以全局 C 契约为唯一约束集合，grouped、未知、重复 mapping 均只算文本出现并阻断 semantic pass；静态审计把全局/项目硬预算、缺失结构、Claude wrapper、过期 N/A 与非文件 S5 enforcement 引用转为真实门禁。`textual_mapping_covered_count / semantic_gap_count` 是 v1 主字段；`covered_count` 仅兼容 textual count，`gap_count` 仅兼容旧的缺动作计数且不含 mapping issue，消费者不得用二者推断 semantic pass。`structural_pass / semantic_coverage_pass / enforcement_verified` 继续独立，且不外推为 `host_loaded` 或 `live_accepted`。

### `ADR-SMV-008 Responsibility coverage over universal template`

决定：以 `common + platform_delta + project_action` 的责任覆盖和证据判断协同效果；固定 `1/A/B/C/D`、体量预算和 wrapper 只作为可配置 profile。

理由：这保留参考仓已验证的边界设计，同时避免把单一用户/宿主结构固化成所有目标仓的规则框架。

### `ADR-SMV-007 Machine-readable current-phase tasks`

决定：只为当前实施 Phase 维护详细 JSON task manifest，后续 Phase 在 entry gate 通过后再展开。

理由：给 AI 足够执行细节，同时避免维护数十个尚未验证的猜测任务。

### `ADR-SMV-009 Fixture-first bounded plugin distribution`

决定：plugin awareness 优先消费宿主 JSON 快照；只为已证明的自维护 workflow 提供 Codex skills-only fixture exporter。static/behavior 是 deterministic gate，model snapshot 非阻断，host install/load/live acceptance 独立记录。

理由：官方已拥有 scaffold、marketplace、安装和 runtime；本项目只补本地策展、校验、受限导出和证据，避免扩张为第二套 plugin control plane。

### `ADR-SMV-010 Unified selection, host-owned activation`

历史决定：P4 统一 skill/MCP/plugin/app/native-tool 的 selection result 和 activation-plan vocabulary，但不统一或接管各自 runtime；当时采用 explicit name、negative/required intent、metadata ranking 和 abstain。

维护结论：activation-plan vocabulary、availability、side-effect 和宿主认证边界继续保留；脚本内 lexical intent/ranking 已被 `ADR-SMV-017` 取代。P4 的历史 repo_verified 证据不被改写，但不能继续外推为自然语言路由实效。

### `ADR-SMV-011 Adaptive decision plane, native execution plane`

历史决定：P5 以 schema v3 task model、hybrid retrieval/policy adjudication、capability DAG、session reuse plan、recommendation-only profile preheat 和只读 App Server snapshot 扩展 P4；skills、MCP、apps/connectors、plugins 和 native tools 仍由各宿主原生执行。

维护结论：只读 host snapshot、session reuse、profile `apply=false` recommendation、统一 policy 字段和历史 schema compatibility 继续保留；脚本生成 task type/domain/confidence、hybrid semantic ranking 和自动 capability DAG 选择已被 `ADR-SMV-017` 取代。当前 DAG 只表达 `discover -> host_adjudication -> policy -> activate` 的责任顺序。

### `ADR-SMV-012 Lean Delivery is an advisory lens`

决定：Lean AI Software Delivery 只解释产品基线、当前模式、切片、责任和停止条件，宿主原生 Agent 继续拥有推理、编码、工具调用与会话执行。

理由：用户需要的是主链优先和更少无效工作，而不是第二套 agent runtime。advisory lens 可直接复用当前 capability routing、task contract 与证据边界，也能随模型原生能力增强而逐步退役。

### `ADR-SMV-013 Maintenance design is not P6`

决定（P5 期间历史状态）：design package 与条件性 10-task pilot 进入 `maintenance_design` 平行维护轨，基于 P5 且当时保持 `P6_ADMISSION_STATUS: hold`。2026-08-07 admission 后，该 hold 已被 supersede；maintenance track 仍不授权宿主 mutation 或 live acceptance。

理由：规划和 observe-only pilot 不构成新的产品 runtime 或 Phase admission 证据。只有路线图既有五项条件同时满足并由用户明确授权，才允许创建 P6 spec/manifest。

### `ADR-SMV-014 Reuse task and plan fields for delivery views`

决定：Product Baseline 和 Slice Contract 先作为 PRD/spec/plan/task 字段的逻辑投影视图，不新增第二套持久对象、schema major 或同步器。

理由：当前字段已覆盖 goal、scope、依赖、write set、tests、verification、rollback 和 done_when；复制模型会制造漂移。只有 pilot 证明稳定的多消费者交换需要时才评估小幅 P5-local metadata。

### `ADR-SMV-015 Roles are on-demand responsibility lenses`

决定：生命周期职责由主 Agent 按风险启用 lens；不建立固定产品经理、架构师、开发、测试、运维 Agent 团队。

理由：职责覆盖有价值，角色接力本身没有价值。按需 lens 保留专业检查，又减少上下文传递、冲突、token 和无人对端到端结果负责的问题。

### `ADR-SMV-016 Delivery metrics remain lightweight observations`

决定：TTFV、返工、人工打断、非产品 artifact、门禁耗时与 live 转化只记录在 pilot worksheet/evidence；不建设 telemetry service，不设未经 baseline 的硬阈值，不让 LLM score 单独阻断。

理由：指标用于判断流程是否产生净收益。先为指标建设系统会重演治理膨胀，并可能激励虚假完成或跳过必要验证。

M1 baseline 优先使用近期可比 native-only 历史任务或交替匹配任务，不把同一任务机械执行两遍。不可比任务的观察保持 descriptive-only；synthetic、候选和 pilot bootstrap 自身不得计数。该限制牺牲实验室式随机因果声明，以换取真实交付低干扰和证据诚实性。

### `ADR-SMV-017 Native-first semantic selection and deterministic policy kernel`

决定：`decision_owner=host_ai`。当前可见 skill/native tool 由已在处理完整请求的宿主 AI 原生匹配并直接使用；只有显式能力查询、无可见匹配或跨 profile 冷发现时才调用兼容 router。确定性 policy kernel 验证 containment、freshness、availability、side effect、approval、activation 与 session reuse。router 必须报告 `semantic_routing_performed=false`、`task_type/domain=host_adjudicated`、`confidence=null`，不得调用第二个模型或静默切换 profile。其“宿主先猜 profile hint”的发现入口已被 `ADR-SMV-020` 取代；语义所有权和安全内核继续有效。

理由：真实使用反馈和重复自然语言回放已经证明，固定正则/词表既重复宿主已有语义能力，又丢失上下文和否定语义，辅助层反而低于仅使用 profile 的基线。该设计复用官方 `name + description -> model implicit/explicit invocation`，将本项目独有价值压缩到可确定、可测试的 discovery 与安全策略；它减少额外 token、延迟和双重决策，同时保留写操作、认证和激活的可见门禁。

在当前约束下这是 Pareto-optimal，而不是宣称永恒或全局绝对最优：相对于继续堆词法规则，它提高语义质量并降低维护成本；相对于额外 provider/embedding/router service，它不增加模型调用、daemon、数据库、凭据或故障点；相对于只保留一个超大 profile，它守住元数据预算和渐进披露；相对于全手工选择，它允许低风险已可用能力无感使用。若未来官方提供可查询、可约束且带稳定 trace 的跨 profile 原生 discovery，本兼容 router 应继续缩减或退役；若真实 replay 不能降低误调用、漏调用、纠正次数或 TTFV，也应仅保留 policy kernel。

### `ADR-SMV-018/019 Historical profile reconciliation and canary (superseded by ADR-SMV-037)`

历史决定曾以宿主 proposal、确定性 plan-only 校验、非活动 profile canary、fresh replay 和 receipt rollback 维护 profile membership。P6 已证明 profile 不应承担 reachability 或语义选择，旧 advisor/canary 的真实维护净收益也未建立，因此 proposal planner、apply、accept 和 replay runtime 已退役。

当前仅为旧配置和已存在 receipt 保留 read-only compatibility view、versioned migration 与 stale-safe rollback；proposal 入口返回 `profile_reconciliation_retired`。若未来出现新的独立迁移失败，应在该兼容 seam 内最小修复，不能恢复自动语义归属、active-profile 热切换或 canary 控制面。

### `ADR-SMV-020 Hierarchical domain discovery before candidate adjudication`

决定：cold discovery 采用 `visible native match -> direct use`，否则由 resident router 返回轻量 `discovery_domains(name,purpose)`；宿主基于完整请求选择最多两个 domain，再取得 `candidates(name,description,path,domains)` 并做语义裁决，最后进入 ADR-SMV-017 的 deterministic policy。profile 降级为 domain/index partition、projection/budget/preheat 兼容面；`DomainHint` 是主入口，`ProfileHint` 只保留兼容。脚本不做 lexical ranking，不修改 active profile。

理由：上一版 profile-first contract 存在信息循环：宿主在调用 router 前看不到 cold skill 描述，却必须先判断是否存在值得发现的 cold skill并猜 profile。真实 default cold baseline 只有 4/8 主动触发，而显式进入 discovery 后 raw chain 8/8，证明故障在入口发现，不在候选后 policy。层级 catalog 用极小 metadata 解除循环，同时保留单一语义所有者和可测试安全内核。

验收边界：重构后 32-case selection 为 32/32，8-case cold-load chain 为 8/8；这是 fresh ephemeral `host_evaluation_partial`。cold-load 平均 input token 从约 161,765 升至 164,346，平均耗时从约 56.3 秒降至 53.8 秒，因此只证明触发/选择改善，不宣称 token 成本改善、普遍无感或业务 `live_accepted`。

退役条件：官方宿主提供稳定跨域 native discovery/trace 后删除 catalog seam；代表性真实任务不能持续减少漏触发、误触发或用户纠正时，进一步缩减为 policy-only，而不是增加词法规则或第二模型。

### `ADR-SMV-021 Inventory-delta signal and cost-aware cold discovery`

决定：`Sync-CodexSkillProjection` 在覆盖旧 manifest 前比较 canonical `name + path + description` fingerprint。只有真实 delta 才写 ignored `reports/skill-profile-reconciliation/pending.json`，并向当前宿主返回 `reconciliation_needed + exact delta + config hash + advisor command`；profile-only/no-op 不产生新信号。signal 只启动 ADR-SMV-018 的宿主语义 handoff，不直接 proposal/apply，不切 active profile；signal 写失败不阻断技能投影主链。

host evaluation 同时记录 cumulative input、cached/uncached input、cache ratio、command/router/tool-round count 和 latency。2026-08-04 两个同 prompt A/B 中，合并工具回合尝试把 5 回合降为 4、累计 input 下降约 13%–16%，但 uncached input 无改善或上升、延迟分别约 +5% 与 +51%，并因合并命令重试降低链稳定性，因此 reject 该实现并恢复 separate 分层调用。保留完整 router/target `SKILL.md` 读取、宿主语义裁决和确定性 policy；日常通过按需触发与 focused replay 控制成本，不删除正确性步骤。

理由：inventory delta 是确定性事实，适合脚本发现；profile 归属是语义判断，继续交给已在场宿主。token 成本的主要可观察部分是多回合累计 cached context，盲目合并命令只移动成本并增加失败/延迟。该决定获得自动 handoff 与可测成本，同时避免 daemon、第二模型、静默配置写入和脆弱 shell orchestration。

退役条件：官方 `skills/changed`/profile 管理能提供等价 delta、事务和 host handoff 时删除本 signal；宿主原生跨域发现消除 cold router 后删除相应 evaluator chain。指标无净收益时继续缩减验收频率/兼容层，而不是引入额外 reranker。

### `ADR-SMV-022 Truth-preserving cold discovery hardening`

决定：继续保持一个 `route-capability.ps1` 深模块和既有 schema v3 interface，不增加 router service 或第二套状态。显式未知 domain 零候选并返回 `unknown_domain`；候选上限同时公开 `available_candidate_count + truncated`；current caller-provided host snapshot 对同名 skill/MCP 做字段级 runtime truth override，同时保留静态 skill path/containment 和 policy side-effect。宿主-facing 指令只投影 retrieval/exclusion 或 policy/activation 结果，避免把重复 catalog、完整内部图和无关字段送回模型。

理由：这三个缺口都会造成错误静默降级、候选丢失或把 disabled/needs-auth 误写成可自动使用，属于确定性正确性问题而不是语义 ranking。修复集中在现有 seam，caller 无需学习新 schema major；本地同 prompt 输出投影将 discovery JSON 从 21,470 bytes 降至 9,133 bytes、policy JSON 从 22,933 bytes 降至 1,284 bytes，但只声明返回体积下降，不外推为端到端 token 等比例下降。

仍不可消除：宿主模型语义选择具有概率性、fresh task 固定上下文会重放、当前宿主没有稳定 skill-body invocation trace，且 profile/config 写入不能安全地无授权热切换。这些边界只能通过 representative replay、current snapshot、明确 truth ladder 和 retire trigger 缓解，不能由本仓伪装成确定性或 live acceptance。

### `ADR-SMV-023 Portable catalog decouples cold discovery from profiles and repository state`

决定：`SkillProjection` 从 canonical inventory、`discovery_catalog` domain membership 和 routing policy 生成 `agent/capability-router/catalog.json`，并随 router 包一起投影到用户 skill root。catalog 只保存规范化 metadata、相对 `SKILL.md` 路径、domain 与 routing rules；router 从任意工作目录优先读取相邻 catalog，使用路径 containment 与 skill name 复核文件，并以 catalog 的规范化 description 作为 cold-discovery metadata 真源。显式 manifest/config/policy 仍保留兼容入口，但普通跨仓发现不再依赖它们。

理由：profile 同时承担预热预算与 cold index 会使普通目标仓在没有 `skills-manager` report/config 时得到 0 domain/0 candidate，也让未进入 resident profile 的 canonical skill永久不可发现。portable catalog 将“宿主初始可见面”和“按需冷发现全集”拆开：新增/删除 skill 由既有 build/projection 幂等刷新 catalog，不扩大初始 metadata 预算，不静默修改 active profile，也不引入 daemon、数据库、第二模型或 schema major。

验收与退役：生成包必须从用户主目录、无关 Git 仓及其嵌套目录暴露非空 domain/candidate，且 `manifest_path/config_path/policy_path` 为空、`writes_performed=false`；专用 cross-repo regression test 在 repo 外 CWD 重放该形状，corpus verifier 保持 tracked-input hermetic。官方宿主若提供完整、可验证的跨 profile cold inventory 与 policy trace，则删除 portable catalog seam。

### `ADR-SMV-024 Host-owned coordinator with single-writer shared seams`

决定：多 Agent 工程采用 `host-owned coordinator -> optional read-only design panel -> admitted work slices -> disjoint worktree candidates -> single integration owner`。共享文件、生成 seam、迁移或外部状态固定为单 writer/串行；lease 只是带 owner/write-set/base/recovery 的 admission claim，当前不实现服务。Git ref CAS 与内容 hash 只做 freshness guard，不作为文件锁、任务队列或 winner selection。

理由：宿主已拥有任务分解、subagents、worktrees、等待和 review 能力；本仓已有 task/write-set/freshness/receipt/gate。增加 scheduler/lease database 会复制原生控制面，而只靠 merge conflict 又发现得过晚。小的 planning interface 在不增加 runtime 的情况下把责任、并行准入和 stale recovery 变成可审查合同。

退役/扩展触发：官方宿主若稳定暴露 write-set admission、candidate provenance、lease/reassignment 和 integration trace，本合同缩减为 verifier 兼容检查；只有跨进程/跨主机真实并发反复产生无法由 native worktree + Git + current task ownership 修复的失败，才可在 P6 admission 后评估独立 coordinator/lease service。

### `ADR-SMV-025 Evidence-gated tool adapters and sparse skill lifecycle`

决定：默认栈为宿主原生执行 + Git/repo truth + affected/full gates；skill、plugin、MCP、knowledge/code graph 按稳定 surface 职责逐层增加。所有社区候选统一记录 `adopt | adapt | defer | reject`、native equivalent、real consumers、data/auth/write boundary、evaluation、maintenance cost、retirement trigger 和 truth level。外部 context adapter 需两个独立真实失败样本后才进入 read-only canary；skill 需 replay/shadow/bounded canary/review 后 promotion。

理由：强模型会降低部分提示词和 workflow 的边际价值，但不会消除持久规则、权限、外部 current truth、确定性测试、证据和回滚。相反，能力堆叠会增加 metadata、触发竞争、供应链、索引 stale 和维护成本。证据化 admission 能保留真正独特的 adapter seam，并在宿主原生能力覆盖时可删除。在授权、外部作用和风险基线不变时，只有代表性真实任务的对照证据才能触发治理减重；模型版本、单次成功或模型自评均不能单独触发。新增或保留的门禁和审计必须说明其独立失败模式，否则优先合并或退役。

退役条件：真实 M1 样本没有显示相对 native baseline 的净收益；外部工具语言/索引/隐私/资源成本不满足；skill 长期无消费者、误触发或宿主已原生覆盖。退役优先于为保存范围继续包装。

### `ADR-SMV-030 Resident dispatcher and complete-catalog cold entry`

决定（P5-local 历史/prompt-contract，ADR-SMV-031 superseded）：profile 只负责 resident metadata 预算、domain/index partition 和未来任务的 preheat 建议；每个可能受益于本地 skill 的非平凡请求先进入 resident `capability-router` dispatcher。无显式 domain/profile hint 时，router 直接从相邻 portable catalog 暴露完整 canonical candidate index，再由宿主 AI 依据完整请求和否定约束选择最小技能集合，最后由既有 deterministic policy 校验 containment、freshness、availability、side effect、approval 和 activation。该入口不切换或写入 active profile。

理由：官方 Codex skill contract 采用 progressive disclosure，初始 metadata 列表受 8,000 字符/2% context budget 限制并可能省略技能；skill description 的 implicit invocation 是宿主模型选择，不是 middleware 强制调用。原来的 fallback-only router 因而可能在看不到 cold skill 时永远不进入 discovery；原脚本的 no-hint current-profile 过滤还会让 portable catalog 在无 manifest/config 的普通 cwd 得到 0 candidate。resident dispatcher + complete catalog 解除信息循环，同时不把 111 个技能粗暴塞入初始 prompt。

边界：仓库可以确定性地生成完整 catalog、返回 cold-load policy 和证明零写入，但不能把宿主模型是否调用 skill metadata 伪装成硬保证。若未来需要每个请求必经路由，必须由宿主 pre-model middleware/app-server 提供注入和 invocation trace；在官方 surface 未提供该能力前，本仓只承诺 `repo_verified + host_prompt_contract_verified`。

### `ADR-SMV-031 Host AI owns semantic skill selection`

决定：普通请求只走宿主原生 progressive disclosure；skills-manager 负责编译 inventory、资格、安全、投影和证据，不再要求 resident `capability-router` 先行，也不把 profile/cold domain 当语义或可达性边界。P5 router/profile 只作为 P6 迁移期 shadow/compatibility 输入。

理由：仓库可发现与宿主触发长期断裂，证明第二套 router 无法强制 host invocation，还会重复模型已有语义能力。将语义选择交回宿主，仓库保留确定性且高杠杆的 lifecycle seam，减少 token、延迟、双真源和热加载问题。

### `ADR-SMV-032 Effective HostCapabilitySnapshot, not raw config`

决定：以 `HostCapabilitySnapshot` 聚合 turn、thread、effective config、model/provider catalog 和 unknown fallback。App Server/CLI 是当前事实 adapter；直接读取 `config.toml` 只为 `source=config_fallback`。已知 context 下 metadata ceiling 使用 `floor(context_window * 0.02)` 或宿主更严格值，并保留 configurable headroom。

理由：`model_context_window` 可缺省、由模型/provider 推导或被 thread/turn 覆盖。原始 TOML 是配置输入，不是每个 surface 的有效运行事实。

### `ADR-SMV-033 Split compiler and eligibility policy from legacy router`

决定：把 router 内可保留职责拆成 `SkillCatalogCompiler`、`SkillEligibilityPolicy` 和 `SkillInventoryDoctor`；它们分别拥有 canonical metadata/provenance、确定性 allow/deny/activation 和健康诊断。任何 lexical/profile semantic ranking 不进入这些模块。

理由：这些职责深、稳定、可测试并被 projection/doctor/fallback 多处复用；与宿主语义选择隔离后，模块接口更窄且 legacy router 可渐进删除。

### `ADR-SMV-034 Complete token-aware native metadata projection`

决定：所有 eligible enabled skill 都进入 native discovery plan；以宿主有效 token budget 和 description compaction 规划，验收为 `enabled_total == kept_total`、`truncated=false`、`omitted=0`。预算不足时 fail-closed 并报告 offenders，不恢复 profile 分片。

理由：仅证明 catalog 完整不能解决宿主看不见；而固定字符 ceiling 不能表达 272000 等不同 context window 的官方 2% token budget。完整投影把可达性还给宿主，同时让成本和遗漏可测。

### `ADR-SMV-035 Metadata-first activation evaluation`

决定：用 concise metadata lint 与 direct/indirect/negative/ambiguous/no-skill corpus 评价宿主原生选择。失败先修 name/description/边界，禁止用 corpus 反向生成脚本 semantic router。

理由：宿主选择的稳定输入是 metadata；metadata 质量可被确定性 lint 和代表 replay 改善，又不会建立第二模型或长期索引。

### `ADR-SMV-036 Invocation trace defines truth level`

决定：统一 `NativeInvocationTrace` 状态为 listed、selected、injected、executed、abstained，缺少宿主事件时保持 partial/unknown。visibility、prompt presence 和 selection 都不能推断 full body execution。

理由：过去 fresh prompt/projection 证据被迫依赖间接推断。显式 truth ladder 防止 repo reachability 被误报为自动调用或 live acceptance。

### `ADR-SMV-037 Retire profile reachability through versioned migration`

决定：profile、active/current profile、reconciliation 和 canary 从运行主链退役；迁移期只读兼容、shadow、deprecation 和 round-trip receipt 先行，达到 removal gate 后删除 runtime 路径，历史 spec/manifest/evidence 不改写。

理由：profile 既不能热加载当前任务，也不应成为全局技能全集的可达性门；继续维护它只会让用户在新任务前选 profile，并复制宿主 native selection。

### `ADR-SMV-038 Strict App Server dispatch is opt-in fallback`

决定：只有明确 strict/fallback 请求才允许 `pre-turn dispatch -> bounded candidates -> host adjudication -> supported type=skill injection -> trace`。普通请求不进入，候选必须先过共享 eligibility policy，缺宿主裁决或 surface 支持即 fail-closed/platform_na。

理由：pre-turn middleware 可提供更强的强制与 trace，但若默认覆盖所有请求会重新建立第二套路由和额外 token/延迟。窄 fallback 保留必要控制而不破坏 host-native 主链。

### `ADR-SMV-039 Reference portfolio is reversible evidence, not accumulated runtime`

决定：外部资料采用 official-first、manifest-controlled 的可逆组合；社区候选先 discovery/review，再按需只读，只有第一方权威或重复真实消费者才晋级。官方替代、无消费者、重复、stale、许可证/供应链风险或维护成本超出净收益时先降级/停刷，满足独立 runtime/import 与 checkout 守卫后才删除。写权限只覆盖 manifest-owned `skills-manager-references`，不扩展为 `D:\CODE\external` 根或兄弟项目 shelf 管理权。

理由：只增不减会扩大上下文、供应链和维护成本，把参考输入误写成产品范围；立即物理删除又可能破坏历史兼容或 runtime import。分层退役保留取证与回滚，同时贯彻可绕过、可替换、可删除的 North Star。

### P6-012 staged-removal status（2026-08-08，repo_verified）

CURRENT_PHASE_TRUTH_SOURCE: tasks/skills-manager-vnext-phase6.tasks.json

P6-012 已进入 repo-side closeout：legacy `SkillRouting` source 及其自测已删除，普通入口不再暴露 `技能配置`/`skill-profile` dispatch；profile compatibility view 保留为 `read_only` 且 `reachability_authority=none`。独立 compatibility verifier 只读取配置并报告 migration 状态，不能成为当前语义选择或 reachability owner。

本节标题和 2026-08-08 full 只保留 point-in-time 架构/历史事实。当前 P6 任务、runtime migration、inventory/evaluation/invocation/live truth 与最新 evidence 动态读取上述 manifest；full 运行态不写回 tracked manifest，只由 `reports/quality-gates/current.json` 的 immutable receipt 证明 `profile=full`、`status=passed` 和 exact-current-source。任何 inventory 或 repo-side 结果都不得提升为 invocation 或业务 acceptance。

## 11. 安全与供应链

- 外部内容是不可信输入，不执行其仓库指令或脚本，除非单独评估并授权。
- 记录 source revision/checksum/license；floating `latest` 只能用于 discovery，不能直接进入 locked apply。
- MCP/plugin capability 必须声明 external data/action 和 auth boundary。
- plan/receipt/evidence 统一 redaction；测试包含 token、URL userinfo、connection string 和 env value fixtures。
- reviewed slice evidence、历史 runtime archive 与 ignored current runtime receipt 三层分离；active ledger 不接受 `audit-runtime-*` 运行产物。
- hooks 视为代码执行面，必须显式 review/trust；本项目不自动启用第三方 hook。
- 规则 prose 不是权限系统；确定性拦截放 native policy、hooks、scripts 或 CI。
- 社区仓 README、issue、prompt、skill 和代码均按不可信输入处理；只读记录 upstream URL、revision、license/checksum 与 `adopt | adapt | defer | reject`，不继承其指令或运行其脚本。
- 多 Agent 的角色名、讨论结论、lease 或 candidate commit 都不转移用户授权；外部写入、发布、生产和付费动作仍需当前 authority。共享路径 reassignment 必须先确认旧 writer 停止并保存 candidate provenance。
- Git ref CAS/hash 只能拒绝 stale 更新；任何文档或实现不得把它表述为文件锁、队列、公平性保证或自动 merge authority。
- Obsidian vault、Hermes/OpenHands/LangGraph state 和任何外置 memory 不成为本仓真源；进入任务上下文前必须通过显式导出、路径范围和敏感信息检查。
- provider/auth/token、生产写入和付费调用属于宿主或外部系统授权面；maintenance advisory 不保存凭据、不绕过 approval，也不因角色/计划状态自动授权。
- prompt injection 不能修改 Product Baseline、write set、verification level 或 apply token；来自网页、MCP、issue、日志和外部源码的动作建议必须回到当前用户指令与仓库契约复核。

## 12. 性能与资源

- inventory 扫描使用 root allowlist、目录排除、mtime/content fingerprint 和有界并行。
- external reference refresh 与 runtime scan 分离，不在日常 doctor 中隐式 fetch/clone。
- package hash cache 继续 fail-safe；未知 schema 或 fingerprint mismatch 回退 full hash。
- native probe 有 timeout、重试上限和可观察 exit；不无限等待宿主进程。
- 不为性能跳过 checksum、freshness、schema 或 redaction。

## 13. 迁移策略

1. Phase 0 先添加 schema、seam 和 contract，不改变现有 CLI 行为。
2. 新 application/domain function 与旧 wrapper 并行，使用 golden/compat tests 证明输出一致。
3. 每迁移一个 command seam 后才从旧大文件移除对应 implementation。
4. 新 OperationPlan 先用于一个低风险路径 observe；receipt 与旧结果对比通过后再 enforce。
5. rules advisor Phase 1 不接入写入路径。
6. 兼容窗口结束必须有 usage evidence、迁移说明和 rollback，不按日期自动删除。

## 14. 反过度设计守卫

以下任一提案默认拒绝，除非有重复真实问题、明确用户和验收证据：

- 通用 agent runtime、planner、memory、model router 或 provider gateway；只读 capability discovery/policy kernel 与 activation plan 不属于这些 runtime。
- 中央目标仓 registry、跨仓自动同步或统一规则服务。
- 为每个宿主复制完整插件商店、OAuth 或 connector 管理。
- 只为展示 inventory 而建设数据库、搜索集群、Web/WPF UI。
- 为尚未实现的 Phase 预建空接口、空配置或通用 extension SDK。
- 用 LLM score 直接阻断安装、写规则或自动删除能力。
- 因目录“更干净”一次性重写全部 PowerShell 模块。
- 主链未通过前扩展多租户、插件 SDK、通用事件总线、完整角色团队、全套测试矩阵或遥测平台。
- 为每个 task 机械新增 schema、wrapper、fixture、evidence、ADR 或 skill；同一逻辑切片应复用最低充分资产。
- 把一次成功、自我总结或社区热门做法直接晋级为全局规则/skill，或在没有消费者时永久保留。
- 为本地单用户工作流复制 Trellis/AGOS 式 scheduler、ledger service、lease database、dashboard 或自动 reviewer runtime；协议启发不等于采用控制面。
- 在没有两个独立 repo-native 检索失败样本、语言覆盖和 freshness/privacy/resource 证据时，默认安装知识库、代码图或全仓 LLM 分析工具。

新抽象必须至少满足一项：消除两个真实调用点的重复、形成可测试安全边界、匹配稳定外部协议，或降低已量化热点复杂度。

AI 编码开始前使用六项范围检查，不建设新的治理子系统：真实问题和用户是否明确、官方/既有 surface 是否可复用、最小直接方案是什么、预计新增哪些长期维护面、最低充分测试是什么、什么条件触发停止或重新评审。任一项无答案时保持 design/deferred。

验证采用升级制：日常迭代只跑受影响测试；共享 config/write/generated seam 使用 quick contract；不改运行面、安全、数据/迁移、公开契约、依赖/包或 release 的 closeout 使用 focused verification，上述风险或 focused 发现的跨面风险才触发一次 full。低层已充分证明的风险不重复堆 unit/fixture/E2E；同一切片共用 evidence，文件未变化不重复跑 full。若实际 write set、抽象数量或测试层级明显超过计划，停止编码并重新做复用/删除/延后判断。

任一条件触发 anti-overdesign checkpoint：首次可演示价值仍未出现但新增了三个以上非产品 artifact；计划外长期维护面出现；同一风险存在两层以上重复证明；新增抽象没有两个调用点/稳定协议/量化热点；实现不能用一句话说明用户可见增量。checkpoint 的默认动作是删除、合并、推迟或回到 Main-chain，而不是新增治理文档。

P5 后默认 maintenance hold。新 schema major 或 P6 只能由跨至少两个 task domain 的独立真实失败、现有 P5 seam 无法修复的证据、已消费字段的调用证据和用户明确授权共同触发；否则只做缺陷修复、真实 corpus、性能和删除性维护。

## 15. 验证矩阵

| 层级 | 证明 | 不证明 |
| --- | --- | --- |
| schema/unit | object 和 validator 行为 | CLI/宿主行为 |
| golden/fixture | 兼容输出、diff、redaction | native load |
| repo gate | 构建、测试、contract、hotspot | host loaded |
| native list/probe | 当前 host 发现/加载 | 真实业务效果 |
| live workflow | 特定真实任务成功 | 其他宿主/账号/环境 |
| human acceptance | 指定用户/场景认可 | 普遍产品完成 |

任何报告必须选择最高实际执行层级，不得从低层自动推断高层。
