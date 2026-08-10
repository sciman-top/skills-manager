# skills-manager vNext 产品需求文档

**program_id**: `skills-manager-vnext`
**status**: accepted-direction
**implementation_status**: phase-6-host-native-lifecycle-repo-verified-host-evaluation-partial
**最后更新**: 2026-08-09

## 1. 产品结论

`skills-manager vNext` 是一个 Windows-first、local-first 的 AI 能力策展器与规则全域管理器。它帮助用户为 ChatGPT Work/Codex 与 Claude 选择、组合、投影和验证合适的 skills、plugins、MCP 与规则文件，并管理 `D:\CODE` 直属目标仓（默认排除 `external`、`文档`）及两宿主的全局用户规则，同时保持宿主原生能力、目标仓自治和真实验收边界。

面向高效 AI 软件交付时，它额外提供一层精益、按阶段启用的 advisory lens：把产品目标、主链、当前切片、停止条件、最低充分验证和完成等级说清楚，再由 ChatGPT/Codex/Claude 等宿主原生 Agent 执行。它引导和约束 AI 编码，但不复制模型的推理、编码、会话、多代理或长期运行能力。

North Star：在不复制宿主原生推理、编码和运行能力的前提下，最大化 verified value、correctness 和 user outcome，同时最小化 user attention、wall-clock latency、provider/model spend、token/context、retry、coordination/integration、maintenance cost 与不可逆失败风险；任何辅助功能都必须证明相对 native baseline 的 Pareto 净收益，并始终可绕过、可回滚、可替换、可删除。

它不是 AI coding runtime，不执行或接管 agent loop，不提供运行时模型路由、账号、认证、权限、会话、云任务、插件商店或中央跨仓治理服务。允许生成由宿主拥有、可审查、可绕过、可回滚的模型/推理强度建议、custom-agent 配置草案、fallback/escalation 策略和评估证据，但不得静默修改 active session、provider、auth 或宿主配置。

## 2. 背景与问题

当前仓库已经解决了多来源 skill 安装、构建、投影、MCP profile、目标仓审查和证据等问题，但继续扩展时出现以下系统性风险：

1. 官方产品已经提供 skills、plugins、MCP、hooks、`AGENTS.md` 和原生配置，重复实现会产生重叠与漂移。
2. skills、MCP、plugins 和规则文件的生命周期不同，塞进同一巨型配置或通用对象会造成错误抽象。
3. 当前 PowerShell 源码包含大量函数和多个超大命令文件，继续横向加功能会提高回归和维护成本。
4. 规则优化容易退化为中央同步、批量覆盖和“repo-side pass 等于宿主已接受”的旧问题。
5. AI 执行需要清晰的 requirement ID、write set、依赖、验证和回滚，普通路线图不足以支持可靠编码。
6. AI 容易在首次用户价值出现前预建框架、抽象、治理层、测试矩阵和非产品 artifact，主链却没有跑通。
7. 产品经理、架构师、开发、测试和运维被机械实例化为固定 Agent 并反复交接，增加上下文损耗、冲突和 token 成本，却没有增加责任覆盖。
8. 澄清不足会让错误方向持续执行；澄清过多又会把可自动推进的低风险工作切碎为人工审批流水线。
9. 门禁没有按风险升级，日常切片重复运行完整套件或为同一风险堆叠多层测试，反馈周期和维护成本持续膨胀。
10. 将一次成功或未经回放的总结直接升级为 skill、规则或长期记忆，会把偶然做法、项目局部事实和错误经验扩散到后续任务。
11. “多 Agent”常被误写成固定角色团队或任意并行写入；缺少结果 owner、write-set admission、单 writer、集成顺序和失败回收时，并行只会放大冲突与虚假完成。
12. “lease”与“Git CAS”容易被误解为文件级互斥锁和自动排队。Git 只能条件更新 ref、检测内容或分支漂移；同一路径的写入协调仍必须由宿主 coordinator 和单 writer 规则承担。
13. 社区 workflow、知识库和代码图工具常以能力数量或热度进入默认栈，却没有 problem evidence、native equivalent、语言覆盖、数据/权限边界、索引 freshness、净收益和退役触发。
14. “skills 会被强模型淘汰”与“不断堆 skills”都过于绝对；真正需要管理的是可复用工作流的边际价值、触发精度、上下文成本和宿主原生替代能力。

## 3. 目标用户

### 3.1 Primary persona: 多宿主本地 AI 高级用户

- 在 Windows 上同时使用 Codex App/CLI/IDE、ChatGPT Work、Claude、Gemini 或其他 agent 工具。
- 维护多个目标仓和大量 skills/MCP 来源。
- 需要清楚知道“安装了什么、为什么启用、投影到哪里、是否加载、如何回滚”。

### 3.2 Secondary persona: 团队/仓库维护者

- 需要精简、可执行的项目 `AGENTS.md` 和相邻规则文件。
- 希望从真实 build/test/CI/script 中校验规则，而不是依赖中心模板覆盖。
- 需要可审阅的建议、diff 和 repo-side evidence。

### 3.3 AI coding agent

- 需要机器可读任务、稳定 requirement ID、明确模块边界和 fail-closed 完成条件。
- 不能把设计态、候选态、repo-side gate 或 synthetic evidence 写成 live acceptance。

## 4. Jobs To Be Done

| JTBD ID | 用户目标 | 成功信号 |
| --- | --- | --- |
| `JTBD-001` | 找到适合当前任务的既有官方/社区能力 | 推荐包含来源、版本、许可证、宿主兼容和替代判断 |
| `JTBD-002` | 控制默认上下文和工具面 | profile 选择可解释、可预算、可预演、可回滚 |
| `JTBD-003` | 诊断规则文件为什么效果差 | 输出加载链、重复/冲突、事实漂移和精简建议 |
| `JTBD-004` | 安全地应用本地配置/规则改动 | plan/diff 先行，写入显式确认，备份和 receipt 完整 |
| `JTBD-005` | 判断改动是否真的生效 | repo verification、host load、live acceptance 分层报告 |
| `JTBD-006` | 让 AI 连续执行工程任务 | 每个任务都有依赖、write set、测试、回滚和 done_when |
| `JTBD-007` | 尽快获得首个可验证用户价值 | 先跑通最短端到端主链，TTFV 可观察且非产品 artifact 受控 |
| `JTBD-008` | 在有界授权内让 AI 连续执行 | 低风险切片自动推进；方向变化、授权越界或连续失败时才打断用户 |
| `JTBD-009` | 为软件生命周期当前阶段选择最小能力组合 | 只启用当前阶段必需的 lens、skill、tool 和 verifier，不机械展开完整团队/流程 |
| `JTBD-010` | 让多个 AI 安全讨论或并行处理同一目标 | 只读评议与写入执行分层；每个切片有结果 owner、base revision、互斥 write set、集成顺序和失败回收 |
| `JTBD-011` | 判断社区 workflow、知识库或代码图是否值得接入 | 每个候选都有 `adopt | adapt | defer | reject`、native baseline、真实消费者、风险、验证和 retirement trigger |

## 5. 产品原则

### PP-000 Host-native-first main-chain-first self-retiring

在授权、安全、数据、兼容、供应链和真值边界内，本项目最大化宿主 AI 原生能力并优先交付最短真实主链；无真实重复、稳定协议、已证实风险或量化热点，不新增抽象、治理或优化层。本条优先解释“继续、完成、closeout”：完成是冻结范围内的最小充分验收闭环，达到已声明的停止条件必须结束；“仍可继续做”不等于“必须继续做”。“继续/自动自主连续执行”只授权冻结范围内推进，不授权范围扩展；具体执行表示：仅在已冻结的用户目标、授权边界、`admission_scope`、`exact_write_set`、`verification ceiling` 和 `stop_condition` 内持续执行，完成该最小闭环即停止；任何新文件/模块/抽象/治理/证据、扩大 write set、升级 full、创建 worktree/子代理、吸收范围外远端/并发改动、修改宿主或产生外部副作用都是 `scope expansion`，必须先证明其防止当前任务内的独立现实失败并重新 admission；证明不足则跳过、降级、保持分支或报告独立阻断。在这些边界不变的同等风险基线下，经代表性真实任务证明的宿主原生能力越强，本项目附加治理负担必须递减；模型名称、版本升级、单次成功或模型自评本身都不是删减门禁的充分证据。本项目仅补宿主原生能力的真实缺口；当原生能力覆盖、功能重叠、消费者消失或维护成本超过净收益时，相关能力必须依据可复核证据进入弱化或退役处置，有兼容义务时先转为 `compatibility-only/deprecated`，义务结束后最终 `retired`。门禁、审计、字段、证据、skill 和流程必须覆盖独立失败模式并保持正净收益；否则合并、降级、转为兼容层或退役。仅仅缺少遥测或使用记录不能单独证明消费者消失。不得为执行本条款建立第二套治理或运行控制面。

