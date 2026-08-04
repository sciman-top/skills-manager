# skills-manager vNext 工程架构

**program_id**: `skills-manager-vnext`
**architecture_version**: 1
**status**: accepted-direction
**最后更新**: 2026-08-04

## 1. 架构结论

采用“PowerShell 模块化单体 + build-time 单文件 bundle + 文件型 versioned contracts + host adapters”的架构。

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

当前问题不是 PowerShell 本身，而是 bounded context、应用层和 IO seam 不够明确。Phase 0 先建立 seam，不做语言重写。

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

#### Profile reconciliation advisor

skill inventory 变化后的 profile 维护继续遵守相同的 ownership 分层：宿主 AI 读取完整 skill description、profile 目的和用户上下文后提出语义归属；仓库只计算和校验可确定事实。

```text
skill add/remove/metadata change
  -> canonical inventory + current profile diagnostics
  -> host_ai proposal (base_config_sha256 + add/remove + reason)
  -> freshness / existence / protected-kind / no-op / budget / policy checks
  -> exact dry-run change-set (apply_allowed=false, writes_performed=false)
  -> bounded non-active-profile canary (explicit token)
  -> atomic backup + receipt
  -> fresh ephemeral host replay
  -> accept partial evidence or automatic rollback
```

诊断直接复用 `New-SkillProjectionPlan` 的 canonical、reachability 和 budget 计算，不建立词法分类器、embedding、provider call、daemon 或第二个 profile schema。system skill、resident skill 和 alias 迁移项不允许由 proposal 放入或移出 profile；`active_profile` 在 current/proposed view 中必须完全一致。跨三个及以上 profile 的 membership 只作为 overlap observation，不能在缺少语义证据时自动删除。

`Application/SkillProfileReconciliation.ps1` 是 proposal 后唯一的 profile mutation seam。它不负责语义归类，只实现最多 5 skill/10 action、默认 256 字符预算余量、非活动 profile 限制、hash freshness、single-writer、atomic backup/write、receipt、fresh replay acceptance 和 stale-safe rollback。执行型 benchmark 可临时投影被测 profile，但报告必须证明恢复原 profile；当前 Codex JSONL 无独立 skill-body invocation event，因此 replay 保持 `host_evaluation_partial`。

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
- 不引入 PowerShell class hierarchy；优先使用 plain object + validator function，保持 PS 5.1 兼容窗口。
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

## 9. 配置与 schema

- `skills.json` 在兼容窗口内继续是 skill/MCP runtime truth，不加入 rules 文本或 host auth/model 设置。
- Phase 0 为 `skills.json` 建立 schema 和 migration/version policy；先 observe 再 enforce。
- Rule advisor 配置只在 Phase 1 有真实字段后建立独立文件，禁止预建空的万能 `rulesets.json`。
- Operation plan/receipt 分别拥有独立 schema version。
- task manifest 属于 planning contract，不属于产品 runtime config。

## 10. 技术栈决策

### 10.1 当前条件下的最优性

不存在脱离目标、约束和时间尺度的单一“全局最优技术栈”。这里把全局最优定义为：在所有已知目标上位于 Pareto 前沿，并保留最大未来选择权的参考架构；任何一项继续改善都会显著损害成本、可靠性、兼容、交付速度或可逆性中的至少一项。

若暂时忽略本仓迁移成本，一个更接近全局最优的长期参考形态是：protocol-first 的稳定 domain contracts、可替换的 source/host adapters、无宿主状态的 planning engine、显式事务/证据协议、跨平台 typed core，以及按真实规模选择的 CLI/TUI/API 和可选本地索引。它是 north star，不是当前 backlog；database、daemon、remote control、extension SDK 等只有触发条件成立后才进入实现。

当前约束下的适配性最优则把已验证事实纳入目标函数：Windows-first、现有 PowerShell/Pester 投资、单文件便携分发、当前用户规模、CLI/Junction/Git 密集工作和兼容成本。当前核心工作是建立模块 seam 和合同，以最低行为风险获得主要维护收益。

