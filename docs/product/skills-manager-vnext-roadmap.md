# skills-manager vNext 路线图

**program_id**: `skills-manager-vnext`
**roadmap_version**: 1
**最后更新**: 2026-08-03

## 1. 状态总览

| Phase / track | 名称 | 状态 | 当前真值 |
| --- | --- | --- | --- |
| `P0` | Foundation and contracts | `complete` | 9/9 tasks repo_verified；host_loaded/live_accepted 未执行 |
| `P1` | Read-only inventory and rule advisor | `complete` | 9/9 tasks repo_verified；host_loaded/live_accepted 未执行 |
| `P2` | Transactional explicit apply | `complete` | 7/7 repo_verified；follow-through 增加 reviewed global/project multi-target saga，真实 apply 仍需独立 review/token |
| `P3` | Plugin-aware distribution and evaluation | `complete` | 7/7 tasks repo_verified；fixture-first，host/live 未执行 |
| `P4` | Unified capability selection and activation planning | `complete` | 6/6 tasks `repo_verified`；16-profile fresh prompt probe 已通过，host runtime activation/live acceptance 未执行 |
| `P5` | Adaptive Capability Fabric | `complete` | 5/5 `repo_verified`；live read-only App Server snapshot 与 full gate 已通过，business live acceptance 未执行 |
| `maintenance_design` | Lean AI Software Delivery | `M0 repo_verified` | 规划包 4/4 tasks repo_verified；M1-M3 conditional，10-task pilot 未执行 |

状态只可在相应 exit gate 有当前证据后更新。Phase 文档完成不等于 Phase 实现完成。

## 2. 全局依赖

```text
P0 contracts and seams
  -> P1 read-only facts and diagnostics
     -> P2 safe write protocol
        -> P3 packaging/evaluation

P4 started from repeated real routing failures and unified selection. P5 starts from a current meta-task false positive and adds task understanding, composition and read-only host truth without taking over runtime execution.
```

禁止绕过：

- P0 未完成前，不增加 rules apply 或 plugin installer。
- P1 未取得真实只读 findings 精度证据前，不进入规则写入。
- P2 未完成 freshness/rollback/live truth 分层前，不扩大宿主写入面。
- P3 不以“技术上可打包”为发布理由，必须有重复使用和明确分发对象。

## 3. P0 Foundation and contracts

### 3.1 目标

在不改变现有 CLI 产品行为的前提下，建立可扩展但不沉重的 schema、模块 seam、operation plan/receipt 和 AI-executable planning contract。

### 3.2 范围

- 产品文档和 task manifest/verifier。
- reference shelf 的官方 plugin source 纠偏。
- `skills.json` schema/version/observe validation。
- Domain/Application/Adapter 最小目录和首个真实迁移 seam。
- versioned OperationPlan/Receipt validator。
- MCP sync 的 machine-readable plan 对等路径。
- host adapter capability matrix 和 truth-state contract。

### 3.3 非目标

- 不实现 rules advisor 用户功能。
- 不写任何目标仓规则。
- 不安装/卸载 plugin。
- 不建立数据库、服务、GUI 或跨仓 registry。
- 不一次性重写旧大文件。

### 3.4 Entry gate

- 当前 `main`/工作树事实已读取。
- build/test/doctor/full gate 存在可运行入口。
- 产品边界已被 PRD/架构记录。
- Phase 0 task manifest 通过 planning verifier。

### 3.5 Exit gate

- Phase 0 task manifest 中全部非 deferred 任务为 done。
- `skills.json` schema validator 对当前配置通过，未知字段/错误 fixture fail-closed；enforcement 状态有明确 observe/enforce 字段。
- 至少一个旧 command seam 迁入新模块且 golden/compat tests 证明行为未变。
- OperationPlan/Receipt schema、validator、freshness 和 redaction tests 通过。
- MCP sync 能生成不写文件的结构化 plan，actions 与真实 apply 的受管目标集合一致。
- host adapter matrix 能区分 repo_verified、host_loaded、live_accepted。
- fixed gate 和 full local quality gate 通过，并新增 change evidence。

