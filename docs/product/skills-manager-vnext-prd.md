# skills-manager vNext 产品需求文档

**program_id**: `skills-manager-vnext`
**status**: accepted-direction
**implementation_status**: phase-5-adaptive-capability-fabric-repo-verified-maintenance-hold
**最后更新**: 2026-08-04

## 1. 产品结论

`skills-manager vNext` 是一个 Windows-first、local-first 的 AI 能力策展器与规则全域管理器。它帮助用户为 ChatGPT Work/Codex 与 Claude 选择、组合、投影和验证合适的 skills、plugins、MCP 与规则文件，并管理 `D:\CODE` 直属目标仓（默认排除 `external`、`文档`）及两宿主的全局用户规则，同时保持宿主原生能力、目标仓自治和真实验收边界。

面向高效 AI 软件交付时，它额外提供一层精益、按阶段启用的 advisory lens：把产品目标、主链、当前切片、停止条件、最低充分验证和完成等级说清楚，再由 ChatGPT/Codex/Claude 等宿主原生 Agent 执行。它引导和约束 AI 编码，但不复制模型的推理、编码、会话、多代理或长期运行能力。

North Star：在不复制宿主原生推理、编码和运行能力的前提下，持续提高每单位用户注意力、token 与长期维护成本所产生的可验证用户价值；任何辅助功能都必须证明相对 native baseline 的净收益，并始终可绕过、可回滚、可替换、可删除。

它不是 AI coding runtime，不执行或接管 agent loop，不提供模型路由、账号、认证、权限、会话、云任务、插件商店或中央跨仓治理服务。

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

## 5. 产品原则

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

治理、角色 lens、测试层级和能力组合随生命周期模式与风险升级。一个风险只使用最低充分证明；未产生净收益的流程、字段、skill 和指标应降级或退役。

## 6. 功能需求

### 6.1 Capability catalog

- `FR-CAT-001`：统一列出已知 skill、plugin、MCP descriptor 和 rule document，但保留各自类型字段，不做最低公分母扁平化。
- `FR-CAT-002`：每个外部能力记录 source URL/path、revision/version、checksum、license、trust tier、lifecycle status 和 discovered_at。
- `FR-CAT-003`：区分 runtime truth、reference shelf、official directory、host-installed inventory 和 discovery-only candidate。
- `FR-CAT-004`：同名/近似能力必须输出 canonical、duplicate、alternative 或 conflict 决策和依据，不直接按名称删除。
- `FR-CAT-005`：官方已存在等价插件/系统技能时默认推荐复用，只有明确缺口才进入自维护候选。

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
- `FR-SEL-003`：profile 是任务边界的有界预热包和 capability domain/index partition；没有可见匹配时，fallback discovery 先返回可理解的 domain `name + purpose`，宿主选择最多两个 domain 后再取候选，不静默切 profile，也不把 profile 当权限边界。
- `FR-SEL-004`：active/cold read-only skill 输出 `use_active_skill | load_skill`；operator skill 输出 `load_skill_with_approval`；读取必须受 declared root containment 保护。
- `FR-SEL-005`：已可用 read-only/external-read 能力可自动使用；write/destructive/open-world/unknown 或 needs_activation 必须输出 approval/activation plan。
- `FR-SEL-006`：建立 direct、indirect、negative、ambiguous、多阶段、architecture/stack、cross-domain、cross-kind、native/no-skill 和 side-effect 中英文自然语言 corpus；分别验证 resident trigger、domain/candidate discovery、宿主选择、policy、完整 SKILL.md 冷加载、零 semantic auto-selection 和零 negative/side-effect violation。
- `FR-SEL-007`：discovery/policy 全程只读，不切 profile、不创建任务、不重启宿主、不额外调用 provider，也不保存或推断 OAuth/token/session 状态。
- `FR-SEL-008`：脚本必须报告 `decision_owner=host_ai`、`semantic_routing_performed=false`、`task_type/domain=host_adjudicated` 和 `confidence=null`；不得伪造未由宿主提供的意图、风险置信度或工程阶段。
- `FR-SEL-009`：capability graph 只表达 `discover -> host_adjudication -> policy -> activate` 的责任顺序；产品交付阶段与多步执行计划继续由宿主 Agent/Plan/Goal 拥有。
- `FR-SEL-010`：caller-provided session snapshot 只用于 compatible reuse/load/release planning；profile 只输出 `apply=false` preheat recommendation。
- `FR-SEL-011`：Codex host snapshot 优先来自稳定只读 App Server RPC；包含 source/captured_at/freshness/availability/callable/access/auth evidence，陈旧事实 fail-closed，单来源失败可 truthful partial。
- `FR-SEL-012`：任何辅助发现层不得降低 host-native/profile baseline；若真实 replay/canary 不能减少误调用、漏调用、用户纠正或 TTFV，则语义路由功能必须继续降级或删除，仅保留 policy kernel。
- `FR-SEL-013`：skill 新增、删除或 metadata 变化后，profile reconciliation advisor 必须报告未路由技能、失效 profile/resident 引用、全部 profile metadata 预算和明显多 profile 重叠；诊断不得按名称关键词自动决定归属。
- `FR-SEL-014`：profile 语义归属只能由宿主 AI 以 `decision_owner=host_ai` 的显式 proposal 提供；确定性 planner 校验 `skills.json` freshness、canonical skill/profile 存在性、protected skill、add/remove 冲突、no-op、理由、动作上限、预算和 routing policy，并只输出 `apply_allowed=false`、`writes_performed=false` 的精确 change-set。
- `FR-SEL-015`：宿主 proposal 经 plan-only 校验后，可在常驻授权下进入非活动 profile 的 bounded canary；每次最多改变 5 个 skill、10 个 membership action，默认至少保留 256 字符 metadata headroom，禁止改变当前 active profile 或其 membership，并以 config hash、单 writer、原子 backup/write、receipt 和 drift-safe rollback 保护状态。
- `FR-SEL-016`：canary promotion 必须使用 fresh ephemeral host task replay，覆盖每个新增 skill 的 positive/negative prompt 和每个 changed profile 的至少四类代表场景；profile 未恢复、模型输出/期望失败或覆盖不足时自动回滚。模型 replay 只能标记 `host_evaluation_partial`，不得作为唯一门禁或晋级为 live acceptance。
- `FR-SEL-017`：cold discovery 必须使用 `hierarchical_domains_v1`：首次只暴露 domain `name + purpose`，宿主基于完整请求选择最多两个 domain，第二次才返回 `name + description + path + domains` 候选；不得要求宿主在看见 catalog 前猜不透明 profile 名。
- `FR-SEL-018`：`DomainHint` 支持数组或逗号分隔输入并最多保留两个有效值；`ProfileHint` 仅作为向后兼容别名。candidate 必须带 domain provenance，domain hint 不改变 `active_profile`。
- `FR-SEL-019`：代表性宿主验收必须分开记录 selection trigger 与 cold-load chain，并观测 router script、router/target `SKILL.md` 全文读取、deterministic policy、profile restore、duration 和 tokens；结果最高为 `host_evaluation_partial`，不得外推为普遍语义正确或业务效果。
- `FR-SEL-020`：canonical skill inventory 的 name/path/description 新增、删除或变化必须在投影 seam 生成 ignored `reconciliation_needed` signal，包含 before/after fingerprint、精确 delta、当前 config hash、profile/unrouted 摘要和 advisor command；profile-only/no-op sync 不生成新信号，信号不得直接写 profile。
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

