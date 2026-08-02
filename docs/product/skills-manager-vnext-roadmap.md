# skills-manager vNext 路线图

**program_id**: `skills-manager-vnext`
**roadmap_version**: 1
**最后更新**: 2026-08-02

## 1. 状态总览

| Phase | 名称 | 状态 | 当前真值 |
| --- | --- | --- | --- |
| `P0` | Foundation and contracts | `complete` | 9/9 tasks repo_verified；host_loaded/live_accepted 未执行 |
| `P1` | Read-only inventory and rule advisor | `complete` | 9/9 tasks repo_verified；host_loaded/live_accepted 未执行 |
| `P2` | Transactional explicit apply | `complete` | 7/7 repo_verified；单 Git 仓规则 create/update pilot 通过，host/global-user apply 仍禁用 |
| `P3` | Plugin-aware distribution and evaluation | `complete` | 7/7 tasks repo_verified；fixture-first，host/live 未执行 |
| `P4` | Conditional scale surfaces | `conditional` | entry decision=`not_started/deferred`；未创建 manifest |

状态只可在相应 exit gate 有当前证据后更新。Phase 文档完成不等于 Phase 实现完成。

## 2. 全局依赖

```text
P0 contracts and seams
  -> P1 read-only facts and diagnostics
     -> P2 safe write protocol
        -> P3 packaging/evaluation

P4 requires independent product evidence and does not follow automatically.
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

在 P1 findings 可靠后，为 MCP、skill projection 和单目标规则 patch 提供一致 plan/freshness/apply/receipt/rollback。

### 5.2 Feature slices

- `P2-S1`：OperationPlan enforce 和 stale/freshness gate。
- `P2-S2`：atomic write、backup 和精确 rollback。
- `P2-S3`：rules plan 输出 diff，不自动 apply。
- `P2-S4`：rules apply 仅允许单 repo、精确路径、显式 token。
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

## 7. P4 Conditional scale surfaces

以下能力没有当前承诺，只在触发条件满足后建立独立 PRD/spec：

| 候选 | 触发条件 | 默认决定 |
| --- | --- | --- |
| TUI/GUI | CLI inventory/diff 已被重复使用且可用性成为主要阻碍 | 保持 CLI/report |
| local daemon/API | 多进程共享状态或外部客户端是已验证核心需求 | 不建设 |
| database/search | 文件索引无法满足已量化规模/性能 | 不建设 |
| .NET/TypeScript core | PowerShell seam 无法解决反复类型、性能或跨平台缺陷 | 不重写 |
| team/remote control | 存在明确多用户/RBAC/审计需求和运营边界 | 不建设 |
| public marketplace | 有独立供应链、审核、发布和支持能力 | 依赖官方目录，不自建 |

## 8. 风险登记

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

## 9. 路线维护

- Phase 进入实施前：刷新官方语义、reference revisions、当前代码 seam 和 baseline gate。
- Phase 进入实施时：创建该 Phase 的 detailed spec 和 task manifest；更新 `current_phase`。
- Phase 退出时：运行本仓 full gate、Phase verifier、native probe（适用时），写 change evidence。
- `designed` 不能直接改为 `done`；必须经过 `in_progress` 和 exit gate。
- 外部插件目录、宿主加载或社区 revision 的变化只触发 review，不自动改 runtime truth。