### 3.6 Task truth

详细任务只以 `tasks/skills-manager-vnext-phase0.tasks.json` 为真源。`tasks/plan.md` 定义顺序，`tasks/todo.md` 只显示状态。

### 3.7 Closeout evidence

- 2026-08-02：全部 9 个 Phase 0 task 为 done，planning verifier 0 findings，waiver 0。
- 定向套件 58/58；最终 full local quality gate Unit 557/557、E2E 13/13。
- config、host matrix 和 MCP plan 的只读探针保持输入哈希不变；MCP plan 未调用 native mutation，也未修改 active profile。
- 本状态仅为 `repo_verified`。未执行 host native projection、fresh-session load 或 live workflow acceptance，因此不得外推为宿主已加载或业务已验收。

## 4. P1 Read-only inventory and rule advisor

### 4.1 目标

提供统一但不扁平化的 capability inventory，以及 Codex-first、可扩展到其他宿主的规则扫描和诊断；全阶段保持只读。

### 4.2 Feature slices

#### `P1-S1 Capability inventory`

- 聚合 runtime truth、reference shelf、host inventory 和 official directory candidates。
- 输出 skill/plugin/MCP 分类型 descriptor 和 source disposition。
- 识别 official equivalent、duplicate、alternative、conflict 和 lifecycle。
- 不 fetch/clone/install，不改变 active profile。

#### `P1-S2 Rule discovery`

- Codex global/repo/nested/override discovery。
- 使用官方加载语义生成 candidate chain；无法通过 native probe 证明时标记 `inferred`。
- 只读取授权 root 和明确 host user path。
- 分离 `common`、`platform_delta`、`project_action`、`deterministic_enforcement` 和 `task_local`，不要求目标仓采用同一 heading。

#### `P1-S3 Deterministic diagnostics`

- filename、BOM、wrapper、byte budget、required section、path/command existence、duplicate exact blocks。
- deterministic findings 可作为 verifier blocker。
- 体量/heading/wrapper 按 host/profile 配置；仅在当前 profile 与官方加载事实都适用时阻断。

#### `P1-S4 Semantic advisor`

- 重复/冲突、surface 错位、过长说明、把 prose 当 enforcement、global/repo 泄漏。
- 输出 `Global Rule -> Repo Action` 的 `covered/gap/conflict/duplicated/not_applicable` 覆盖和 `adopt/adapt/reject/defer` disposition。
- semantic findings 默认 recommendation，提供 evidence/confidence，不直接阻断。

#### `P1-S5 Repo truth integration`

- 复用 TargetAudit 的 build/test/CI/script 发现。
- findings 引用 source path/line/revision，禁止 outer AI recommendation 自我证明。

### 4.3 Entry gate

- P0 exit gate 全部满足。
- RuleDocument/CapabilityDescriptor schema 不再是猜测接口，至少有当前 Codex/skills/MCP fixture。
- read-only command contract 有 provider-call-zero 和 write-zero 测试。

### 4.4 Exit gate

- 三个代表仓完成只读 rules scan：简单仓、嵌套规则仓、存在冲突/漂移仓。
- 至少一个 Codex/Claude 共用项目契约样本能区分共同语义、平台差异和项目动作，且不依赖中央 target registry。
- findings 有 precision 抽样记录；误报不会自动写入或阻断产品门禁。
- capability inventory 能识别官方 plugin 与 deprecated source。
- current session 未发生 host config/profile/target repo 写入。
- repo full gate 与 fresh Codex rule-load probe 状态分别记录；repo-only P1 可在 probe 为 `not_run` 时收口，但不得宣称 `host_loaded`。

### 4.5 Closeout evidence