| 维度 | 全局最优参考 | 当前适配性最优 |
| --- | --- | --- |
| 优化范围 | 已知及合理未来场景 | 当前用户、仓库和近两个 Phase |
| 迁移成本 | 可作为长期投资处理 | 作为真实高权重成本 |
| 不确定性 | 用可替换边界保留选择权 | 延迟未被证据证明的能力 |
| 技术选择 | 可接受 typed core/多入口/可选索引 | PowerShell 模块化单体 + 单文件 bundle |
| 验收 | 跨平台、规模、生态和演进性 | 兼容、门禁、可回滚和真实工作流 |
| 主要风险 | 过早平台化 | 被当前实现锁死、错过重评时点 |

| 方案 | 现有兼容/迁移风险 | Windows 与 native CLI 适配 | 分发复杂度 | 长期类型/并发能力 | 当前决定 |
| --- | --- | --- | --- | --- | --- |
| PowerShell 模块化单体 + 单文件 bundle | 高兼容、低迁移风险 | 高 | 低 | 中 | 采用 |
| .NET 单体 CLI | 中低兼容、需迁移入口/测试 | 高 | 中 | 高 | 条件重评 |
| TypeScript/Node CLI | 中低兼容、增加 runtime/打包 | 中 | 中高 | 高 | 当前拒绝 |
| daemon/API + database | 破坏 local single-process 边界 | 中 | 高 | 高 | 无需求证据，拒绝 |

改进方向不是重写，而是依次完成：纯 Domain contract、Application orchestration、Infrastructure/Host adapter seam、结构化 plan/receipt、兼容 wrapper 和 characterization tests。只有出现可量化的跨平台、并发、类型安全或性能瓶颈，且连续多个有界切片无法解决，才启动替代技术栈 ADR/PoC；PoC 必须证明迁移收益、兼容策略、分发和回滚，不能仅以代码风格作为理由。

选择算法固定为：先列 hard constraints 和不可接受结果；再比较满足约束方案的用户价值、总拥有成本、风险、可逆性和 option value；删除被支配方案；选择能完成下一真实里程碑的最小 Pareto 方案；最后为未选择的更重方案记录量化重评触发。全局参考用于检查方向，适配性方案用于决定当前实现。

### 10.2 运行与工程工具

- Runtime：PowerShell 7 主路径；Windows PowerShell 5.1 仅保留有界 bootstrap/smoke 兼容窗口。
- Source/build：`src/*.ps1` 模块化源码 + `build.ps1` 确定性 bundle + 根 `skills.ps1` 便携入口。
- Contracts：UTF-8 JSON、显式 `schema_version`、plain object validator 和稳定 finding/exit contract；具体 schema validator 在 `SMV-P0-003` 以当前依赖事实选定。
- Tests：Pester 4.10.1 unit/E2E、fixture/golden/characterization/fault injection，以及 Python dependency baseline verifier。
- Distribution/state：Git、lock/manifest、文件 hash、ignored plan/receipt/backup；不增加数据库或常驻服务。
- Integration：优先 native CLI/plugin/connector，缺少原生入口时才使用精确 scoped file adapter。

### `ADR-SMV-001 Keep PowerShell modular monolith`

决定：继续使用 PowerShell，按模块 seam 演进，保留单文件发行。

理由：当前主要工作是 Windows 文件、Git、Junction、CLI 和宿主配置；现有测试/发布投资大，重写不会直接改善产品价值。

重评触发：非 Windows 成为核心使用量、需要常驻 API/并发服务、类型/性能缺陷连续多个 Phase 无法通过 seam 修复。

### `ADR-SMV-002 PowerShell 7 primary, 5.1 compatibility window`

决定：开发/CI 以 PowerShell 7 为主；5.1 保留 bootstrap 和显式 smoke。

理由：避免 legacy runtime 永久限制结构化错误处理、跨平台和依赖能力，同时保持现有 Windows 用户迁移路径。

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

决定：design package 与条件性 10-task pilot 进入 `maintenance_design` 平行维护轨，基于 P5 且保持 `P6_ADMISSION_STATUS: hold`。

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

### `ADR-SMV-018 Host-proposed deterministic profile reconciliation`