本条是 `PP-001` 至 `PP-013` 的优先级解释，不复制或替代其具体契约。所有原则仅通过一次最小执行转译进入动作：用现有 `user_outcome/admission_scope` 表达触发与边界，`reuse_decision/main_chain_checkpoint` 表达默认动作，`authority/exact_write_set` 表达禁止越界，`verification/stop_condition` 表达最低充分验证与停止；方向、风险、授权、写集、验证上限或外部副作用扩大时重新 admission。简单任务可在进度更新中等价声明，不新增 schema、registry、verifier 或 evidence。

### `PP-001 Official-first`

官方应用、插件目录、原生 CLI/config/help/schema 能解决的问题，优先复用或调用；本项目只补发现、比较、组合、投影和证据。

### `PP-002 Local-first`

默认单机、单用户、文件和 Git 为真源。没有证据前不引入服务端、数据库、账号系统或遥测。

### `PP-003 Advisory-first`

扫描、诊断和建议默认只读。写入必须通过结构化 plan 和显式 apply。

### `PP-004 Target-owned rules`

项目规则由目标仓维护。本项目从显式工作区动态发现 Git 目标，结合全局当前规则、目标仓规则与仓内 build/test/CI/script/README 事实生成仓库专属建议；经人工或登记策略审阅后，可以形成包含全局规则和多个目标仓的 change-set，并在精确 allowlist、目标文件 hash、目标集合、锁与显式 token 约束下逐目标 apply。仓内无关 dirty paths 只作 observation 并保留；缓存清单和控制仓模板都不能成为权威中央 registry，也不能进行无审阅同质化覆盖。

规则协同采用三层责任模型：跨仓稳定语义属于 `common`，宿主加载/诊断/权限差异属于 `platform_delta`，仓库事实、命令、边界、证据和回滚属于 `project_action`。三层共同覆盖一个执行约束、且没有重复或冲突，才可判定为“全局 + 项目 1+1>2”；文件长得相似或通过静态模板检查不构成该结论。

### `PP-005 Separate domains`

Capability、RuleDocument、Profile、OperationPlan 和 Receipt 使用独立模型，只共享必要的操作 envelope。

### `PP-006 Evidence before status`

所有状态必须说明证据层级；未知或未执行的 native/live 验证必须明确为 `not_verified`。

### `PP-007 Maximum reasonable slice`

优先边界清楚、可验证、可回滚的最大合理切片；不机械拆成微任务，也不跨越多个高风险写入面。

### `PP-008 Main-chain first`

Discovery 先确定用户、问题、成功信号和非目标；实现先跑通一条最短可演示主链，再按真实失败稳定化和重构。没有主链证据前，不为未来扩展预建平台层。

### `PP-009 Adaptive governance`

治理、角色 lens、测试层级和能力组合随生命周期模式与风险升级，并在同等风险基线下随已经验证的宿主原生能力增强而递减。一个风险只使用最低充分且相互独立的证明；未产生净收益的流程、字段、skill 和指标应降级或退役。日常实现不隐式串联固定的 brainstorming、计划、worktree、子代理、review 和分支收尾流程；宿主原生 Plan/Goal/Review/agent/worktree 控制优先，窄 validator 只在当前风险或明确请求命中。日常 closeout 在 focused/full 中只走最低充分的一条，只有运行面或 release 风险变化才升级 full。TDD 仅在显式 strict test-first 合同下启用；配置、文档和生成物不机械套用 TDD、CI 或覆盖率门禁。

### `PP-010 Git truth spine, host-owned coordination`

Git 保存版本、分支、candidate commit 和集成结果；宿主原生 coordinator 保存当前任务的分解、分派、等待和合并责任。本项目只提供可验证的 planning/write-set/freshness 合同，不建立第二套 scheduler、lease service 或 agent control plane。

### `PP-011 Sparse capabilities, evidence-gated adapters`

默认工具栈保持稀疏：宿主原生推理与 Git/仓库门禁是主干，skill 只承接稳定重复 workflow，MCP/connector 只承接实时外部数据或动作，知识库/代码图只在 repo-native 搜索和文档不足的真实样本中作为可替换 adapter。没有净收益证据的能力不进入默认面。

### `PP-012 Typed-core migration without shell rupture`

PowerShell 7 是当前 Windows-first 的唯一受支持入口、运行真源和适配层。新领域逻辑优先通过稳定 JSON/protocol contract、纯函数和窄 seam 评估；只有当前失败无法用更简单方式修复，且真实消费者、对比收益、分发与回滚证据同时成立时，才重新准入 typed implementation。Windows PowerShell 5.1 不再是受支持 runtime，缺少 `pwsh` 时 fail-closed；没有这些证据，不创建第二实现或开始 typed-core 生产重写。

2026-08-05 的 TC0/TC1 `OperationPlan/Receipt v1` package-free C#/.NET `shadow_only` PoC 已完成固定 corpus parity，但因零生产/仓外消费者、无可比 AI 返工净收益和持续 SDK/full-gate 成本退役；专用 spec/manifest/evidence 仅作历史记录，PowerShell 仍是唯一当前运行真源。

### `PP-013 Bounded research and reversible reference portfolio`

外部研究默认只读且有停止条件：本仓事实与官方资料优先，社区仓、issue、文章和趋势只作候选证据。reference shelf 是可增、可降级、可退役的证据组合，不是累计式 runtime 或档案馆；搜索、阅读、fetch 或 clone 均不自动取得采纳、复制、安装、执行、宿主写入或 live authority。只有当前事实可能改变决定时才触发 research；后台代理必须有独立且有界的研究 seam，Markdown/evidence 持久化必须由用户明确要求。

## 6. 功能需求

### 6.1 Capability catalog

- `FR-CAT-001`：统一列出已知 skill、plugin、MCP descriptor 和 rule document，但保留各自类型字段，不做最低公分母扁平化。
- `FR-CAT-002`：每个外部能力记录 source URL/path、revision/version、checksum、license、trust tier、lifecycle status 和 discovered_at。
- `FR-CAT-003`：区分 runtime truth、reference shelf、official directory、host-installed inventory 和 discovery-only candidate。
- `FR-CAT-004`：同名/近似能力必须输出 canonical、duplicate、alternative 或 conflict 决策和依据，不直接按名称删除。
- `FR-CAT-005`：官方已存在等价插件/系统技能时默认推荐复用，只有明确缺口才进入自维护候选。
- `FR-CAT-006`：reference portfolio 生命周期固定为 `discover -> conditional-not-cloned -> on-demand read-only -> secondary/core-mainline -> historical-compatibility -> retire/remove`；每次转换记录消费者、来源/revision/license、证据、维护成本、决定和退役条件。
- `FR-CAT-007`：晋级要求重复当前价值或第一方权威；降级/退役由官方替代、长期无消费者、重复、stale、许可证/供应链风险或维护成本高于净收益触发。reference shelf、runtime import/source 和物理 checkout 是三个独立删除面，不得联动误删。
- `FR-CAT-008`：宿主可为当前非平凡任务自主搜索官方文档、标准、第一方源码和公开社区候选；达到足以选择可逆方案的证据停止点后停止。认证、私有源、依赖安装、上游脚本、生产动作和宿主 mutation 继续走独立授权。
- `FR-CAT-009`：本项目只拥有 manifest 指定的 `D:\CODE\external\skills-manager-references` 子树；`D:\CODE\external` 根、其他项目的 `*-references`、共享 checkout 和产品仓不进入自动 inventory、refresh、move 或 delete。`_shared` manifest 只能作为只读映射输入。

### 6.2 Profiles and desired state

- `FR-PRO-001`：profile 能选择 skills、plugins 和 MCP 工具面，并记录用途、预算和启停原因。
- `FR-PRO-002`：profile 不能保存 auth、token、provider、model、sandbox 或会话状态。
- `FR-PRO-003`：任何 projection 必须先生成目标、before/after hash、操作、风险和预期验证。
- `FR-PRO-004`：未在本次 plan 中声明的文件、配置段和宿主能力不得被修改。
- `FR-PRO-005`：当前任务不热加载时必须提示 fresh session/native probe，不能通过删除宿主系统目录强制生效。

### 6.3 Rule advisor

