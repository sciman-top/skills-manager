# skills-manager vNext 产品文档索引

**program_id**: `skills-manager-vnext`
**文档状态**: active
**最后更新**: 2026-08-09

## 1. 目的

本目录定义 `skills-manager` 从“skills/MCP 管理脚本”演进为“本地 AI 能力策展器与规则全域管理器”的产品方向。这里描述的是产品目标、架构和后续实施契约，不把设计态能力写成当前已实现能力。

产品终态保持以下边界：

- Windows-first、local-first、single-process、CLI-first。
- 辅助 ChatGPT Work、Codex App/CLI/IDE 和其他受支持宿主，不替代宿主 runtime、插件目录、权限、认证、模型、会话或 agent loop；允许输出 host-owned 模型/effort/agent policy proposal，但不执行运行时路由或静默配置变更。
- 优先复用官方应用、官方插件、原生 CLI、MCP/Agent Skills 等开放协议，以及已核许可证、固定 revision、存在本仓消费者并通过 focused gate 的社区实现。
- 把外部来源作为可逆 reference portfolio：允许自主只读发现，按消费者和证据晋级、降级、停刷或退役；搜索/克隆不取得安装、执行或 runtime truth 权限。
- external 管理只覆盖 manifest-owned 的 `D:\CODE\external\skills-manager-references`；不接管 `D:\CODE\external` 根、其他项目参考棚或真实产品 checkout。
- 管理发现、筛选、期望状态、差异、显式投影、验证、证据和回滚，不建设中央跨仓控制面。
- 规则能力默认 `advisory-first`；任何写入必须经过显式 plan/apply 边界。
- 面向软件交付时先跑通最薄真实主链并观察 TTFV；主链未通前不以平台层、治理层、测试数量或文档数量替代用户终态证据。

## 2. 文档职责