决定：profile reconciliation 采用 `host_ai proposal -> deterministic validation -> plan-only change-set`。planner 只接受带当前 `skills.json` SHA-256 的 schema v1 proposal，拒绝 stale/unknown/protected/conflicting/no-op/unjustified/over-budget/policy-blocking 变更，并固定 `semantic_routing_performed=false`、`apply_allowed=false`、`writes_performed=false`。

理由：新增/删除 skill 后确实需要维护 profile，但自动关键词归类会重新引入已退役的 lexical router；静默 apply 或 active profile 切换又会制造当前任务不可热加载、预算漂移和宿主副作用。宿主已有完整语义上下文，仓库已有稳定 canonical/budget/policy 计算，二者以窄 proposal 契约组合能获得自动建议与确定性安全，同时保留 reviewed apply 的授权边界。

退役条件：若官方宿主未来原生管理跨 profile metadata 预算、变更计划和可审阅 apply，本 advisor 应缩减为兼容检查或删除；若 proposal replay 不能降低 profile stale/unrouted 的人工维护成本，也不继续增加自动化层。

### `ADR-SMV-019 Bounded profile canary with fresh-task replay`

决定：在 ADR-SMV-018 的 plan-only advisor 后增加 `host proposal -> deterministic bounded canary -> fresh ephemeral replay -> accept/rollback`。apply 仅允许非活动 profile、最多 5 skill/10 action、默认至少 256 字符 metadata headroom，必须显式 token、config hash、原子 backup/receipt；replay 对每个 added skill 同时要求 positive/negative case，并确认 original/restored profile。失败默认自动回滚，hash 漂移时停止而非覆盖。

理由：宿主 AI 更擅长完整上下文语义，但不适合替代 freshness、预算、冲突、权限与原子状态；完全静默写 profile 会降低可重复性并可能改变当前任务可见能力。非活动 canary 将用户打断降到最低，又保留审计、恢复和新任务真实验证。官方支持 skill invalidation/force reload，但没有 skills-manager `active_profile` 或当前 turn hot switch，因此 promotion 边界必须是 fresh task。

退役条件：官方若提供稳定的原生 profile/capability set、事务、trace 和 rollback，本 seam 应适配或删除；真实维护数据若不能降低 stale、纠正次数或 TTFV，则回退 plan-only advisor。

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

## 11. 安全与供应链

- 外部内容是不可信输入，不执行其仓库指令或脚本，除非单独评估并授权。
- 记录 source revision/checksum/license；floating `latest` 只能用于 discovery，不能直接进入 locked apply。
- MCP/plugin capability 必须声明 external data/action 和 auth boundary。
- plan/receipt/evidence 统一 redaction；测试包含 token、URL userinfo、connection string 和 env value fixtures。
- reviewed slice evidence、历史 runtime archive 与 ignored current runtime receipt 三层分离；active ledger 不接受 `audit-runtime-*` 运行产物。
- hooks 视为代码执行面，必须显式 review/trust；本项目不自动启用第三方 hook。
- 规则 prose 不是权限系统；确定性拦截放 native policy、hooks、scripts 或 CI。
- 社区仓 README、issue、prompt、skill 和代码均按不可信输入处理；只读记录 upstream URL、revision、license/checksum 与 `adopt | adapt | defer | reject`，不继承其指令或运行其脚本。
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

新抽象必须至少满足一项：消除两个真实调用点的重复、形成可测试安全边界、匹配稳定外部协议，或降低已量化热点复杂度。

AI 编码开始前使用六项范围检查，不建设新的治理子系统：真实问题和用户是否明确、官方/既有 surface 是否可复用、最小直接方案是什么、预计新增哪些长期维护面、最低充分测试是什么、什么条件触发停止或重新评审。任一项无答案时保持 design/deferred。

验证采用升级制：日常迭代只跑受影响测试；共享 config/write/generated seam 使用 quick contract；phase、commit 或 release closeout 才跑一次 full。低层已充分证明的风险不重复堆 unit/fixture/E2E；同一切片共用 evidence，文件未变化不重复跑 full。若实际 write set、抽象数量或测试层级明显超过计划，停止编码并重新做复用/删除/延后判断。

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