## 7. 非功能需求

- `NFR-COMP-001`：现有 `skills.json`、lock、CLI aliases、generated `skills.ps1` 和 MCP/skill projection 行为保持兼容。
- `NFR-MNT-001`：新增业务逻辑进入明确 bounded context；不再向超大 command 文件无界追加。
- `NFR-MNT-002`：开发源码模块化，发行仍允许单文件 bundle。
- `NFR-PORT-001`：PowerShell 7 是首选开发/CI runtime；Windows PowerShell 5.1 保留有时限的兼容 smoke，不阻止新代码使用可适配的 PS7 能力。
- `NFR-SAF-001`：只读命令不能调用 provider、写宿主配置或改变 active profile。
- `NFR-SAF-002`：所有外部写入必须显式授权；高风险写入必须先有可执行回滚。
- `NFR-SAF-003`：profile reconciliation 的诊断和 proposal 校验必须 network-free、provider-free、zero-write，且不得修改 `active_profile`、安装/删除 skill 或写宿主配置；未来 apply 路径必须另行设计、审阅和授权。
- `NFR-SAF-004`：profile canary apply 只能消费显式宿主 proposal 与 apply token，runtime receipt/backup 留在 ignored `reports/`；不得直接调用 provider、修改 skill/plugin/MCP 安装、永久切换 active profile，或在 hash 漂移后覆盖用户修改。
- `NFR-SAF-005`：hierarchical discovery 只读、network-free、provider-free、zero-write；domain/purpose 和宿主语义选择不能覆盖 containment、freshness、availability、side-effect、approval 或 activation。
- `NFR-SAF-006`：reconciliation signal 属于 advisory handoff；写入失败只记录 warning，不得阻断已验证的 skill projection，也不得触发第二模型、active profile 热切换或无 token apply。
- `NFR-SEC-001`：不持久化 API key/OAuth/token；日志、plan 和 receipt 使用 redaction-first。
- `NFR-PERF-001`：inventory/doctor 使用有界扫描、缓存和明确超时；性能退化不能通过跳过完整性校验解决。
- `NFR-OBS-001`：关键阶段输出稳定的 machine-readable status 和 phase timing。
- `NFR-TST-001`：测试按风险选择最低充分层级；优先真实输入形状和关键失败模式，不要求每个改动机械同时新增 unit、fixture/golden、E2E 和 native probe。更高层不可用时按 N/A 记录恢复条件。
- `NFR-GOV-001`：编码前记录问题证据、官方/既有复用结论、最小方案、write set 与停止条件；full gate 和独立 evidence 仅在共享边界、closeout 或 release 需要时增加。
- `NFR-GOV-002`：P5 后默认 maintenance hold；没有跨域真实失败、已消费 P5 输出、现有 seam 无法修复和用户明确授权，不创建 P6 manifest 或 schema major。
- `NFR-TRU-001`：任何“完成/生效/验收”声明必须绑定 verification level 和 evidence path。
- `NFR-LDL-001`：maintenance design/pilot 不增加 schema major、daemon、数据库、长期任务引擎、固定角色 runtime 或任何宿主写入行为。
- `NFR-LDL-002`：LLM 判断、语义评分和自我总结只能作为建议或候选信号，不得成为唯一硬门禁、权限判定或 skill promotion 依据。
- `NFR-LDL-003`：主链优先于完备架构，测试采用最低充分层级；`designed | planning_contract | implemented | repo_verified | host_loaded | live_accepted` 不得越级。

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
13. skill inventory 变化后可获得确定性的 profile drift 诊断；宿主 proposal stale、引用未知对象、触碰 protected skill、产生 no-op/冲突或超预算时 fail-closed，且诊断全过程不改变配置和 active profile。
14. 经授权的 profile 优化只对非活动 profile 执行有界 canary；fresh-task replay 必须证明正负代表场景并恢复原 active profile，失败时按 receipt 自动回滚，整个链路保持 host semantics 与 deterministic state policy 分离。

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
| `MET-014` | profile reconciliation proposal 的 stale/no-op/budget/policy 拒绝与 reviewed apply 转化 | observe-only；当前只实现 plan，不建立自动 apply 指标门禁 |
| `MET-015` | profile canary replay 通过、回滚、用户纠正与 active profile 恢复 | observe-only；deterministic contract 与 host replay 分层，未建立跨任务净收益前不设语义硬阈值 |
| `MET-016` | cold discovery 的 uncached input、cached ratio、tool rounds 与 latency | observe-only；按同 prompt A/B；任何减少回合但增加 uncached/延迟或降低完整读取可靠性的方案必须回退 |