- 2026-08-02：九个 P1 task 全部完成；三个固定 fixture 和三个授权只读仓完成 precision/performance/hash 验收。
- `capability-inventory` 与 `rule-audit` 提供单行 JSON envelope；默认 zero-write，显式 `--out` 只写一个报告且不能覆盖规则文件。
- deterministic fixture 的已声明正例 4/4 命中、simple fixture 0 false positive；semantic advisor 只在显式 responsibility fixture 取证，尚不外推为通用自然语言精度。
- 2026-08-02 maintenance repair：inventory 已按真实数组配置识别 vendors/imports/mappings/MCP；Rule Advisor CLI 已接通显式责任映射和 repo reference checks，并以真实配置/CLI 语义测试防止 fixture-only 假绿。
- 当前最高状态仅 `repo_verified`；fresh-session load、`host_loaded`、`live_accepted` 均为 `not_run`。

## 5. P2 Transactional explicit apply

### 5.1 目标

在 P1 findings 可靠后，为 MCP、skill projection、单目标规则 patch 和 reviewed rule estate change-set 提供一致 plan/freshness/apply/receipt/rollback。

### 5.2 Feature slices

- `P2-S1`：OperationPlan enforce 和 stale/freshness gate。
- `P2-S2`：atomic write、backup 和精确 rollback。
- `P2-S3`：rules plan 输出 diff，不自动 apply。
- `P2-S4`：rules apply 先支持单 repo 精确路径；follow-through 扩展为 global/project multi-target 的全量预检、逐目标写入与独立 receipt。
- `P2-S5`：MCP sync 迁移到相同 receipt 语义。
- `P2-S6`：native probe adapter 和 verification level projection。
- `P2-S7`：中断/失败/并发漂移恢复测试。

### 5.3 Entry gate

- P1 exit gate 完成且 findings precision 可接受。
- 至少两个真实写入领域复用 OperationPlan envelope，证明抽象不是单点包装。
- secret redaction、stale plan 和 rollback fixtures 通过。

### 5.4 Exit gate

- 任一 write command 在没有 valid plan/explicit apply 时 fail-closed。
- before hash 漂移时零写入。
- fault injection 后只回滚本 operation 的已应用 action。
- receipt 明确四级 verification，不自动晋级。
- fixture target 完成 apply/rollback/fault matrix；真实 Codex/项目规则路径只做 hash guard，不把 fixture 写成 host/live acceptance。
- 2026-08-02 follow-through：真实 Git 仓完成 `AGENTS.md` update 与 `CLAUDE.md` create；精确 token、hash、atomic write、rollback 和 37 项聚焦测试通过，宿主加载仍为 `not_run`。
- 2026-08-02 rule-estate follow-through：fixture 已覆盖 AI self-review 拒绝、global/project exact allowlist、target-set drift、unrelated-dirty observation、target-file stale hash、lock、fail-fast、resume 与 per-target rollback；执行模型不是跨仓 all-or-rollback。
- 2026-08-02 authorized rollout：动态发现 9 个直属 Git 仓并排除 `external`、`文档`；2 个全局规则与 9 个项目规则 receipt 为 11/11 applied，审计为 99/99 covered、0 finding，Codex fresh-process load 为 9/9。Claude 为 `platform_na`，`live_accepted=not_run`，P4 继续 `not_started/deferred`。

## 6. P3 Plugin-aware distribution and evaluation

### 6.1 目标

利用官方 plugin directory 和开放打包模型，减少重复技能安装，并为确有分发需求的自维护 workflow 提供 lint/export。

### 6.2 Feature slices

- `P3-S1`：official/personal/workspace plugin inventory adapter。
- `P3-S2`：skill-only、MCP-only、skill+MCP、optional UI shape advisor。
- `P3-S3`：personal plugin manifest lint 和 source/version/license checks。
- `P3-S4`：同一源到宿主原生产物的 bounded exporters，仅支持有测试的宿主。
- `P3-S5`：static + behavior fixture + optional model eval 分层；LLM score 不作为唯一 gate。

### 6.3 Entry gate

