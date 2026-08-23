# 冷技能路由路线图

**产品契约**: 2.0  
**状态语义**: 稳定设计合同；不记录运行时状态  
**适用范围**: 本仓受控 cold catalog、native-agent bridge 与 Codex host-specific 验收  
**相关文档**: [PRD](skills-manager-vnext-prd.md)、[Architecture](skills-manager-vnext-architecture.md)、[实施计划](cold-skill-routing-implementation-plan.md)、[验收 Runbook](../runbooks/cold-skill-routing-acceptance.md)

## 1. 目标与不变量

目标不是把所有本地技能预热到宿主提示词，也不是新增一个以关键词代替宿主理解的语义路由器。目标是让宿主在可见能力不足、且专门工作流有可量化净收益时，能够安全地发现、校验并按契约使用完整冷目录中的一个精确技能闭包。

稳定主链如下：

    宿主判断可见技能是否足够
    -> 判断专门工作流是否有净收益且误调用成本可接受
    -> 一次有界、只读、domain-scoped cold discovery
    -> 宿主在少量候选中作语义选择
    -> capability-router 精确校验入口、闭包、hash、可用性、副作用与 execution_contract
    -> 独立 admission
    -> 按 execution_contract 分流到 parent、native child 或 fail-closed

下列不变量贯穿全部阶段：

- 宿主 AI 是唯一语义选择者。capability-router 的输出必须保持 `decision_owner=host_ai` 与 `semantic_routing_performed=false`；它不排序意图、不选择候选、不执行候选。
- 不存在“每条请求先 router 一次”的 middleware。引用技能名、讨论技能机制、普通解释、可见技能直达都不是 cold discovery 的充分理由。
- 可见能力足够时直达可见能力；只有“能力不足 + 专门工作流确有净收益”才有一次 discovery 预算。完整原始请求随 discovery 传递，domain hint 最多两个。
- discovery、候选校验、真实读取 SKILL.md、child 生命周期、外部结果接受是不同事件。任何低层证据都不得升格为更高层。
- Router discovery 永远只读，且 `execution_authorization.status=not_granted`。校验许可读取闭包的入口文本，不等于执行许可。
- `execution_contract` 是分流的权威：`one_shot`、`parent_user_input`、`multi_turn_user_decision`、缺失/冲突/unknown/external 必须有不同结果；不得以“给结论”降格多轮交互。
- `controlled_write` 必须另有用户实施请求、exact write set、最低验证和 stop；`external_read`、`unknown`、冲突契约默认拒绝。
- 任何子代理 template 仅可静态固定自己的 model 与 reasoning effort；不得通过 bridge 管理 provider、endpoint、auth、会话、共享 profile 或动态 model fallback。

## 2. 当前基线与已收口问题

CSR-R0 的已知输入是提交 `6e5e390d719e34f76ca2631a109507c06160e405`。该提交修复了跨宿主根 junction catalog 的一个真实断点：当 `SKILLS_MANAGER_CAPABILITY_CATALOG` 或 `-CatalogPath` 指向 router junction 下的 `catalog.json`、而执行 router 不在同一 junction 根下时，旧逻辑把 sibling skill junction 当作越界 reparse point，令整本 catalog 失效。

修复将“catalog 直接父目录是单目标 reparse point 且物理对照文件存在、物理链无再解析点”的窄形态规范化到 physical catalog；其他形态仍 fail-closed。它没有放宽 containment、fingerprint、entrypoint hash 或闭包校验。该基线的 focused 证据是：

| 证据 | 所证明的边界 | 不证明什么 |
| --- | --- | --- |
| `tests/Unit/CapabilityRouterCrossRepo.Tests.ps1` 8/8 | 跨根 router-junction、environment catalog 与缺失物理对照的 deterministic 行为 | 宿主自然语言理解、SKILL.md 实际加载、native child |
| `tests/Unit/CapabilityRouter.Tests.ps1` 18/18 | router 的候选、闭包、契约与 fail-closed 行为 | host 选择正确或业务结果被接受 |
| catalog/current 指纹与 hash | 目录投影及可校验性 | 当前会话已加载或调用某技能 |

历史上 `grill-with-docs` 的精确校验已得到 `candidate_load_validated`，其闭包为 `grill-with-docs + domain-modeling + grilling`，有效契约为：

    mode=multi_turn_user_decision
    native_agent=design-griller
    conversation_owner=parent
    stop_condition=one_question_then_wait