- `FR-RUL-001`：发现 global、repo、nested 和短期 override 规则文件，并按宿主输出可能的加载链和 precedence。
- `FR-RUL-002`：检测体量预算、重复、层级错位、宿主专属内容泄漏、陈旧命令、无依据断言、wrapper/BOM 和冲突。
- `FR-RUL-003`：用当前 repo build/test/CI/script/README 校验规则中的命令和路径；无法证明时输出 bounded uncertainty。
- `FR-RUL-004`：建议遵循“prompt/thread -> AGENTS -> skill -> plugin -> MCP -> hook/CI”的最小 surface 选择。
- `FR-RUL-005`：规则 plan 必须包含依据、目标 path、diff、风险、验证、回滚和 scope owner。
- `FR-RUL-006`：Phase 1 只读；规则写入在 Phase 2 才允许，并要求精确 Git 根、已知规则文件名、reviewed desired file、before hash、显式 token、receipt 和回滚。
- `FR-RUL-007`：不得批量生成同质化项目规则，不得恢复权威中央 target registry 或统一规则 CI；允许消费 reviewed multi-target change-set，但每个 desired rule 必须由该仓当前事实独立推导。
- `FR-RUL-008`：为每条规则分类 `common | platform_delta | project_action | deterministic_enforcement | task_local`；发现层级错位时优先移动或下沉，不在多个文件复制修补。
- `FR-RUL-009`：输出 `Global Rule -> Repo Action` 覆盖关系，区分 `covered | gap | conflict | duplicated | not_applicable`；`not_applicable` 必须有理由和恢复条件，不能用来隐藏缺口。
- `FR-RUL-010`：Codex/Claude 的共同语义应可比较，平台差异必须独立取证；不得假定文件 import、wrapper、fallback 或 override 在不同宿主具有相同语义。
- `FR-RUL-011`：渐进披露建议同时考虑常驻上下文成本与可发现性。行数/字节阈值、固定 heading 和 wrapper shape 是可配置 profile 或 finding，不是跨宿主硬编码真理。
- `FR-RUL-012`：规则审查输出采用 `adopt | adapt | reject | defer` disposition，记录来源/revision、依据、产品落点、验证方式和 truth boundary。
- `FR-RUL-013`：workspace estate audit 从当前直属 Git 根派生目标集合，应用显式排除项并报告 registry drift；历史清单不得覆盖磁盘真值。
- `FR-RUL-014`：全局用户规则只允许精确写入 Codex `AGENTS.md` 与 Claude `CLAUDE.md`；项目规则只允许目标 Git 根的 `AGENTS.md`/`CLAUDE.md`，不得借规则流程修改 provider、auth、model、sandbox、plugin/native host 配置。
- `FR-RUL-015`：estate plan 必须保存动态目标集合 hash、review provenance、逐目标 before/desired hash、风险、依据和 truth boundary；`reviewed_by_type=ai` 不构成 apply authority。
- `FR-RUL-016`：estate apply 执行 `preflight-all -> apply-one-by-one -> per-target receipt -> fail-fast`；不得实现跨仓 all-or-rollback，已完成目标保留可独立回滚证据。
- `FR-RUL-017`：目标集合漂移、目标规则 hash 陈旧、越界文件、并发锁或 resume receipt 不匹配时 fail-closed；无关 dirty paths 必须记录但不得阻断、覆盖、暂存或纳入回滚。
- `FR-RUL-018`：支持从 receipt resume 和按 action 单目标 rollback；默认不自动 commit/push 任何目标仓，也不常驻后台同步。
- `FR-RUL-019`：规则变更后的证据严格区分 `filesystem_applied | repo_verified | host_loaded | live_accepted`；fresh session/native probe 与真实用户 workflow 未执行时不得晋级。
- `FR-RUL-020`：规则体系采用 `stable normative/advisory entrypoint -> project action -> dynamic manifest/evidence state` 分层；根规则不得复制易过期任务计数、gate 或 host/live 快照。estate audit 必须检查共同段 parity、差异段独立、全局/项目预算、项目 `1/A/B/C/D` profile、Claude 首行 wrapper 与全局/项目 release 对齐，但结构通过不等于宿主已加载或强制。

### 6.4 Plugin awareness

- `FR-PLG-001`：从官方目录/宿主原生入口读取或接收 plugin inventory，不复制官方公共目录。
- `FR-PLG-002`：区分 plugin bundle、bundled skill、MCP server、connector、hook 和 optional UI。
- `FR-PLG-003`：安装、启停和授权优先委托宿主原生能力；本项目记录 intent 和 result，不保存 OAuth/token。
- `FR-PLG-004`：个人 plugin lint/export 只在已有自维护 workflow 需要分发时启用；不因“可能有用”自动打包。
- `FR-PLG-005`：distribution lint 必须检查 manifest shape、source/repository、SemVer、license、component path、skill structure 和敏感字段；缺失供应链事实时 fail-closed。
- `FR-PLG-006`：plugin evaluation 分为 deterministic static、behavior fixture、optional model snapshot、host load 和 live workflow；model score 不得作为唯一 gate。

### 6.5 MCP governance

- `FR-MCP-001`：保留当前 MCP server/profile/target 真源和向后兼容。
- `FR-MCP-002`：MCP 同步必须提供与真实写入等价的结构化 plan/diff，而不只是日志型 dry-run。
- `FR-MCP-003`：凭据只能以引用或环境要求出现；receipt、日志和进程参数必须 redaction-first。
- `FR-MCP-004`：优先使用宿主 connector/plugin 或 native MCP CLI；只有不存在原生入口时才使用受管配置段。
- `FR-MCP-005`：服务可启动、工具可列出、真实工具调用和业务验收是不同验证层级。
- `FR-MCP-006`：任务内选择必须区分 `available | needs_activation | unknown`；未启用、未连接或未认证的 MCP 只能生成 activation plan，不得静默切换 profile、写配置或启动服务。

### 6.6 Unified capability selection

- `FR-SEL-001`：以统一 descriptor/policy contract 表达 skill、MCP、plugin/app/connector 和 native tool，但保留每种能力的 path、availability、auth、side-effect 与宿主字段；统一 policy 不等于统一 runtime 或语义路由器。
- `FR-SEL-002`：宿主 AI 使用完整请求、对话上下文和可见 metadata 做唯一语义判断；确定性脚本只接受 `$skill`/`@skill` 形式的 explicit capability 或宿主标注的 candidate/exclusion，不再用正则、词频或固定同义词表决定相关性。普通文本中的能力名可能位于否定句，不构成选择授权。
- `FR-SEL-003`：profile 是任务边界的有界预热包和 capability domain/index partition；resident dispatcher 在每个可能受益于本地 skill 的非平凡请求中先暴露 portable catalog，宿主从 visible/cold 候选选择能力，不要求用户预先选 profile、不静默切 profile，也不把 profile 当权限边界。
- `FR-SEL-004`：active/cold read-only skill 输出 `use_active_skill | load_skill`；operator skill 输出 `load_skill_with_approval`；读取必须受 declared root containment 保护。
- `FR-SEL-005`：已可用 read-only/external-read 能力可自动使用；write/destructive/open-world/unknown 或 needs_activation 必须输出 approval/activation plan。
- `FR-SEL-006`：建立 direct、indirect、negative、ambiguous、多阶段、architecture/stack、cross-domain、cross-kind、native/no-skill 和 side-effect 中英文自然语言 corpus；分别验证 resident trigger、domain/candidate discovery、宿主选择、policy、完整 SKILL.md 冷加载、零 semantic auto-selection 和零 negative/side-effect violation。
- `FR-SEL-007`：discovery/policy 全程只读，不切 profile、不创建任务、不重启宿主、不额外调用 provider，也不保存或推断 OAuth/token/session 状态。
- `FR-SEL-008`：脚本必须报告 `decision_owner=host_ai`、`semantic_routing_performed=false`、`task_type/domain=host_adjudicated` 和 `confidence=null`；不得伪造未由宿主提供的意图、风险置信度或工程阶段。
- `FR-SEL-009`：capability graph 只表达 `discover -> host_adjudication -> policy -> activate` 的责任顺序；产品交付阶段与多步执行计划继续由宿主 Agent/Plan/Goal 拥有。
- `FR-SEL-010`：caller-provided session snapshot 只用于 compatible reuse/load/release planning；profile 只输出 `apply=false` preheat recommendation。
- `FR-SEL-011`：Codex host snapshot 优先来自稳定只读 App Server RPC；包含 source/captured_at/freshness/availability/callable/access/auth evidence，陈旧事实 fail-closed，单来源失败可 truthful partial。
- `FR-SEL-012`：任何辅助发现层不得降低 host-native/profile baseline；若真实 replay/canary 不能减少误调用、漏调用、用户纠正或 TTFV，则语义路由功能必须继续降级或删除，仅保留 policy kernel。
- `FR-SEL-013`：历史 profile reconciliation 诊断与 proposal 结果只作 P5 证据；当前 active runtime 不再计算 unrouted/overlap 或维护 profile membership。
- `FR-SEL-014`：所有 legacy profile proposal 入口必须返回 `status=deprecated`、`profile_reconciliation_retired`、`apply_allowed=false` 和零写入，不再生成 change-set。
- `FR-SEL-015`：历史 canary `Apply`/`Accept`/replay runtime 保持退役；当前唯一允许的写路径是显式 versioned profile migration 与 hash/backup 一致时的 receipt rollback。
- `FR-SEL-016`：历史 canary/replay receipt 只保留点时 `host_evaluation_partial` 与回滚证据，不参与当前 native selection、gate 或 live acceptance。
- `FR-SEL-017`：cold discovery 默认使用 `global_catalog_discovery`：resident dispatcher 在无显式 hint 时返回完整 `name + description + path + domains` candidate index，宿主基于完整请求选择最多三个候选；候选截断时才允许用 domain `name + purpose` 做只读窄化。不得要求宿主或用户在看见 catalog 前猜不透明 profile 名。
- `FR-SEL-018`：`DomainHint` 支持数组或逗号分隔输入并最多保留两个有效值；`ProfileHint` 仅作为向后兼容别名。candidate 必须带 domain provenance，domain hint 不改变 `active_profile`。
- `FR-SEL-019`：代表性宿主验收必须分开记录 selection trigger 与 cold-load chain，并观测 router script、router/target `SKILL.md` 全文读取、deterministic policy、profile restore、duration 和 tokens；结果最高为 `host_evaluation_partial`，不得外推为普遍语义正确或业务效果。
- `FR-SEL-020`：canonical skill inventory 的 name/path/description 新增、删除或变化必须在投影 seam 生成 ignored `host_refresh_needed` signal，包含 before/after fingerprint、精确 delta、当前 config hash 和 profile/unrouted 兼容摘要，下一动作固定为 `fresh_session_or_host_handoff`；不得生成 advisor command、直接写 profile 或恢复已退役 planner，profile-only/no-op sync 不生成新信号。
- `FR-SEL-021`：host evaluation 必须将累计 input 拆分为 cached/uncached，并记录 cache ratio、command/router/tool-round count。focused 维护默认只运行 1–2 个代表 cold case；8-case full cold corpus 仅用于结构变化或 closeout，不把累计 cached input 当作真实新增上下文。
- `FR-SEL-022`：调用方显式提供 domain/profile hint 且全部未知时必须 fail-closed，不得静默回退 `active_profile`；显式 `$skill`/`@skill` 仍可绕过 discovery 并进入确定性 policy。
- `FR-SEL-023`：candidate pool 超过 `MaxCandidates` 时必须同时报告显示数、截断前总数和 `truncated=true`，宿主应缩小到一个有效 domain 后重试，不得从不完整候选中猜测。
- `FR-SEL-024`：current host snapshot 中的 skill/MCP description、availability、callability/accessibility 必须覆盖静态 manifest/config 对应字段；`disabled`、`needs_auth`、`not_callable` 或 `inaccessible` 不得被升级为自动 load/use。
- `FR-SEL-025`：构建/投影必须在 `capability-router` 包内生成自包含 cold-discovery catalog，覆盖 canonical cold skill 的规范化 name/description、相对路径、domain membership 与 routing rules。普通目标仓不得依赖 `skills-manager` manifest/config/policy 才能发现 domain/candidate；profile 只保留预热/预算职责，catalog metadata 是 portable discovery 真源。