| 文档 | 唯一职责 | 不得承载 |
| --- | --- | --- |
| [PRD](skills-manager-vnext-prd.md) | 用户、问题、需求、非目标、产品级验收 | 代码文件级步骤 |
| [架构](skills-manager-vnext-architecture.md) | bounded context、模块依赖、数据契约、ADR、技术栈 | 路线状态和任务勾选 |
| [P6 domain model](host-native-skill-lifecycle-domain-model.md) | host-native lifecycle 统一语言、aggregates、invariants 和 states | 文件级实现步骤或运行状态 |
| [路线图](skills-manager-vnext-roadmap.md) | Phase、依赖、入口/退出门禁、状态边界 | 逐文件实现细节 |
| [规则治理参考采纳矩阵](rule-governance-adoption-matrix.md) | 官方/参考仓模式的 adopt/adapt/reject/defer 与验证边界 | 当前宿主安装或跨仓写入状态 |
| [规则全域 reviewed change-set](rule-estate-reviewed-change-set.md) | 全局/多目标仓 plan、apply、resume、rollback 输入契约 | AI 自行批准或宿主加载证明 |
| [Phase 5 Spec](../superpowers/specs/2026-08-03-capability-manager-vnext-phase-5-design.md) | 历史 adaptive decision plane、host snapshot、兼容和测试契约 | 当前 P6 runtime truth 或认证实现 |
| [Phase 6 host-native reset spec](../superpowers/specs/2026-08-07-capability-manager-vnext-phase-6-design.md) | P6 领域语言、技术栈、架构迁移、任务和验收契约 | 替代当前 manifest 的动态状态或越级写成 live accepted |
| [Phase 6 implementation plan](../superpowers/plans/2026-08-07-host-native-skill-lifecycle-reset.md) | 12-task DAG、waves、逐任务 TDD/文件/命令/停止点 | 替代 manifest 状态或跳过单任务验证 |
| [Lean Delivery maintenance spec](../superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md) | P5 后精益 AI 软件交付 advisory、host-owned coordination/model policy、tool admission、typed-core decision、pilot 和退役边界 | 新 Phase、agent/lease/model-router runtime、typed-core 实现、社区工具安装或业务效果声明 |
| [Typed-core Operation Contract shadow PoC](../superpowers/specs/2026-08-05-typed-core-operation-contract-shadow-poc.md) | TC0 seam/corpus/protocol 与 TC1 package-free C#/.NET shadow parity、分发观测、TC2 admission | PowerShell 替换、CLI/生产集成、默认分发或 live acceptance |
| [PowerShell 7-only runtime migration](../superpowers/specs/2026-08-05-powershell-7-only-runtime-migration.md) | 当前 shell runtime 支持收敛、迁移/回滚合同、PS7 policy verifier 与 repo closeout | 历史 Phase 重写、typed-core TC2、P6 或下游 live acceptance |
| [Agent workflow advisory runtime](../superpowers/specs/2026-08-05-agent-workflow-advisory-runtime.md) | TaskGraph/FailurePacket v1、completion receipt、barrier wave/admission、surface-scoped 三态可用性、Sol xhigh/medium/low proposal validation、失败升级和 PS7 zero-write CLI；legacy Radar v2 仅只读兼容 | native scheduler/provider/model calls、仓库 host mutation、Radar refresh/decision、P6 或 live acceptance；各宿主 surface 的 partial receipt 独立记录 |
| [Native-first routing correction spec](../superpowers/specs/2026-08-04-native-first-capability-discovery-correction.md) | P5-local capability routing 回归纠正、宿主语义所有权和真实场景验收 | P6、新 router service 或普遍 live acceptance |
| [Hierarchical discovery redesign spec](../superpowers/specs/2026-08-04-hierarchical-capability-discovery-redesign.md) | P5-local cold discovery、domain catalog、32+8 host 验收、inventory signal、成本拆分与 runtime truth hardening | profile 热切换、第二模型 router、P6 或普遍 live acceptance |
| [Profile reconciliation advisor spec](../superpowers/specs/2026-08-04-skill-profile-reconciliation-maintenance-design.md) | skill inventory 变化后的 profile drift 诊断、宿主 proposal 与确定性 plan-only 校验 | 自动语义 router、静默 apply/profile 切换或 P6 |
| [Profile optimization canary spec](../superpowers/specs/2026-08-04-bounded-profile-optimization-canary.md) | 宿主 proposal 后的非活动 profile canary、fresh replay、receipt 和失败回滚 | provider 路由、永久 active profile 切换、P6 或 live acceptance |
| [当前实施计划](../../tasks/plan.md) | 当前 Phase 执行顺序、检查点、失败分流 | 产品背景全文 |
| [Phase 5 manifest](../../tasks/skills-manager-vnext-phase5.tasks.json) | P5 历史任务、依赖、write set、验证、回滚和完成条件 | 当前 Phase 动态状态 |
| [Phase 6 manifest](../../tasks/skills-manager-vnext-phase6.tasks.json) | 当前 host-native lifecycle reset 的任务、truth ladder、full gate 与 `latest_evidence` 唯一动态真值 | 在产品文档复制易漂移状态 |
| [Maintenance manifest](../../tasks/skills-manager-vnext-maintenance-design.tasks.json) | 非 Phase 的 M0/M0.2/M0.3 规划任务、evidence group 与 write-set 真值 | M1 pilot 任务、runtime/typed-core implementation 或 P6 admission |
| [Typed-core shadow manifest](../../tasks/skills-manager-vnext-typed-core-pilot.tasks.json) | TC0/TC1 的 seam、代码、parity、发布测量、回滚与 truth closeout | TC2 生产迁移或 P6 admission |
| [PowerShell 7 migration manifest](../../tasks/skills-manager-vnext-powershell7-migration.tasks.json) | PS7-only 决策、生产入口/CI/test/docs/verifier 的 write set、验证和回滚真值 | 历史 manifest 改写、typed-core 生产迁移或宿主 mutation |
| [M1 pilot registry](../../tasks/skills-manager-vnext-lean-delivery-pilot.json) | 10 个真实任务的 observe-only 样本、计数、coordination/tool observations 和 truth boundary | agent runtime、自动指标门禁或 P6 admission |
| [Routing correction manifest](../../tasks/skills-manager-vnext-capability-routing-correction.tasks.json) | P5-local 缺陷纠正的任务、write set、验证与回滚真值 | 历史 Phase 状态改写或 P6 admission |
| [Discovery redesign manifest](../../tasks/skills-manager-vnext-capability-discovery-redesign.tasks.json) | hierarchical cold discovery、host acceptance 和收口任务真值 | P6 admission、host mutation 或业务验收 |
| [Profile reconciliation manifest](../../tasks/skills-manager-vnext-profile-reconciliation.tasks.json) | P5-local profile advisor 的实现、测试、规划和收口真值 | 自动 apply、P6 admission 或 host mutation |
| [Profile optimization manifest](../../tasks/skills-manager-vnext-profile-optimization.tasks.json) | P5-local bounded canary、host replay 和收口真值 | semantic router、skill 安装删除或 P6 admission |
| [任务索引](../../tasks/todo.md) | 路由到各 track 的结构化真源 | 任务 ID、勾选、计数或 mutable status 副本 |
| [planning verifier](../../scripts/verify-vnext-planning.ps1) | 机械校验上述资产的一致性 | 判断产品价值或宿主 live acceptance |
| [host-native lifecycle planning verifier](../../scripts/verify-host-native-skill-lifecycle-planning.ps1) | 历史 P6/migration 显式诊断；检查完整投影和 fallback 边界 | 默认 quick/full closeout gate，或执行 host projection/invocation |
| [maintenance verifier](../../scripts/verify-lean-ai-delivery-planning.ps1) | 在 P5 contract 通过后校验 maintenance design 一致性和边界 | 运行 pilot、修改 runtime 或评估业务收益 |
| [PowerShell runtime policy verifier](../../scripts/verify-powershell-runtime-policy.ps1) | 默认只检查 active PS7 execution surface；`-HistoricalMigration` 显式检查已完成 migration/history/P6/typed-core 边界 | 证明所有外部消费者已迁移或 PowerShell 长期最优 |
| [Agent workflow advisory verifier](../../scripts/verify-agent-workflow-advisory.ps1) | 检查 manifest/truth、三档锚点、CLI/build wiring、host ownership、pure-layer 与 runtime-control 禁令 | 镜像行为测试内部错误码/函数/fixture，或证明 host/live acceptance |
| [capability routing verifier](../../scripts/verify-capability-routing.ps1) | 用 labelled 自然语言 corpus 验证 candidate recall、host-labelled policy、否定约束和零脚本语义自动选择 | 证明宿主模型普遍正确或业务 live acceptance |
| [profile reconciliation planner](../../scripts/plan-skill-profile-reconciliation.ps1) | 诊断 unrouted/stale/budget/overlap 并校验 host-owned proposal，输出 zero-write change-set | 自动决定 profile 语义归属或写入配置 |
| [profile reconciliation transaction manager](../../scripts/manage-skill-profile-reconciliation.ps1) | 预演/应用非活动 profile canary，接受 fresh replay 或按 receipt 回滚 | 自行调用宿主模型、永久 profile 热切换或业务验收 |
| [历史 evidence archive](../archive/change-evidence/README.md) | 保存已退出活跃账本的旧 runtime receipts | 当前 closeout 证明或运行态输出目录 |