这证明 deterministic router 可以返回正确闭包与分流合同；它不能证明某个 ZCode 父任务或 Codex host 已读取闭包内 SKILL.md，也不能证明 native child 已启动。

## 3. 分阶段路线图

阶段按依赖顺序推进。完成一个阶段只可声明其表中真值边界，不能跳过未完成的宿主验收。

| 阶段 | 名称 | 主要问题 | 进入条件 | 退出条件 | 允许声明的最高边界 |
| --- | --- | --- | --- | --- | --- |
| CSR-R0 | Deterministic baseline | 跨根 cold catalog 是否仍可 fail-closed 地发现与校验 | 当前 router 基线存在 | CrossRepo 与 Router focused tests 通过，Junction 正/负例保留 | `repo_verified` |
| CSR-R1 | Bridge model determinism | bridge 是否意外继承不可用的全局 subagent 默认模型 | R0 通过 | 两个 source template 固定 Terra/high；模板测试阻止 provider/auth 字段混入 | `repo_verified` |
| CSR-R2 | Receipt 与场景契约 | 是否能区分预期、观测与断言，避免“代行=child 成功” | R1 通过 | tracked matrix、receipt v2 verifier、正负 fixtures 与 runbook 同步 | `repo_verified` |
| CSR-R3 | Filesystem projection | 受管 template 是否以可回滚方式投影到 Codex agents 根 | R2 已提交且工作树洁净；当前授权允许 host projection | source/target SHA-256、backup paths、source revision 写入 receipt；未改非受管文件 | `filesystem_projected` |
| CSR-R4 | Fresh Codex native acceptance | Codex 是否真实启动了正确 child 并遵守多轮/只读契约 | R3 收据可复查；fresh Codex 会话可用 | design-griller、runner、visible direct 对照均有可观察事件 | `host_specific_live_accepted` |
| CSR-R5 | 语义观测与工件专项 | 隐式表达是否造成漏发/误发；产物是否合格 | R4 已完成 | 三正三负 fresh-host 样本完成；文档/图片/Office 工件另有渲染或内容质量验收 | `observed`，工件按各自 host-specific 边界 |

### CSR-R0：确定性路由基线

该阶段只维护 router 的确定性属性，不判断自然语言是否“应该触发”：

- 正例：仓内 router、`.agents` junction router、其他根 router 都能使用同一合法 physical catalog。
- 正例：`-CatalogPath`、`SKILLS_MANAGER_CAPABILITY_CATALOG` 与 auto-discovery 的受支持形态输出一致的校验结果。
- 负例：物理对照不存在、entrypoint hash 漂移、闭包越界、再解析链非允许形态、catalog 过期或 domain 超限时零执行、零候选、明确 finding。
- 禁止为规避 junction 测试取消 reparse 检查，或把“路径存在”视为可信。

### CSR-R1：原生 bridge 的静态模型确定性

两份 source template 的配置只能新增以下两个静态字段：

    model = "gpt-5.6-terra"
    model_reasoning_effort = "high"

目标是消除 bridge 无意继承 `[agents].default_subagent_model` 的不确定性，而非替换用户的全局默认或修复 provider/auth。依据官方 OpenAI Subagents 文档，custom-agent 文件可设置这两个字段且在文件中显式设置时优先；该规则只影响由对应 custom agent 创建的 child。

`design-griller` 是高判断密度的一题一轮审问角色；`cold-capability-runner` 需要严守闭包、admission 与副作用约束。两者都固定为 Terra/high 是本项目的静态部署决策。它并不承诺 Terra 在任一 provider 上始终可用，故新会话 child 事件仍是 CSR-R4 的独立门槛。

历史 Sol child 成功和 503 均仅用作故障诊断基线：前者证实 runner 过去能 fail-closed 并在完整 admission 下运行，后者说明无 template 钉选时确会解析到 Sol。它们早于本阶段的变更，绝不可充当 Terra/high 的接受证据。

### CSR-R2：可机器校验的语义观测合同

阶段产物由一份 tracked 场景矩阵、一套 receipt v2 schema/verifier、fixture 与 runbook 组成。