### 6.7 Operation plan and receipt

- `FR-OPS-001`：所有写操作共享 versioned `OperationPlan` envelope。
- `FR-OPS-002`：plan 至少包含 operation_id、domain、target、before_hash、desired_hash、actions、risk、preconditions、verification 和 rollback。
- `FR-OPS-003`：apply 必须验证 plan freshness、路径范围和 before_hash，任一不匹配 fail-closed。
- `FR-OPS-004`：apply 生成 versioned `Receipt`，记录 attempted/applied/skipped/failed actions、backup、exit code 和 verification state。
- `FR-OPS-005`：跨多个文件的写入应使用 staging/atomic replace 或可恢复事务目录；失败只回滚本次切片。
- `FR-OPS-006`：dry-run、applied、repo_verified、host_loaded 和 live_accepted 使用不同状态，不允许自动晋级。

### 6.8 AI-executable planning

- `FR-AIE-001`：当前实现 Phase 必须提供机器可读 task manifest。
- `FR-AIE-002`：每个任务必须声明 ID、状态、风险、依赖、requirement IDs、write set、步骤、测试、验证、回滚和 done_when。
- `FR-AIE-003`：任务依赖必须无环，done 任务的依赖也必须 done。
- `FR-AIE-004`：任务不得把 `agent/`、`vendor/` 或运行态 report 作为源码 write set。
- `FR-AIE-005`：planning verifier 必须检查 PRD requirement、架构决策、路线 Phase、spec、plan 和 todo 的交叉引用。

### 6.9 Evidence and reporting

- `FR-EVD-001`：报告必须包含 source revision、命令、exit code、关键输出、风险、N/A、回滚和工作树边界。
- `FR-EVD-002`：外部参考必须记录采纳、适配或拒绝决定，不继承其仓库指令。
- `FR-EVD-003`：candidate、pending_review、synthetic、repo_verified 和 live_accepted 必须保持语义隔离。
- `FR-EVD-004`：敏感路径和凭据不得写入可提交 evidence；host-local receipt 默认保留在忽略目录。
- `FR-EVD-005`：活跃 `docs/change-evidence/` 只保存 reviewed 逻辑切片；历史 runtime receipts 进入只读 archive，未来 runtime receipts 留在 ignored `reports/`。

### 6.10 Lean AI software delivery advisory

- `FR-LDL-001`：为复杂产品任务建立轻量 Product Baseline 逻辑契约，至少覆盖目标用户、问题、期望结果、成功信号、范围、非目标、关键约束、风险、验收等级与未决问题；优先复用现有 PRD、plan 和 task 字段，不新增第二套 runtime 大对象。
- `FR-LDL-002`：按当前工作状态选择 `Discovery | Main-chain | Stabilize | Refactor | Release | Operate` delivery mode；每次只激活完成当前 checkpoint 所需的最小能力组合，并允许在证据变化时回退到前一模式。
- `FR-LDL-003`：进入实现前最多提出三项会改变方案或验收的高价值澄清；其余可逆细节采用显式假设继续。相同 `issue_id` 连续失败两次后停止局部补丁，回到 baseline/slice 重新规划，方向变化或风险越界时询问用户。
- `FR-LDL-004`：产品、项目、业务、UX、架构、前端、后端、移动、测试、安全、发布和运维只作为按需责任 lens；主 Agent 对端到端结果负责，不默认实例化固定角色团队或制造角色接力文档。
- `FR-LDL-005`：为 maintenance pilot 轻量记录 TTFV、返工、人工打断、非产品 artifact、门禁耗时和 live acceptance 转化；指标仅 observe，不建立遥测服务，不以语义评分或未经 baseline 的阈值阻断交付。
- `FR-LDL-006`：重复工作先成为 `skill_candidate`，经代表任务 replay、失败样本修订、shadow、有限 canary 和 reviewed promotion 后才进入稳定 skill；持续记录触发精度、净收益、适用边界和退役条件，宿主原生能力覆盖或模型进步消除缺口时应合并、降级或 retire。
- `FR-LDL-007`：M1 pilot 只登记达到证据停止点的真实任务；synthetic、候选和当前 pilot/规划维护自身不得计入 10 个样本。优先使用近期可比 native-only 历史任务或交替匹配任务作 baseline；无可比项时只做描述性报告，不要求重复执行同一任务，也不宣称因果收益。

### 6.11 Engineered agent workflow and tool adoption