## 10. 发布和兼容边界

- Phase 0 不增加用户可见新领域能力，只建立 schema、模块 seam、operation contract 和规划门禁。
- Phase 1 只增加 read-only inventory/rules advisor，不新增规则写入。
- Phase 2 才引入显式 apply；必须保留现有命令兼容和 feature flag/observe 窗口。
- Phase 3 才评估 personal plugin lint/export，不创建公共 marketplace。
- Phase 4 只增加统一 capability selection 和 activation planning；宿主仍拥有 MCP/plugin/tool runtime、认证、权限、approval 和 session。
- Phase 5 增加 task understanding、capability DAG、session reuse planning 和只读 host snapshot；仍不接管执行、安装、认证、审批、profile 或 session mutation。
- P5 maintenance correction 以真实用户反馈和重复自然语言回放退役 lexical task understanding/ranking；该修正不改写 P5 历史任务状态，不构成 P6，也不宣称 host-native 路由已经 live accepted。
- P5-local profile reconciliation advisor 只诊断 profile drift 并校验宿主语义 proposal；它不自动优化 `skills.json`、不热切换 profile、不实现 apply，也不构成 P6 或 live acceptance。
- P5-local profile optimization canary 在 advisor 之后增加显式 token、非活动 profile 的 bounded apply、runtime receipt、fresh-task replay 和失败回滚；它不自行调用宿主 AI、不永久切换 active profile，也不构成 P6 或 live acceptance。
- P5-local follow-up 已把 canonical inventory delta 接到 projection 主链的 advisory signal；宿主在同一任务边界可据此启动 reconciliation，但 profile proposal/apply 仍遵守 ADR-SMV-018/019，不等于静默写配置。
- P5 后的 `maintenance_design` 已建立 Lean Delivery advisory 规划契约，并由独立 registry 启动 M1 `collecting (0/10)`；它不是新 Phase，不改变 P5/P6 状态，也不证明 pilot 已执行、完成或产生业务效果。
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
- [OpenAI Memories](https://learn.chatgpt.com/docs/customization/memories)：local memories 是可选回忆层，稳定规则仍进入 `AGENTS.md`/仓库文档；本项目不复制记忆库。
- [OpenAI Codex App Server](https://learn.chatgpt.com/docs/app-server) 与 [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk)：深度客户端集成和编程式线程控制已有原生入口；只有未来独立产品需求与 P6 admission 同时成立时才评估集成，不在本仓复制。
- [OpenAI Scheduled tasks](https://learn.chatgpt.com/docs/automations)：稳定重复流程可由宿主 scheduled tasks + skill 承接；先人工跑通并验证，再自动化。本仓不建 daemon/scheduler。
- [MCP specification](https://modelcontextprotocol.io/specification/latest) 与 [MCP Registry](https://registry.modelcontextprotocol.io/)：采用 schema、versioning、validation 和来源/所有权边界。

### 社区采纳或适配

- [wshobson/agents](https://github.com/wshobson/agents)：采纳细粒度 plugin、单一源到宿主原生产物、结构校验；拒绝把大规模多代理/模型分层直接移入本项目。
- [obra/superpowers](https://github.com/obra/superpowers)：采纳 evidence-before-claims、可组合 workflow 和行为测试；拒绝默认强制全部流程和 always-on bootstrap。
- [mattpocock/skills](https://github.com/mattpocock/skills)：采纳小、可组合、可编辑副本与订阅式 plugin 的区别；拒绝由 workflow 接管完整工程过程。
- [github/spec-kit](https://github.com/github/spec-kit)：适配从 constitution/spec/plan/tasks 到实现的可追踪结构；拒绝强制 TDD、固定文件数和所有任务人工审批等与本仓风险分级不符的流程。
- [OpenHands](https://github.com/All-Hands-AI/OpenHands) 与 [LangGraph](https://github.com/langchain-ai/langgraph)：仅作为 agent runtime、状态图和可恢复执行的对照；当前 defer，不把 runtime/control plane 移入 skills-manager。
- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)：仅在外置个人 Agent/长期任务需要独立验证后评估组合；不得作为本仓的默认执行内核或真值源。
- [Obsidian](https://obsidian.md/)：可作为用户拥有的产品知识库和长期笔记界面；本仓只消费明确导出的文档/链接，不把 vault、插件或双链索引变为必需 runtime。
- `D:\CODE-other\governed-ai-coding-runtime`：采纳规则最小化、`common/platform_delta/project_action` 层级职责、共同语义与平台差异分离、native probe 和 wrapper 启发；把固定结构/体量预算适配为 profile；拒绝恢复已退役的中央 registry/sync/audit runtime。精确 revision、逐项 disposition 和证据见 [规则治理参考采纳矩阵](rule-governance-adoption-matrix.md)。

## 12. 决策与待确认

本 PRD 已采用以下默认决策，不阻塞 Phase 0：

- `DEC-PROD-001`：产品定位为 local capability curator + rule advisor。
- `DEC-PROD-002`：规则永久默认 advisory-first；显式 apply 是唯一写入入口。
- `DEC-PROD-003`：PowerShell 模块化单体继续作为主技术方向。
- `DEC-PROD-004`：不立即改仓库名；只有规则/plugin 两条新主路径经过真实使用验收后再评估品牌更名。
- `DEC-PROD-005`：未来 Phase 在进入实施前各自生成详细 task manifest，避免提前维护大量猜测任务。
- `DEC-PROD-006`：Rules Advisor 使用责任覆盖模型，不建立通用规则 AST、重型 policy engine 或强制统一模板。
- `DEC-PROD-007`：Lean AI Software Delivery 是 P5 后的 advisory maintenance track；先通过 10 个真实任务 observe-only pilot 证明净收益，再决定保留、修订、退役或是否形成新的 P6 admission 输入。
- `DEC-PROD-008`：Goal、subagents、scheduled tasks、local memories、App Server/SDK 属于宿主 native baseline 和本项目退役触发器；只有本仓独有的 capability/rule discovery、advice、bounded transaction 与 verification seam 可在证据支持下保留。

以下选择有意延迟到有真实代码/宿主证据的任务，不允许 AI 在更早任务中猜定：

- `VAL-P0-003`：schema dialect、validator 实现和 observe/enforce 切换，以当前 `skills.json` 变体和本机可用 runtime 为依据，不为验证器额外引入常驻服务。
- `VAL-P0-005`：首个 Infrastructure seam 必须由至少两个真实 caller 和 characterization tests 选出，不按目标目录图预建空模块。
- `VAL-P0-006`：MCP plan 的最终 CLI spelling 先读取当前 parser/alias tests；行为合同先于命令拼写。
- `VAL-P0-007`：host matrix 的 affirmative capability 必须由当前官方文档、help/schema 或 native probe 支持；未知值保持 unknown/platform_na。
- `VAL-P1-MET`：semantic finding precision 和性能阈值要先用代表仓建立 baseline，再决定 gate 阈值。