1. 场景矩阵保存用户提供的 29 组原始请求类型及 provenance；矩阵的业务 oracle 是 route class、允许集合、禁止事件与契约分流，而不是让隐式 prompt 唯一命中某个技能名。
2. receipt 把 `expected`、`observed` 与 `assertion` 分开。`observed=not_observable` 永远不能被自动转成 pass。
3. verifier 对结构、状态组合和禁止的过度声明 fail-closed；它不负责判断宿主的语义判断“正确”，而是防止证据自相矛盾。
4. legacy receipt 原件只读保留。迁移输出要绑定 legacy SHA-256，并将无法回放的 native child / SKILL.md loading 标为 `not_observable`。

该阶段不要为 29 个 prompt 建关键词分类器或“golden 必选技能名”系统。那会把宿主语义选择复制到 router，既无法代表真实语言多义性，也会把测试算法误当用户行为。

### CSR-R3：受控投影

投影是宿主外部写入，属于显式 workflow，绝非文档/单元测试自动完成条件。仅当本切片已提交、worktree 状态符合 host promotion contract、并获得当前授权时才可执行 `skills.ps1 构建生效`。

验收条件：

- 生成 bridge 与 source template 的 SHA-256 一致。
- `reports/native-agent-bridge/current.json` 能列出 source revision、definition 名、source/target hash、changed names、backup root 与 precise backup paths。
- 两个目标是 `~/.codex/agents/design-griller.toml`、`~/.codex/agents/cold-capability-runner.toml`；无 provider/auth/endpoint/secret 字段。
- 回滚只使用本次 receipt 的 backup paths，不触碰用户其他 custom agents。

成功只表示文件系统已投影。即使 Codex config 可解析、文件可枚举或工具显示 agent 名，也仍不表示新会话读取了这些文件。

### CSR-R4：Codex 新会话原生验收

该阶段只能在支持 Codex native subagent 的 fresh session 中执行。每条已接受的断言必须含 child id 或等价宿主事件、解析到的 model/effort、生命周期状态与原始证据引用。

最小代表性链路：

1. 明确 `$grill-with-docs`：cold discovery/precise validation 后，实际 `design-griller` 只给一个首问，并停在 `awaiting_user_answer`。
2. 同一个 parent 向用户取得真实回答后，将该回答交回同一 child；不得创建替代 child 或跳成单轮摘要。
3. 明确 `domain-modeling`：仅在有效 `one_shot` + read-only admission 下启动 `cold-capability-runner`；确认零写入。
4. 可见 `$grill-me`：作为 direct visible 对照，不得产生 router 事件。

ZCode、模拟 parent、catalog reader 或测试 harness 无 native subagent 机制时，应报告 `native_child=not_supported` 或 `not_observable`，并把结果限制为 parent-mediated observability；它们是有价值的分流测试，但不能通过 CSR-R4。

### CSR-R5：隐式语言观测与专项工件验收

这是观察阶段，不是把一次代表性成功外推到完整目录的阶段。

- 执行三个不同措辞的隐式正例。允许 host 选择不同但兼容的候选或拒绝启动，只要 receipt 记录候选集合、一次 discovery 上限、实际 contract、未授权副作用和失败原因。若实际目标要求某一工作流，必须由 matrix 的契约而非名称硬编码说明。
- 执行三个明显无技能需求或可见能力直达的负例。它们不得触发 cold discovery、native child 或 side effect。
- 按附件 #12–#15、#19–#20 的类型制作 Word/PDF/PPTX/XLSX/image fixture 时，路由结果与工件质量分开报告。前者通过不代表图表、公式、阅读顺序或视觉布局正确；后者按 documents/pdf/presentations/spreadsheets/image 的专项 render/inspection workflow 验收。
- #16–#18 没有当前 workbook/sheet/cell/tab/URL/目标浏览器状态时为 `platform_na`，不得伪造 live pass。

## 4. 依赖、决策与风险