- `FR-EWF-001`：宿主原生主 Agent/coordinator 是唯一结果 owner，负责目标分解、任务 admission、分派、等待、集成和最终 truth closeout；skills-manager 不调度 worker、不维护运行队列、不接管会话或权限。
- `FR-EWF-002`：每个可执行切片必须声明 `task_id / result_owner / mode / base_revision / depends_on / exact_write_set / authority / verification / rollback / stop_conditions`；优先复用 task manifest、plan、Git branch/worktree 和 evidence，不新增第二套 lifecycle registry。
- `FR-EWF-003`：两到三个 Agent 可在设计阶段并行给出只读、独立、带假设和 trade-off 的候选方案；只有 coordinator 的综合决定进入 spec/task，讨论结论本身没有写入、apply、发布或 live authority。
- `FR-EWF-004`：并行写入只允许 write set 互斥、输入/base revision 固定且可独立验证的切片；共享文件、共享生成 seam、迁移顺序或同一外部状态必须单 writer 或串行，不能用“稍后解决冲突”代替 admission。
- `FR-EWF-005`：lease 是 coordinator 对 `owner + write_set + base_revision + expiry/recovery` 的有界 admission claim，不是文件锁或成功承诺；过期、撤销或 reassignment 前必须确认旧 writer 已停止，候选 worktree/commit 保留为可审查输入。
- `FR-EWF-006`：Git CAS 仅指 ref/expected-old-object 的条件更新，文件 freshness 使用内容 hash；它们用于检测 stale writer，不提供文件级排队、互斥、公平性或“谁先提交谁自动胜出”。共享路径仍由单 writer 和显式集成决策控制。
- `FR-EWF-007`：集成按依赖拓扑逐个消费 candidate commit/patch；每次先验证 base/freshness 与声明 write set，再处理冲突和 affected gate；最终由 integration owner 运行唯一 closeout gate，子 Agent 的局部 pass 不能升级整体状态。
- `FR-EWF-008`：工具候选必须记录 `source/revision/license/trust / problem_evidence / native_equivalent / real_consumers / disposition / integration_mode / data_auth_write_boundary / evaluation / maintenance_cost / retirement_trigger / truth_level`；缺任一安全或真值字段时保持 `defer`。
- `FR-EWF-009`：`AGENTS.md` 承接稳定仓库约定，skill 承接重复 workflow，plugin 承接可安装组合，MCP/connector 承接实时外部数据/动作，hook/script/CI 承接机械 enforcement，Git/worktree 承接版本与写入隔离；不得用一个 surface 替代所有层。
- `FR-EWF-010`：知识库/代码图/理解工具只有在至少两个独立真实任务证明 repo-native `rg`、符号/测试/文档与宿主上下文不足，且语言覆盖、隐私、索引 freshness、资源、供应链和卸载/重建路径均可验证时，才进入 read-only canary；它们不成为源码、任务或验收真源。
- `FR-EWF-011`：skill 优化只借鉴 `real sample -> replay -> shadow -> bounded canary -> reviewed promotion -> retain/revise/retire`；不得把领域研究系统的自动蒸馏、provider/embedding/solver 依赖直接解释为通用 workflow 自动升级能力。
- `FR-EWF-012`：M1 pilot 在既有 10 个真实样本中同时观察 coordination mode、shared-write policy、tool disposition、external context adapter 和 skill lifecycle action；本 maintenance 切片自身不计数，也不为观察字段建设 daemon 或 telemetry。
- `FR-EWF-013`：长链路任务的分解、DAG、Plan/Goal 状态和完成回执由宿主原生能力拥有；本仓 task manifest 仅描述本产品自己的实现工作，不升级为通用 `TaskGraph` runtime 或跨项目治理合同。
- `FR-EWF-014`：模型、reasoning effort、fallback 和可用性由用户与宿主根据当前 surface 决定；本仓不维护模型档位、proposal validator、Radar 或外部榜单决策链。
- `FR-EWF-015`：任务需要子 Agent/worktree 时直接使用宿主原生控制面；本仓不规定固定角色、固定模型三档或仓库级并发配额。
- `FR-EWF-016`：Radar automation、活动决策链及其兼容 parser 均退出当前 runtime；历史记录只保存在 spec/manifest/evidence，不进入 bundle。
- `FR-EWF-017`：共享写集、迁移、配置、Git 和最终集成保持单 writer/串行；其余串并行判断由宿主按当前任务证据负责，不通过仓库通用 admission engine 重复裁决。
- `FR-EWF-018`：仓库不得提供通用 Agent Workflow contract/runtime；只保留 capability、rule、projection 等产品领域自身必要的 plan/receipt/rollback。
- `FR-EWF-019`：生成 bundle、CLI help 和默认 quality gate 不得暴露 `agent-validate`、`agent-plan` 或专用 Agent Workflow verifier；历史 spec/manifest/evidence 继续可追溯。
- `FR-EWF-020`：advisory implementation 必须保持层次边界：domain/application 是无文件、时钟、环境、网络和 terminal 副作用的 pure layer；command adapter 只读取仓内显式输入并呈现结果；Radar refresh、spawn/wait/steer、worktree 创建和模型/effort 应用继续由宿主显式执行。

### 6.12 Retired typed-core shadow experiment

- `FR-TEC-001`：历史 typed-core PoC 只允许选择一个 read-only pure seam，至少两个真实 caller 和固定 characterization corpus；协议必须是 versioned stdin/stdout UTF-8 JSON，并固定 finding/exit/redaction contract。当前实现不得保留 shadow runtime、SDK pin、专用 verifier/test 或生产 side effect；未来恢复必须由新的真实失败、消费者、对比收益、分发与回滚证据重新 reviewed admission。

### 6.13 P6 Host-Native Skill Lifecycle Reset

- `FR-HNS-001`：宿主 AI 是技能语义选择的唯一 owner；仓库编译、资格判决和评估不得形成 lexical、embedding、第二模型或 profile-owned 语义真源。
- `FR-HNS-002`：提供 versioned `HostCapabilitySnapshot`，按 turn override、thread effective model、effective config layering、model/provider catalog、unknown fallback 解析有效上下文窗、metadata budget、surface 和 skills inventory。
- `FR-HNS-003`：App Server、fresh CLI probe 和 offline config adapter 映射同一 snapshot schema；直接读取 `config.toml` 只能标记 `source=config_fallback`。
- `FR-HNS-004`：`SkillCatalogCompiler` 从受管 roots 编译完整 canonical inventory 和 provenance，不得以 profile/current_profile 过滤 enabled skill。
- `FR-HNS-005`：`SkillEligibilityPolicy` 只判决 containment、freshness、availability、dependency、side effect、approval 和 surface compatibility；语义置信度不得放宽 deny。
- `FR-HNS-006`：metadata planner 使用宿主有效 token ceiling；已知上下文默认 ceiling 为 `floor(context_window * 0.02)` 或宿主更严格值，headroom 可配置，禁止用固定字符数伪装 token 真值。
- `FR-HNS-007`：每个 eligible enabled skill 必须进入宿主原生 discovery projection；验收要求 `enabled_total == kept_total`、`truncated=false`、`omitted=0`。
- `FR-HNS-008`：metadata 质量以 concise description lint 和 direct/indirect/negative/ambiguous/no-skill corpus 验证；修复选择错误时优先改 metadata，不增加第二套 semantic router。
- `FR-HNS-009`：提供 `NativeInvocationTrace`，区分 listed、selected、injected、executed 和 abstained；不可观测层保持 partial/unknown。
- `FR-HNS-010`：legacy router/profile 只能在 zero-write shadow 中与 native path 对比，shadow 结果不得改变当前执行或覆盖宿主选择。
- `FR-HNS-011`：profile、active_profile、current_profile、reconciliation 和 canary 从可达性主链退役；迁移期可兼容读取，但必须有 versioned migration、round-trip 和 rollback receipt。
- `FR-HNS-012`：strict dispatch 仅允许显式 opt-in；采用 pre-turn bounded candidates、宿主裁决、支持时的 App Server `type=skill` 注入和 trace，普通请求不得默认进入。
- `FR-HNS-013`：legacy runtime 只在 all-enabled projection、shadow evidence、compatibility migration、fresh host evidence 和 rollback gate 满足后 staged removal；P5 文档和 evidence 保持历史真值。

### 6.14 P6 当前实现与验收边界

CURRENT_PHASE_TRUTH_SOURCE: tasks/skills-manager-vnext-phase6.tasks.json

2026-08-08 的 P6-012 repo-side closeout 与 `1097/1097` full 结果是 point-in-time 历史证据。P6-001 至 P6-012 的仓库侧切片、staged removal、source/config/生成链和 compatibility verifier 已落盘；当前任务计数、runtime migration、truth ladder、full authority 与最新 evidence 只从上述 manifest 读取。

当前仓库侧 compatibility boundary 为：legacy `SkillRouting` source 及其自测已删除，`技能配置`/`skill-profile` dispatch 已退役；profile compatibility view 仅为 `read_only`、`reachability_authority=none`，独立 verifier 只读取配置并报告 migration compatibility 状态。P5 profile advisor、resident dispatcher 与 cold-load 描述保留为历史或迁移契约，不是普通请求的当前语义选择 owner。

fresh inventory、host evaluation、injected/executed invocation 与业务 acceptance 是独立层级；它们只能由对应证据晋级，不能由 metadata visibility、focused tests 或 planning verifier 推导。tracked manifest 不复制 `passed|stale` 运行态：当前 full 是否有效只由 `reports/quality-gates/current.json` 指向的 immutable full receipt 及 exact-current-source 校验决定。

## 7. 非功能需求