- 至少两个自维护 workflow 有重复分发需求，且官方目录不存在等价项。
- 当前官方 plugin manifest/schema/CLI 已通过 docs/help/fixture 固定。
- P2 receipt 能覆盖 native plugin install intent/result；OAuth 仍由宿主所有。

### 6.3.1 Current entry evidence (2026-08-02)

- 四个自维护 domain workflow 已在多个 profile 重复路由并投影到标准用户技能根；teaching workflow 是明确 personal/workspace 分发对象。
- 当前 official/curated inventory 与 pinned `openai/plugins@11c74d6b...` 未发现等价的初中课堂课件 + 物理动画 bundle；Presentations/Remotion 作为互补执行器保留 official-first。
- current Codex manual 与 `codex-cli 0.145.0` help 已固定 manifest、local/repo/workspace 分层和只读 list JSON shape。
- P2 contract/receipt vocabulary 可记录 plugin intent/result，但本任务未授权 install；OAuth/runtime 继续由宿主所有。
- 因此 P3 repo implementation 可进入；host install/load/live acceptance 不在本次 entry authorization 内。

### 6.4 Exit gate

- plugin lint 对官方样例和错误 fixture 有稳定结果。
- exporter 只生成声明的宿主产物，round-trip/structural tests 通过。
- 未创建公共 marketplace、账号系统或 connector runtime。
- 安装后使用 fresh session 验证 bundled skill/tool 可见性；业务效果另行验收。

## 7. P4 Unified capability selection and activation planning

### 7.1 目标

把 profile-independent skill cold loading 扩展为 intent-aware unified selector；为 skill、MCP 和 caller-provided plugin/app/native-tool snapshots 输出统一 availability、side-effect 和 activation plan，同时保持 zero-write 和 host-owned runtime。

### 7.2 当前最大合理切片

- explicit name + required/excluded intent + metadata ranking + abstain。
- skill active/cold-load adapter。
- MCP active profile available/needs_activation adapter。
- plugin/app/connector/native tool caller snapshot adapter。
- direct/indirect/negative/ambiguous/cross-kind golden verifier。
- resident skill、8000 字符预算、fresh process/task 和 full gate closeout。

### 7.3 非目标

- 不切换 skill/MCP profile，不写 host config，不重启或创建新任务。
- 不安装/启停 plugin/MCP，不处理 OAuth/token，不接管 approval。
- 不调用 provider 做每次 routing，不建立 embedding database、daemon 或 team service。
- 不把 repo corpus 结果写成所有自然语言、host_loaded 或 live_accepted。

### 7.4 Entry evidence

- 两个不同完整请求均把 implementation/architecture assessment 错误路由到 review-only/interview-only skills。
- 用户明确要求推进统一无感选择主链并授权更新产品与实施真源。
- schema v2 selector 的首批 4 个失败用例已完成 red→green。

### 7.5 Exit gate

- P4 6/6 tasks done，planning/entry verifier 0 finding。
- golden corpus expected/forbidden/abstain 全部通过，side-effect violations=0。
- full Unit/E2E、doctor、dependency/host/planning 和 full quality gate 通过。
- 真实只读 prompt replay 证明 implementation 不再选择 draft/grill，available/disabled MCP 输出正确 plan。
- profile/config/plugin/MCP runtime 未被 selector 修改；host/live 独立记录。

### 7.6 后续 conditional scale surfaces

以下能力仍没有当前承诺，只在独立触发条件满足后建立新 Phase/spec：

| 候选 | 触发条件 | 默认决定 |
| --- | --- | --- |
| TUI/GUI | CLI inventory/diff 已被重复使用且可用性成为主要阻碍 | 保持 CLI/report |
| local daemon/API | 多进程共享状态或外部客户端是已验证核心需求 | 不建设 |
| database/search | 文件索引无法满足已量化规模/性能 | 不建设 |
| .NET/TypeScript core | PowerShell seam 无法解决反复类型、性能或跨平台缺陷 | 不重写 |
| team/remote control | 存在明确多用户/RBAC/审计需求和运营边界 | 不建设 |
| public marketplace | 有独立供应链、审核、发布和支持能力 | 依赖官方目录，不自建 |