| 决策或风险 | 所在阶段 | 约束/处理 | 反模式 |
| --- | --- | --- | --- |
| 全目录 metadata 预算 | R0/R5 | profile 是预热预算；portable catalog 是完整冷索引 | 全量预热所有冷技能 |
| 隐式意图有歧义 | R5 | 记录 host 选择与禁止行为，不制造关键词判定器 | 要求每个自然句唯一技能名 |
| discovery 被误用为执行 | R0-R4 | validation 与 admission 分离，router 永远 not_granted | 一次 router 成功即执行 |
| 多轮被单轮摘要吞掉 | R2/R4 | contract + child lifecycle 验收 | runner 总结多轮决策 |
| 全局子代理默认值漂移 | R1/R3 | source template 静态钉选，投影 hash 可追溯 | 修改用户 config 或动态 fallback |
| provider/auth 间歇故障 | R4 | 记录 host-specific 失败；不把模型枚举当健康检查 | 重试后把历史 child 当当前验收 |
| junction/目录拓扑 | R0 | 窄规范化，其他形态 fail-closed | 广泛取消 reparse 防护 |
| 29 场景范围膨胀 | R2/R5 | routing contract 与 artifact quality 分跑 | 把所有 Office 产物质量塞进 P0 |
| “无第二语义路由器”为带阈值原则（2026-08-24 决策） | R0-R5 | 域数量 > 30、单域常驻候选 > 16、目录技能数 > 150，任一触及即重开“cold discovery 是否加检索前置”的决策；阈值仅触发重审，不自动改架构；三个数值为有依据的估计而非实测校准；行为触发器（隐式命中率/契约塌缩计数）待 CSR-R5 样本机制存在后再钉 | 无条件死扛；越限即自动切换架构；把未校准阈值当自动开关 |
| 冷目录范围边界（2026-08-24 决策） | R0/R5 | “全冷目录可调度”指目录内全类型；imagegen 与 live-control 类不收编，判据是“受管且契约已声明 vs 宿主侧未管理且副作用 external”，不是“工件 vs 非工件”（docx/pdf/xlsx 在册而 imagegen 不在册即由此界产生）；单一类型出现真实高频复用证据时可单独决策纳入 | 按“是否工件”划界；无真实调用方即扩治理面 |
| 架构结论声明档位（2026-08-24 决策） | 全阶段 | 分腿声明：deterministic 腿（发现/闭包/hash/契约/verifier）可声明“已实跑验证”，声明时必须附口径与证据位置；语义腿与 native 腿在 CSR-R4/R5 完成前只能声明“未验收/假设” | 总括式“最优方案已验证”；把已验证腿反向压成假设 |
| 阈值越限看护 | R2 | 目录阈值当前仅为文档承诺；应下沉为 quality gate 的 catalog 阈值检查（域数、最大域候选数、技能数，超限即 fail），本决策记录本身不实现该机制 | 静默越限后无人重审；为记录阈值先建遥测 |

## 5. 明确不做

- 不重新引入 profile 切换、全量 prewarm、router 意图排序、每请求预检或长期行为遥测库；第二语义分类器仅在 §4 记录的目录阈值被触及并重开决策、且新决策明示引入时方可进入。
- 不为“可能的 portable 独立分发”新建第三份 catalog/skill 副本；除非出现真实调用方和独立一致性需求。
- 不声称 78 个或全部冷技能已经 live accepted；每次只报告有 event evidence 的代表性任务。
- 不把 ZCode 代行、AI 口头说明、router JSON、模板文件存在、config parse、HTTP 200、或历史 session 升格为 Codex fresh-session live acceptance。
- 不修改 `~/.codex/config.toml`、Cockpit provider/auth、插件缓存、全局 default_subagent_model，也不在本路线图中授权重启或 kill 任何宿主进程。

## 6. 路线图完成定义

路线图不是一个单一 Done 状态。对每个任务和最终汇总必须分别报告：

| 层级 | 最低证据 | 不可替代的下一层 |
| --- | --- | --- |
| `repo_verified` | source diff、build、focused test/verifier | host projection receipt |
| `filesystem_projected` | source/target hash、promotion receipt、backup paths | fresh host/child event |
| `host_loaded` | 新宿主会话的可观察加载事实 | 真实代表性任务结果 |
| `candidate_load_validated` | router exact closure/hash/contract receipt | SKILL.md load 与 native execution event |
| `host_specific_live_accepted` | 当前宿主的 child id/lifecycle/行为证据 | 其他宿主或其他技能的独立验收 |
| `observed` | 有界实验的原始样本及结果分类 | 统计推广或产品承诺（需另行决策） |

实施顺序、精确 write set、test cases、rollback 及每项 stop condition 以 [冷技能路由实施计划](cold-skill-routing-implementation-plan.md) 为唯一细化来源。