- `NFR-COMP-001`：现有 `skills.json`、lock、CLI aliases、generated `skills.ps1` 和 MCP/skill projection 行为保持兼容。
- `NFR-MNT-001`：新增业务逻辑进入明确 bounded context；不再向超大 command 文件无界追加。
- `NFR-MNT-002`：开发源码模块化，发行仍允许单文件 bundle。
- `NFR-PORT-001`：PowerShell 7 是唯一受支持的开发、CI、安装和运行 runtime；当前最低版本为 7.0，推荐 PowerShell 7.6 LTS。入口、子进程和 CI 必须只解析 `pwsh`，缺失时 fail-closed，不提供 Windows PowerShell 5.1 fallback/smoke。
- `NFR-SAF-001`：只读命令不能调用 provider、写宿主配置或改变 active profile。
- `NFR-SAF-002`：所有外部写入必须显式授权；高风险写入必须先有可执行回滚。
- `NFR-SAF-003`：profile compatibility view 与 retired proposal stub 必须 network-free、provider-free、zero-write，且不得修改 `active_profile`、安装/删除 skill 或写宿主配置；当前写路径仅限 versioned migration/rollback，旧 proposal/canary 入口必须 fail-closed 为 `deprecated`。
- `NFR-SAF-004`：历史 profile canary receipt/backup 仅作为迁移与回滚兼容证据保留；不得恢复 canary apply/accept、直接调用 provider、修改 skill/plugin/MCP 安装、永久切换 active profile，或在 hash 漂移后覆盖用户修改。
- `NFR-SAF-005`：hierarchical discovery 只读、network-free、provider-free、zero-write；domain/purpose 和宿主语义选择不能覆盖 containment、freshness、availability、side-effect、approval 或 activation。
- `NFR-SAF-006`：reconciliation signal 属于 advisory handoff；写入失败只记录 warning，不得阻断已验证的 skill projection，也不得触发第二模型、active profile 热切换或无 token apply。
- `NFR-SEC-001`：不持久化 API key/OAuth/token；日志、plan 和 receipt 使用 redaction-first。
- `NFR-PERF-001`：inventory/doctor 使用有界扫描、缓存和明确超时；性能退化不能通过跳过完整性校验解决。
- `NFR-OBS-001`：关键阶段输出稳定的 machine-readable status 和 phase timing。
- `NFR-TST-001`：测试按风险选择最低充分层级；优先真实输入形状和关键失败模式，不要求每个改动机械同时新增 unit、fixture/golden、E2E 和 native probe。更高层不可用时按 N/A 记录恢复条件。
- `NFR-GOV-001`：编码前记录问题证据、官方/既有复用结论、最小方案、write set 与停止条件；full gate 仅由运行面、安全、数据/迁移、公开契约、依赖/包、release 或 focused 发现的跨面风险触发，独立 evidence 仅在现有切片证据不足时增加。
- `NFR-GOV-002`：P5 后默认 maintenance hold；没有跨域真实失败、已消费 P5 输出、现有 seam 无法修复和用户明确授权，不创建 P6 manifest 或 schema major。
- `NFR-TRU-001`：任何“完成/生效/验收”声明必须绑定 verification level 和 evidence path。
- `NFR-LDL-001`：maintenance design/pilot 不增加 schema major、daemon、数据库、长期任务引擎、固定角色 runtime 或任何宿主写入行为。
- `NFR-LDL-002`：LLM 判断、语义评分和自我总结只能作为建议或候选信号，不得成为唯一硬门禁、权限判定或 skill promotion 依据。
- `NFR-LDL-003`：主链优先于完备架构，测试采用最低充分层级；`designed | planning_contract | implemented | repo_verified | host_loaded | live_accepted` 不得越级。
- `NFR-EWF-001`：M0.2 只增加文档、task/registry 字段、verifier 与 tests；禁止新增 scheduler、lease daemon、数据库、provider router、worker runtime、profile/host mutation 或 schema major。
- `NFR-EWF-002`：共享 write set 的默认策略必须是 `single_writer`；任何 parallel-write exception 都必须有可复核的路径互斥证明和 integration owner，不能由模型置信度或 Git merge 成功替代。
- `NFR-EWF-003`：外部 context adapter 默认只读、最小 root、redaction-first、可重建且可移除；索引或图谱过期、语言不支持、权限不明或证据来源缺失时 fail-closed，并回退 repo-native 工具。
- `NFR-EWF-004`：tool/skill promotion 的语义判断可由宿主 AI 提议，但 availability、freshness、权限、预算、供应链、测试和 truth-level advancement 必须由确定性证据或人工 review 约束。
- `NFR-EWF-005`：模型策略是多目标 Pareto 建议，必须同时观察正确性/用户结果、费用、wall-clock、token/context、重试和集成成本及不可逆风险；不得把动态 Radar 分数压成不可解释的固定总分或单项硬门禁。
- `NFR-EWF-006`：PS7-only runtime policy 必须覆盖 source、generated bundle、installer、`skills.cmd`、CI、tests、subprocess wrapper、runbook 和 release contract；历史 Phase/证据中的 5.1 记录只保留为历史事实，不能恢复为当前支持承诺。新 typed core 候选仍须以 versioned protocol、single source of truth、PS7 回滚路径和可删除 PoC 证明，不得在无门禁的情况下形成双写或双真源。
- `NFR-EWF-007`：不得重新引入仓库 scheduler/daemon/database/provider gateway、Radar fetch、通用 TaskGraph/model policy 或仓库发起的 custom-agent/config/profile/session mutation；宿主侧授权动作不改变本仓 runtime 边界。
- `NFR-EWF-008`：现有 build/dispatch/gate contract 必须阻断 `agent-plan`、`agent-validate`、Agent Workflow 源模块或专用 verifier 回流；该负向约束复用现有测试，不建立新的治理 registry。
- `NFR-TEC-001`：替代技术栈只在新的真实失败或消费者触发时比较 C#/.NET、TypeScript/Node、Python 和 Rust 的 Windows/native CLI 适配、类型/并发、分发、供应链、维护与回滚成本；不得把历史 C#/.NET 偏好升级为当前目标架构或默认依赖。
- `NFR-TEC-002`：历史 TC1 曾 pin 受支持 LTS SDK、保持零第三方 `PackageReference`、4/4 corpus parity、结构化协议负例、零生产引用和可删除回滚；这些结果仅作历史 evidence。当前 PowerShell runtime 必须保持 authoritative，任何未来生产迁移都必须重新证明单一真源和净收益。
- `NFR-HNS-001`：P6 admission 是 planning/implementation authority，不自动授权宿主重启、provider/auth/session/plugin/MCP mutation 或业务 live action。
- `NFR-HNS-002`：snapshot 每个推导值携带 source、captured_at、freshness 和 unknown reason；未知不得被默认配置提升为 runtime truth。
- `NFR-HNS-003`：host adapters bounded、timeout、redaction-first、provider-free、zero-write；surface 不支持时报告 `platform_na`。
- `NFR-HNS-004`：metadata budget 溢出列出 exact offenders 和 compaction result；不得静默增大 ceiling、切 profile 或丢弃 enabled skill。
- `NFR-HNS-005`：projection apply 需要显式 token、expected hash、atomic replace、receipt 和 drift-safe rollback；plan 保持 zero-write。
- `NFR-HNS-006`：activation corpus 只评估 metadata/host behavior，不得成为脚本 semantic selector 或权限门禁。
- `NFR-HNS-007`：invocation trace redaction-first、correlated、freshness-aware；visibility 不得升级为 full skill body execution。
- `NFR-HNS-008`：退役裁决阶段的 shadow comparison 必须 writes=0、不调用第二模型、不把 partial trace 当作输赢依据；P6 removal gate 完成后删除比较器和专用测试，仅保留历史 manifest/evidence。
- `NFR-HNS-009`：profile migration 兼容读取旧 schema，且旧数据可 round-trip 恢复；当前 task 不热切换 active profile。
- `NFR-HNS-010`：strict fallback 与 native main path 复用同一 eligibility policy，候选集有界，缺宿主裁决或 injection 支持时 fail-closed/platform_na。
- `NFR-HNS-011`：P6 真值阶梯固定为 `planning_contract -> implemented -> repo_verified -> host_inventory_loaded -> host_evaluation_partial -> host_invocation_observed -> live_accepted`，不得越级；inventory 不得冒充 invocation。

## 8. 产品级验收

vNext 不能以“所有 Phase 代码已写完”作为单一验收。每个 Phase 独立验收，完整产品至少满足：

1. 用户能获得统一但不扁平化的 capability inventory。
2. 默认 profile 不因扩展 plugin/rule 能力而超出现有上下文预算。
3. rules advisor 能在不写目标仓的前提下给出可复核 findings 和 patch plan。
4. MCP、skill projection 和 rule apply 使用一致的 plan/freshness/receipt 语义。
5. 任一 apply 中断后能恢复本次切片，不覆盖无关用户修改。
6. 官方插件或系统技能已覆盖的能力不会被重复安装为默认自维护副本。
7. fresh native probe 与 repo-side gate 分开呈现；未执行 live workflow 时保持 `not_verified`。
8. AI 能按 task manifest 执行当前 Phase，不需要从多份文档猜测 write set、依赖或完成条件。
9. AI 软件交付任务能先给出 Product Baseline、当前 delivery mode、单一主链和 Slice Contract，并在 checkpoint 前保持 write set 与停止条件稳定。
10. 同类失败两次、方向证据变化、授权越界或 live/生产动作出现时会停止并重新规划或询问；普通低风险实现不会因固定角色审批而中断。
11. 交付效果只以真实 pilot 观察；规划包、synthetic replay 或 repo verifier 不能被表述为真实业务收益。
12. capability 辅助层必须在“只使用宿主原生匹配 + 当前 profile”基线之上证明净收益；deterministic corpus、profile 可见性和少量 host replay 分别报告，不互相冒充。
13. typed-core TC1 的历史完成只能证明固定 `OperationPlan/Receipt v1` corpus 的 shadow parity；当前实现已退役，不得宣称 CLI/生产迁移、PowerShell 替换或默认分发已接受。
13. skill inventory 变化后可获得确定性的 profile drift 诊断；宿主 proposal stale、引用未知对象、触碰 protected skill、产生 no-op/冲突或超预算时 fail-closed，且诊断全过程不改变配置和 active profile。
14. 历史 profile canary 的 receipt 和 rollback 必须可用于兼容迁移审计；当前 `Apply`/`Accept` 固定 fail-closed 为 `deprecated`，只有显式 versioned migration/rollback 可写配置，且不得恢复 profile reachability authority。
15. 多 Agent 设计评议可并行，但所有写入任务都能追到一个 result owner、固定 base revision、互斥或单 writer write set、集成顺序和最终 closeout owner。
16. verifier 能阻断“Git CAS 等于文件排队/抢占胜出”、共享路径无 owner 并行写入、社区 control plane 偷渡、无证据工具接入和 P6/live truth 越级。
17. 任一外部知识库或代码图 adapter 在接入前都有两个独立真实失败样本、语言/隐私/freshness/资源/供应链/卸载证据；条件不满足时保持 defer，repo-native 工具仍可完成主链。
18. skill/tool 的保留以真实 replay/pilot 净收益为依据；强模型或宿主原生能力覆盖后能通过已记录 retirement trigger 降级或删除，不以资产数量作为成功指标。
19. build、CLI help、生成 bundle、默认 gate 和当前测试面均不包含 `agent-plan`、`agent-validate` 或通用 Agent Workflow 实现。
20. 历史 Agent Workflow spec、manifest 和 evidence 仍可追溯，但不被当前索引写成 active truth source，也不能证明宿主行为或业务效果。
21. 日常 AI 编码直接使用宿主 Plan/Goal/subagent/worktree 能力；本仓只在自身产品领域存在独立失败模式时增加确定性合同。