## 3. 事实优先级

发生冲突时按以下顺序裁决产品事实：

1. 当前代码、命令输出和宿主 native probe。
2. 根 `AGENTS.md`、本目录 PRD/架构、当前 Phase spec。
3. 任务 manifest、实施计划、todo。
4. README、当前 reviewed change evidence。
5. 外部参考仓和社区资料。

历史 runtime receipts 只用于追溯，位于 `docs/archive/change-evidence/`，不参与当前完成态或 planning evidence 判定。

官方文档决定宿主加载、技能、插件、MCP、hooks 和配置语义；当前 session 的可调用能力可证明当前环境事实。社区项目只提供结构、测试和打包启发。

## 4. 状态词汇

| 状态 | 含义 | 可否写成“已完成” |
| --- | --- | --- |
| `implemented` | 代码已存在并通过本仓相应门禁 | 仅限门禁覆盖的 repo-side 范围 |
| `planning_contract` | 文档、任务和 verifier 已落地 | 只能说规划契约完成 |
| `designed` | 已有被接受的行为/架构设计，尚未实现 | 否 |
| `pending` | 已进入任务 manifest，尚未开工 | 否 |
| `conditional` | 只有触发条件满足后才评估 | 否 |
| `repo_verified` | 仓库侧静态/测试验证通过 | 不等于宿主加载或 live acceptance |
| `host_loaded` | fresh native probe 证明宿主加载 | 不等于用户/生产验收 |
| `live_accepted` | 明确的真实工作流或人工验收已完成 | 可以，必须附证据范围 |