## 8. P5 Adaptive Capability Fabric

### 8.1 目标

把 P4 selector 演进为统一决策平面：理解任务、检索和策略判决、组合最小 capability DAG、复用兼容 session capability，并读取宿主当前可用性；所有执行仍走宿主原生 surface。

### 8.2 当前最大合理切片

- schema v3 structured task model 和 P4 field compatibility。
- architecture/meta mismatch guard 与 inspect/implement/verify DAG。
- session hysteresis 和 recommendation-only profile preheat。
- Codex App Server `skills/list`、`app/installed`、`app/list`、`mcpServerStatus/list` read-only adapter。
- stale/inaccessible/not-callable/auth/partial source semantics。
- golden、fresh-process、live read-only probe 和 full closeout。

### 8.3 非目标

不调用 provider 做日常 route，不建立 embedding DB/daemon/control plane；不安装 plugin/MCP、不 OAuth、不写 config/profile/session/thread，不把 ChatGPT web 与本机 Codex 当成共享 runtime。

### 8.4 Entry evidence

真实全局架构查询被 P4 关键词 selector 错选 Windows/MCP construction capability；当前官方手册与 `codex-cli 0.145.0` 已证明稳定 read-only App Server seam。

### 8.5 Exit gate

P5 5/5 task、schema compatibility、golden、fresh query、live read-only multi-kind snapshot、ordered repository gates 和 full quality 全部通过；zero writes/side-effect violations；repo/host/live truth 分离。

2026-08-03 closeout：上述 exit gate 已满足。16 profiles 全部 fresh-pass 并恢复 default；live snapshot 返回 123 skills、6 installed/callable apps、8 MCPs。`app/list` 的外部未安装 app catalog 因 403 标记 `runtime_complete_catalog_partial`，不影响当前 runtime inventory，也不升级为 authenticated app action 或 `live_accepted`。

## 9. Maintenance hold and P6 admission

`P6_ADMISSION_STATUS: hold`

P5 完成后进入维护期，不按 Phase 编号惯性扩张。只有同时满足以下条件，才可把状态改为 `admitted` 并创建 P6 spec/manifest：

- 至少 3 个相互独立的真实任务失败，覆盖至少 2 个 task domain，并有可复现输入与误差分类。
- 证据证明失败不能通过 P5 metadata、policy、golden corpus 或直接缺陷修复解决。
- `session_plan`、`preheat_recommendation` 等 P5 输出已有真实消费者证据；不得为未消费字段继续扩 schema。
- 当前 phase truth、历史 entry lifecycle、full-suite 单次执行、evidence ledger 和 test timing debt 均已闭合。
- 用户明确授权新的产品目标；新 Phase 仍须给出非目标、write set、退出条件和 live boundary。

未满足上述条件时，只允许修缺陷、扩真实 corpus、删除无用字段、改善性能与文档；禁止新增 schema major、daemon/database/provider router、host mutation 或新的治理层。

### 9.1 Lean AI Software Delivery maintenance track

该 track 面向 skills-manager 辅助 ChatGPT/Codex/Claude 高效完成软件交付的总体方案，但只增加 advisory 规划与可验证契约。它与 P5 并行，不是 P6，不改变 Phase sequence，不授权 host/runtime 行为。

```text
M0 maintenance design package
  -> M1 10-task observe-only pilot
     -> M2 P5-local metadata/golden/defect correction
        -> M3 retain / revise / retire / P6 admission review
```