## 9. 成功指标

成功指标先 observe，不为了指标构建遥测服务：

| Metric ID | 指标 | 初始目标 |
| --- | --- | --- |
| `MET-001` | 默认 profile 元数据预算超限次数 | 0 |
| `MET-002` | apply 前存在 machine-readable plan 的写入比例 | 100%（进入新协议的领域） |
| `MET-003` | receipt 可执行回滚覆盖率 | 100%（进入新协议的领域） |
| `MET-004` | 规则建议中的失效命令误报率 | 通过 fixture + 人工抽样建立 baseline 后再定阈值 |
| `MET-005` | 官方已有等价能力却新增自维护副本 | 0 个未经 waiver 的新增 |
| `MET-006` | repo_verified 被误报为 live_accepted | 0 |
| `MET-007` | task manifest 与 plan/todo 漂移 | planning verifier 中 0 finding |
| `MET-008` | TTFV（任务开始到首个可演示、可验证主链） | observe-only；10-task pilot 后建立 baseline |
| `MET-009` | 因需求/方向误解造成的返工切片数 | observe-only；按任务记录原因，不预设硬阈值 |
| `MET-010` | 需要用户介入的非预期人工打断次数 | observe-only；区分必要风险确认与流程噪声 |
| `MET-011` | 非产品 artifact 数量与维护成本 | observe-only；无消费者或无验证价值的候选进入删除评审 |
| `MET-012` | `repo_verified` 向明确 `live_accepted` 的转化 | observe-only；未运行真实工作流时保持 not_run |
| `MET-013` | capability routing precision/recall、误调用、漏调用与用户纠正 | labelled corpus + 只读 host replay 分层记录；未建立跨任务 baseline 前不设硬阈值 |
| `MET-014` | retired profile proposal 入口的 fail-closed 与零写入 | compatibility observation；不恢复 proposal/canary 指标或自动 apply 门禁 |
| `MET-015` | 历史 profile canary receipt 的迁移/回滚兼容性 | compatibility observation；当前 canary apply/accept 已退役 |
| `MET-016` | cold discovery 的 uncached input、cached ratio、tool rounds 与 latency | observe-only；按同 prompt A/B；任何减少回合但增加 uncached/延迟或降低完整读取可靠性的方案必须回退 |
| `MET-017` | 多 Agent 写入冲突、stale candidate、shared-write reassignment 与集成返工 | observe-only；按真实任务记录，未建立 baseline 前不设并行度或冲突率 KPI |
| `MET-018` | 工具候选的 adopt/adapt/defer/reject 分布、真实消费者、维护成本与退役转化 | observe-only；热度、star 或一次演示不构成 adoption success |
| `MET-019` | 外部 context adapter 相对 repo-native baseline 的检索命中、纠正、延迟、资源和 freshness 失败 | 仅在触发 read-only canary 后记录；无两个独立失败样本时不运行 |

## 10. 发布和兼容边界

- Phase 0 不增加用户可见新领域能力，只建立 schema、模块 seam、operation contract 和规划门禁。
- Phase 1 只增加 read-only inventory/rules advisor，不新增规则写入。
- Phase 2 才引入显式 apply；必须保留现有命令兼容和 feature flag/observe 窗口。
- Phase 3 才评估 personal plugin lint/export，不创建公共 marketplace。
- Phase 4 只增加统一 capability selection 和 activation planning；宿主仍拥有 MCP/plugin/tool runtime、认证、权限、approval 和 session。
- Phase 5 增加 task understanding、capability DAG、session reuse planning 和只读 host snapshot；仍不接管执行、安装、认证、审批、profile 或 session mutation。
- P5 maintenance correction、profile reconciliation advisor、hierarchical cold-load 与 profile optimization canary 保留为历史结果或 P6 迁移/兼容证据，不再代表当前 reachability 主链。
- P6 已将 profile reachability authority 退役；旧 canary `Apply`/`Accept` 固定返回 `deprecated` 且零写入，当前只保留显式 versioned migration/rollback 和只读兼容报告。
- 当前主链是 `effective host snapshot -> canonical compiler -> eligibility policy -> all-enabled native metadata -> host AI selection -> full skill injection -> invocation trace`；strict fallback 只在宿主原生注入不可用且显式请求时启用。
- P5 后的 `maintenance_design` 已建立 Lean Delivery advisory 规划契约；M1 registry 当前为 `deferred (0/10)`，因为没有 active owner/collection task，只有显式建立两者后才恢复。它不是新 Phase，也不证明 pilot 已执行、完成或产生业务效果。
- `maintenance_design` M0.2 只补强 host-owned coordination、single-writer write-set admission、Git freshness/CAS 语义、tool disposition 和 context-adapter admission；不引入 coordinator/lease runtime，也不安装 Trellis、AGOS、GBrain、CodeGraphContext、Understand Anything 或 OptSkills。
- `maintenance_design` M0.3 的 TaskGraph/model policy 是历史 planning truth；后续通用 advisory runtime 因无外部消费者且与宿主原生能力重叠已退役。独立 TC1 shadow PoC 也已因无消费者和净收益证据退役；Radar automation 已删除，旧 Luna/Terra/Radar 记录只作为历史 receipt。
- GUI、daemon、远端协作、数据库和 domain core 重写均为 conditional，不进入当前承诺。

## 11. 官方与社区依据

### 官方采纳