## 5. 当前基线

CURRENT_PHASE_TRUTH_SOURCE: tasks/skills-manager-vnext-phase6.tasks.json

- 当前 Phase 是 P6 `Host-Native Skill Lifecycle Reset`。任务计数、runtime migration、truth ladder、full gate 和最新 evidence 只从上述 manifest 及其 `latest_evidence` 读取；本索引不复制这些易漂移字段。
- P6-012 的仓库侧 staged removal 已落盘并重建生成 bundle：默认生成路径不再编入 legacy `SkillRouting`，`skill-profile`/`技能配置` dispatch 已移除，profile compatibility view 保留为 `read_only` 且 `reachability_authority=none`；未生成的旧 routing source 仅供显式 compatibility verifier/test 使用。
- fresh host inventory、host evaluation、host invocation 和 live acceptance 是彼此独立的证据层；inventory 可见性不得升级为 selection、完整 body injection、execution 或业务验收。
- 任一 full receipt 只绑定其运行期间稳定的 repo source；后续 executable/config/generated/fixture 变化会使它失效。即使 full 通过，也只证明 repo-side build/test/contracts，不证明真实技能 invocation 或业务 live acceptance。
- P5 profile advisor、resident dispatcher、hierarchical cold-load 与相关架构描述保留为历史结果或 P6 迁移/兼容契约，不再表示当前普通请求的 runtime reachability 主链。
- 目标主链是 `effective host snapshot -> canonical compiler -> eligibility policy -> all-enabled native metadata -> host AI selection -> full skill injection -> invocation trace`；strict App Server dispatch 仅为显式 opt-in fallback。
- 当前 `model_context_window=272000` 的配置样本对应官方 2% ceiling 约 5440 tokens，但 P6 不把单个 TOML 值当运行真值；最终由 `HostCapabilitySnapshot` 按 surface/thread/turn 解析并以完整无 omission 验收。

历史基线（截至 2026-08-05）：