| Milestone | 状态 | 内容 | 退出条件 | 明确不证明 |
| --- | --- | --- | --- | --- |
| `M0` | `repo_verified` | 综合 PRD/架构/路线图、maintenance spec/manifest、plan/todo、companion verifier、测试与一份 reviewed evidence | 4/4 planning tasks done；新旧 verifier 和 full gate 通过 | 新工作流业务有效、pilot 已运行、host loaded、live accepted |
| `M1` | `conditional` | 选取 10 个覆盖 Discovery/Main-chain/Stabilize/Refactor/Release/Operate 的真实任务，记录无 lens baseline 与 advisory treatment | 用户授权；任务/数据安全边界明确；每项只做 observe，不设完成硬阈值 | 普遍效果、因果结论、自动 promotion |
| `M2` | `conditional` | 只修正 pilot 证明的 P5 metadata、golden、触发策略或直接缺陷 | 至少两个任务复现同一缺口；现有字段无法表达且有真实消费者时才评估小字段 | schema major、新 runtime、daemon/database |
| `M3` | `conditional` | 比较净收益并决定 `retain | revise | retire`；仅把满足既有 admission 的证据提交 P6 review | 指标与失败样本经过人工 review；无净收益流程已删除或降级 | 自动 admitted、自动创建 P6 manifest |

M1 pilot 的最小样本覆盖：模糊需求澄清、从零主链、既有缺陷、行为保持重构、前后端/数据 seam、测试策略、发布准备、运维事件、能力/skill 选择和一次不应启动复杂流程的简单任务。样本在执行时另行登记；本路线图不把候选任务伪装为当前承诺。

observe-only 指标为 TTFV、返工切片、非预期人工打断、非产品 artifact、focused/full gate 耗时和 repo_verified→live_accepted 转化。`M1` 前不设数值阈值；指标不作为单项 completion gate，LLM 评分不作为唯一证据。对每项任务同时记录任务复杂度、既有测试健康和人工授权差异，避免把环境差异误判为流程收益。

M3 判定优先删除性维护：pilot 没有缩短 TTFV、没有减少返工/打断，或新增 artifact/上下文/维护成本抵消收益时，删除候选模板、规则或 skill；只有稳定重复且经 replay/shadow/canary 的做法才 reviewed promotion。宿主模型或官方能力已原生覆盖时，相关功能进入 adapt/retire，而不是为了保留项目范围继续包装。

## 10. 风险登记

| Risk ID | 风险 | Phase | 守卫 |
| --- | --- | --- | --- |
| `RISK-001` | 产品范围膨胀为 runtime/control plane | 全部 | PRD non-goal + planning verifier + ADR review |
| `RISK-002` | semantic rule false positive 被自动应用 | P1/P2 | advisory-only -> explicit apply |
| `RISK-003` | host config 漂移/损坏 | P0/P2 | native CLI first + before hash + backup + fixture |
| `RISK-004` | schema/manifest 文档漂移 | P0+ | version + verifier + compatibility tests |
| `RISK-005` | 官方目录变化导致重复能力 | P1/P3 | official-first inventory + reference refresh |
| `RISK-006` | 大规模重构破坏现有 CLI | P0 | one seam per slice + wrapper + golden tests |
| `RISK-007` | repo pass 被写成 live accepted | 全部 | verification level enum + evidence review |
| `RISK-008` | 任务清单过早细化后腐化 | P1+ | 只为 current Phase 建 manifest |
| `RISK-009` | Lean advisory 膨胀成第二套 agent runtime | maintenance | ADR-SMV-012/013 + runtime write-set denylist |
| `RISK-010` | observe 指标变成流程 KPI 或虚假完成激励 | maintenance | ADR-SMV-016 + 无 baseline 不设 gate |
| `RISK-011` | 自学习把偶然成功/错误经验扩散为 skill | maintenance | replay -> shadow -> canary -> reviewed promotion -> retire |

## 11. 路线维护

- Phase 进入实施前：刷新官方语义、reference revisions、当前代码 seam 和 baseline gate。
- Phase 进入实施时：创建该 Phase 的 detailed spec 和 task manifest；更新 `current_phase`。
- Phase 退出时：运行本仓 full gate、Phase verifier、native probe（适用时），写 change evidence。
- `designed` 不能直接改为 `done`；必须经过 `in_progress` 和 exit gate。
- 外部插件目录、宿主加载或社区 revision 的变化只触发 review，不自动改 runtime truth。