- [OpenAI Codex Best practices](https://learn.chatgpt.com/guides/best-practices)：采用短而准确的 `AGENTS.md`、按真实摩擦演进规则、按需启用 MCP、把稳定重复工作沉淀为 skill。
- [OpenAI AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：采用 global/repo/nested 加载层级和项目事实归属，不假定 hosted surface 与本机文件自动同步。
- [OpenAI Rules](https://learn.chatgpt.com/docs/agent-configuration/rules)：`.rules` 用于 sandbox 外命令决策且仍属 experimental；自然语言 `AGENTS.md` 不承担可重复权限 enforcement。
- [OpenAI Plugins](https://learn.chatgpt.com/docs/plugins) 与 [Plugin architecture](https://developers.openai.com/plugins/concepts/plugins)：采用“先发现/安装现有 plugin”和最小 plugin shape，区分 skill、MCP/connector、hook 与 optional UI。
- [OpenAI Skills](https://developers.openai.com/plugins/concepts/skills)：采用 progressive disclosure，以及 workflow instructions 与 live data/action 的清晰边界。
- [OpenAI MCP](https://learn.chatgpt.com/docs/extend/mcp) 与 [Hooks](https://learn.chatgpt.com/docs/hooks)：MCP 用于外部动态数据/动作；只有确定性 lifecycle enforcement 才进入 hook/script/CI。
- [OpenAI Codex execution plans](https://developers.openai.com/cookbook/articles/codex_exec_plans)：适配长任务的目标、进度、决策和验证追踪，不把计划本身当作交付结果。
- [OpenAI Long-running work](https://learn.chatgpt.com/docs/long-running-work)：`/plan`、`/goal` 与持久目标由宿主承接；本项目只提供可验证的目标/切片输入，不另建 goal runtime。
- [OpenAI Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)：独立探索、测试和分诊可由宿主有界并行；共享 write set 保持单 writer，本项目不托管固定角色团队。
- [OpenAI Models](https://learn.chatgpt.com/docs/models) 与 [Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference)：模型、reasoning effort、default subagent model 和显式 agent override 属于宿主原生配置/执行面；本项目只生成可审查 proposal，不热改 active session。
- [OpenAI Memories](https://learn.chatgpt.com/docs/customization/memories)：local memories 是可选回忆层，稳定规则仍进入 `AGENTS.md`/仓库文档；本项目不复制记忆库。
- [OpenAI Codex App Server](https://learn.chatgpt.com/docs/app-server) 与 [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk)：深度客户端集成和编程式线程控制已有原生入口；只有未来独立产品需求与 P6 admission 同时成立时才评估集成，不在本仓复制。
- [OpenAI Scheduled tasks](https://learn.chatgpt.com/docs/automations)：稳定重复流程可由宿主 scheduled tasks + skill 承接；先人工跑通并验证，再自动化。本仓不建 daemon/scheduler。
- [Git `update-ref`](https://git-scm.com/docs/git-update-ref) 与 [`git push --force-with-lease`](https://git-scm.com/docs/git-push)：采用 expected-old ref 作为 stale-write guard；明确它们不提供文件级锁、排队、公平性或自动冲突裁决。
- [MCP specification](https://modelcontextprotocol.io/specification/latest) 与 [MCP Registry](https://registry.modelcontextprotocol.io/)：采用 schema、versioning、validation 和来源/所有权边界。
- [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6)：推荐当前 LTS，并以官方生命周期安排升级复核。
- [Migrating from Windows PowerShell 5.1 to PowerShell 7](https://learn.microsoft.com/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.6)：采用 side-by-side 安装与显式 `pwsh` 迁移指导；项目选择不再支持 5.1，不声称微软已终止其 Windows 支持渠道。
- [.NET application publishing](https://learn.microsoft.com/dotnet/core/deploying/) 与 [single-file deployment](https://learn.microsoft.com/dotnet/core/deploying/single-file/overview)：typed-core PoC 比较 framework-dependent/self-contained/single-file 的体积、启动、平台和更新成本，发布形态由实测而非偏好决定。

### 社区采纳或适配

- [wshobson/agents](https://github.com/wshobson/agents)：采纳细粒度 plugin、单一源到宿主原生产物、结构校验；拒绝把大规模多代理/模型分层直接移入本项目。
- [obra/superpowers](https://github.com/obra/superpowers)：采纳 evidence-before-claims、可组合 workflow 和行为测试；拒绝默认强制全部流程和 always-on bootstrap。
- [mattpocock/skills](https://github.com/mattpocock/skills)：采纳小、可组合、可编辑副本与订阅式 plugin 的区别；拒绝由 workflow 接管完整工程过程。
- [github/spec-kit](https://github.com/github/spec-kit)：适配从 constitution/spec/plan/tasks 到实现的可追踪结构；拒绝强制 TDD、固定文件数和所有任务人工审批等与本仓风险分级不符的流程。
- [OpenHands](https://github.com/All-Hands-AI/OpenHands) 与 [LangGraph](https://github.com/langchain-ai/langgraph)：仅作为 agent runtime、状态图和可恢复执行的对照；当前 defer，不把 runtime/control plane 移入 skills-manager。
- [mindfold-ai/Trellis `v0.7.0-beta.1`](https://github.com/mindfold-ai/Trellis/tree/v0.7.0-beta.1)：适配 repo 内 spec/task/journal、分阶段验证和可移交上下文；其自动 skill/subagent 四阶段控制面与 AGPL-3.0 分发边界和本仓原生能力重叠，因此不安装、不作为默认 runtime。
- [zsr131550/agos `0.1.0` Alpha](https://github.com/zsr131550/agos)：适配 `write_scope`、candidate patch、ledger/receipt 和 merge gate 的协议思想；上游明确声明全程 AI 制作且无人审核，当前 reject 其 runtime/dashboard/hook 接管，只保留待核参考。
- [fujiwaranoM0kou/OptSkills](https://github.com/fujiwaranoM0kou/OptSkills)：只借鉴 trajectory clustering、deterministic serialized library write、独立 eval 与 checkpoint；它面向数学优化且依赖 provider、embedding、Python 3.12/Gurobi 等，不是通用 skills/workflow 自动升级器。
- [garrytan/gbrain](https://github.com/garrytan/gbrain)：作为完整知识库、图谱、daemon/MCP 与权限系统参考；当前 repo 文档/搜索没有两个独立失败样本，且其数据库、长期 ingestion、密钥和大量工具面过重，保持 defer。
- [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) 与 [Egonex-AI/Understand-Anything](https://github.com/Egonex-AI/Understand-Anything)：只借鉴 read-only code graph、影响分析、增量索引和可视化；前者当前 23 种语言不含 PowerShell，后者首轮多 Agent/LLM 分析与持久图谱成本高，均不进入本仓默认栈。
- “souljourney lightweight workflows”未能唯一定位到可核验的公开工程仓库；在 source/revision/license 可确定前保持 `defer`，不把口述名称写成已采用来源。
- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)：仅在外置个人 Agent/长期任务需要独立验证后评估组合；不得作为本仓的默认执行内核或真值源。
- [Obsidian](https://obsidian.md/)：可作为用户拥有的产品知识库和长期笔记界面；本仓只消费明确导出的文档/链接，不把 vault、插件或双链索引变为必需 runtime。
- `D:\CODE-other\governed-ai-coding-runtime`：采纳规则最小化、`common/platform_delta/project_action` 层级职责、共同语义与平台差异分离、native probe 和 wrapper 启发；把固定结构/体量预算适配为 profile；拒绝恢复已退役的中央 registry/sync/audit runtime。精确 revision、逐项 disposition 和证据见 [规则治理参考采纳矩阵](rule-governance-adoption-matrix.md)。

## 12. 决策与待确认

本 PRD 已采用以下默认决策，不阻塞 Phase 0：

- `DEC-PROD-001`：产品定位为 local capability curator + rule advisor。
- `DEC-PROD-002`：规则永久默认 advisory-first；显式 apply 是唯一写入入口。
- `DEC-PROD-003`：PowerShell 继续作为当前兼容入口、宿主/文件适配层和单文件发行面；领域核心先通过 versioned protocol 与窄 pure seam 降低复杂度。历史 C#/.NET typed-core PoC 已退役，未来只有新的失败、消费者和净收益证据通过 reviewed admission 后才可重评，不允许形成双真源。
- `DEC-PROD-004`：不立即改仓库名；只有规则/plugin 两条新主路径经过真实使用验收后再评估品牌更名。
- `DEC-PROD-005`：未来 Phase 在进入实施前各自生成详细 task manifest，避免提前维护大量猜测任务。
- `DEC-PROD-006`：Rules Advisor 使用责任覆盖模型，不建立通用规则 AST、重型 policy engine 或强制统一模板。
- `DEC-PROD-007`：Lean AI Software Delivery 是 P5 后的 advisory maintenance track；先通过 10 个真实任务 observe-only pilot 证明净收益，再决定保留、修订、退役或是否形成新的 P6 admission 输入。
- `DEC-PROD-008`：Goal、subagents、scheduled tasks、local memories、App Server/SDK 属于宿主 native baseline 和本项目退役触发器；只有本仓独有的 capability/rule discovery、advice、bounded transaction 与 verification seam 可在证据支持下保留。
- `DEC-PROD-009`：工程化多 Agent 采用“host-owned coordinator + read-only design panel + disjoint-worktree execution + single-writer shared seam + sequential integration”；Git 是真值主干和 stale guard，不是文件任务队列。
- `DEC-PROD-010`：社区 workflow、知识库、代码图和自动 skill 学习均先进入证据化 disposition；当前候选只采纳协议启发，不安装运行时，M1 真实任务证据决定后续 retain/adapt/retire。
- `DEC-PROD-011`：宿主 AI 独立拥有任务语义、DAG、串并行、模型档位和 spawn/wait/integration；skills-manager 不再提供通用编排建议或 admission，只保留自身产品领域的确定性安全合同。
- `DEC-PROD-012`：当前 shell runtime 强制收敛为 PS7-only，以删除 5.1/7 双运行时解析、quoting、encoding 和测试分支；这是支持面迁移，不是 typed-core 生产迁移。历史 typed-core PoC 已因真实收益不足、兼容/SDK 成本和无消费者退役；未来只有新的独立失败和 reviewed 净收益证据才能重新准入一个可删除 seam。
- `DEC-PROD-013`：P6 正式采用 host-native skill lifecycle reset；profile/router/cold-load 不再是技能可达性或语义选择主链，完整 native discovery、确定性 eligibility 和 invocation trace 成为新边界。

以下选择有意延迟到有真实代码/宿主证据的任务，不允许 AI 在更早任务中猜定：

- `VAL-P0-003`：schema dialect、validator 实现和 observe/enforce 切换，以当前 `skills.json` 变体和本机可用 runtime 为依据，不为验证器额外引入常驻服务。
- `VAL-P0-005`：首个 Infrastructure seam 必须由至少两个真实 caller 和 characterization tests 选出，不按目标目录图预建空模块。
- `VAL-P0-006`：MCP plan 的最终 CLI spelling 先读取当前 parser/alias tests；行为合同先于命令拼写。
- `VAL-P0-007`：host matrix 的 affirmative capability 必须由当前官方文档、help/schema 或 native probe 支持；未知值保持 unknown/platform_na。
- `VAL-P1-MET`：semantic finding precision 和性能阈值要先用代表仓建立 baseline，再决定 gate 阈值。