- `skills.ps1`、`skills.json`、skill projection、MCP profile/sync、目标仓审查、doctor、reference shelf 和质量门禁已经存在。
- 本目录、Phase 0 spec、Phase 0 task manifest 和 planning verifier 属于本轮新增的 `planning_contract`。
- OperationPlan/Receipt v1 的 pure constructors、validators、freshness、truth-state 和 redaction已达到 `repo_verified`；通用 legacy write path 未整体迁移，Rule Estate 已采用专用 reviewed plan/receipt/resume/rollback 合同。
- UTF-8 atomic file writer 已提取到 Infrastructure，`SaveCfg` 是首个直接 caller，其他 caller 继续通过 legacy wrapper 保持兼容。
- host capability/truth-state matrix 已达到 `repo_verified`：5 个宿主、7 条 evidence，validator 禁止无证据 affirmative claim、unknown 写入和自动 `live_accepted`；它不扫描本机安装状态。
- P0/P1/P2 已分别 9/9、9/9、7/7 `repo_verified`；2026-08-02 follow-through 增加 `rule-estate-audit`、单仓 patch，以及 reviewed global/project multi-target plan/apply/receipt/resume/rollback。真实 apply 仍需独立 review/token，且不等于 `host_loaded` 或 `live_accepted`。
- P3 已完成 7/7 `repo_verified`：只读 inventory、manifest lint、fixture-only exporter 和分层 eval 均有仓库证据；plugin install/host load/live acceptance 未执行。
- P4 已完成 6/6 `repo_verified`：unified selection + activation planning、真实投影和 16-profile fresh prompt probe 已通过；不接管宿主 runtime，未执行 plugin/MCP activation、OAuth 或 live acceptance。
- P5 已完成 5/5 `repo_verified`：task model、capability DAG、session/preheat plan、Codex App Server read-only snapshot 和 full closeout 已通过；authenticated business action 与 `live_accepted` 未执行。
- P5-local routing correction 已完成 4/4 `repo_verified`：以真实用户反馈和自然语言反例退役 lexical task model/ranking；历史 P5 状态保留，当前实现只把宿主选中的 candidate 送入确定性 policy。宿主回放仍为 `host_evaluation_partial`，业务验收未执行。
- P5-local hierarchical discovery redesign 已完成 4/4 `repo_verified`：旧 default-profile cold baseline 仅 4/8 主动触发；重构后 32-case selection 为 32/32、8-case cold-load chain 为 8/8。follow-up 增加 canonical inventory delta signal 与 cached/uncached/tool-round 指标；两个真实 A/B 已否决负收益的 combined command 方案。结果仍仅为 `host_evaluation_partial`，没有证明普遍 token 成本改善或业务验收。
- 历史 P5-local 的 2026-08-07 global skill dispatch correction 曾修复一个确定性入口缺口：无 domain/profile hint 时 router 暴露完整 portable catalog，且不要求 profile switch；该结果及其 prompt contract 证据保留供迁移审计，当前普通请求的主链以 P6 host-native projection 为准。
- P5-local profile reconciliation advisor 已完成 4/4 `repo_verified`：可报告 stale/unrouted/budget/overlap 并校验 host-owned proposal，输出 exact zero-write change-set；不自动更新 profile、不切换 active profile，reviewed apply 和真实维护收益尚未验收。
- P5-local profile optimization canary 已完成 3/3 `repo_verified`：proposal 后只允许非活动 profile 的有界事务，并以 fresh-task replay/receipt/rollback 收口；`doc-coauthoring -> content` 的 6/6 代表回放仅为 `host_evaluation_partial_pass`，不等于普遍语义正确或业务验收。
- `maintenance_design` 的 M0/M0.2/M0.3 规划包已完成 11/11 `repo_verified`；独立 `typed_core_shadow_poc` 已完成 TC0/TC1 3/3 `repo_verified`，只对 `OperationPlan/Receipt v1` 提供 package-free C#/.NET shadow parity 与本机发布观测，PowerShell runtime 仍 authoritative，TC2/生产集成 `not_started`。独立 `powershell7_runtime_migration` 已把当前 shell 支持面收敛为 `ps7_only`，这不等于 typed-core 替换。M1 因无 active owner/collection task 已转为 `deferred (0/10)`，只有显式建立两者后才恢复；coordinator/lease/model-router runtime、custom-agent/host mutation、pilot 执行/完成、业务效果和 live acceptance 均未发生；Radar automation 已删除且不参与模型编排，旧 Luna/Terra/Radar receipt 仅保留历史真值，M3/TC3 仍为 conditional。
- `governed-ai-coding-runtime` 只作为静态规则模型参考；不得恢复其已退役的目标仓 registry、同步器或中央 verifier。
- “全局 + 项目 1+1>2”已定义为 `common + platform_delta + project_action` 的责任覆盖合同；read-only Rule Advisor 已接通显式责任映射和 repo path/command 静态核验，通用自然语言语义精度仍不作外推。

## 6. 维护规则

- 改产品范围先改 PRD，再判断是否影响架构、路线图和任务 manifest。
- 改模块、数据契约或写入协议先改架构和当前 Phase spec。
- 改 Phase 状态先提供退出门禁证据，再改路线图和 task status。
- task manifest 是任务 ID、依赖、write set、状态和完成条件真源；plan/todo 只保留稳定索引，不复制动态字段。
- 运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1` 校验文档和任务一致性。
- maintenance track 先运行 vNext verifier，再运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-lean-ai-delivery-planning.ps1`；它不替代 full gate，也不创建 P6 manifest。
- 规划 verifier 通过只证明规划资产内部一致，不证明产品代码、宿主加载或真实使用效果。
