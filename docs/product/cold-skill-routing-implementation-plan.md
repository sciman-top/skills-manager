# 冷技能路由实施计划与任务清单

**产品契约**: 2.0  
**状态语义**: versioned design input；运行状态只由 Git、ignored receipt 和 fresh-host 事件证明  
**路线图**: [冷技能路由路线图](cold-skill-routing-roadmap.md)  
**验收程序**: [冷技能路由验收 Runbook](../runbooks/cold-skill-routing-acceptance.md)

## 1. 执行总则

本计划把“宿主 AI 语义理解 + 原生子代理优先 + 全冷目录可调度 + 精确闭包受控加载”拆成可独立执行、回滚和验收的任务。每个任务只做其卡片中的 write set，达成 stop condition 即停止；任务之间的执行状态不可由本文档自行宣布。

主链合同：

    可见能力是否足够
    -> 专门工作流是否有净收益且误调用成本可接受
    -> 一次有界、只读、domain-scoped cold discovery
    -> 宿主作语义选择
    -> router 精确验证候选/闭包/hash/副作用/contract
    -> 独立 admission
    -> one-shot、等待用户输入、多轮原生 child 或 fail-closed

硬性约束：

- capability-router 的固定角色是 discovery 和 deterministic validation，输出必须保持 `decision_owner=host_ai`、`semantic_routing_performed=false`、`writes_performed=false`。它不是关键词分类器、排序器、执行器或每请求 middleware。
- 只有用户显式点名不可见本地技能，或宿主高置信度判断可见能力不足且专门工作流确有净收益时，才有一次 discovery 预算。讨论技能、普通解释、可见直达、语义不确定均不是触发充分条件。
- 发现、精确校验、真实 SKILL.md 读取、native child 启动、child 完成和用户接受结果是不同事件。低层事件不能升格为高层验收。
- router validation 只授权读取被验证的 closure，绝不等于执行、写入、外部调用、第二次 discovery 或动态 profile 切换。
- custom-agent template 只允许静态固定自己的 model 和 model_reasoning_effort；不得管理 provider、base URL、auth、secret、session、global config 或 fallback。
- 任何 controlled_write 都需要当前用户实施请求、exact write set、minimum proof、stop 和实际写入清单。根候选的 unknown、external、冲突或缺失 contract 一律 fail-closed；依赖项 contract 只描述其被单独选为根时的 dispatch，不得改变当前根候选的 adapter。

## 2. 依赖图与真值边界

| 任务 | 前置 | 阶段 | 完成后最高边界 |
| --- | --- | --- | --- |
| CSR-100、CSR-110 | 无 | CSR-R1 | repo_verified |
| CSR-120、CSR-130 | CSR-100/110 | CSR-R2 | repo_verified |
| CSR-140 | CSR-120/130 | CSR-R0/R2 | repo_verified |
| CSR-150 | CSR-140 已提交且当前授权 | CSR-R3 | filesystem_projected |
| CSR-160 | CSR-150 + fresh Codex | CSR-R4 | host_specific_live_accepted |
| CSR-170 | CSR-160 或可观测子集 | CSR-R5 | observed / platform_na |
| CSR-180 | CSR-160 的真实 admission drift | execution-admission P0 | repo_verified；host adapter 另验 |

不可声称的跳级关系：

| 已有证据 | 不能声称 |
| --- | --- |
| 单元测试、build、router JSON | 宿主已理解或 SKILL.md 已读取 |
| target template 存在、config 可解析 | fresh host 已加载 |
| router candidate_load_validated | native child 已创建或业务已接受 |
| ZCode 父任务代行 | Codex native child 已启动 |
| 历史 Sol child 或 503 日志 | 当前 Terra/high 投影已验收 |
| 三个样本 | 全部冷技能或全部自然语言已验收 |

实施者每次开始前运行 git diff --check，并用 git diff 划清用户/并发修改。默认不需要子代理；若并行，write set 必须互斥，且任何 agent 都不得同时写 runbook、scenario matrix、同一测试文件或同一 receipt fixture。

## 3. 统一数据合同

### 3.1 Receipt v2

所有新 live/fixture receipt 使用三层结构：

    expected: 本场景允许、禁止和所需的 contract
    observed: host/router/child/filesystem 的实际事件
    assertion: verifier 根据二者作出的保守结论

最小 JSON 形状：

    {
      "schema_version": 2,
      "scenario_id": "S02",
      "request_verbatim": "<完整原始请求>",
      "expected": {
        "route_class": "visible_direct|cold_candidate|discovery_only|ordinary_no_skill|write_plan_only|target_bound|artifact_workflow_deferred",
        "cold_discovery": "required|forbidden|conditional",
        "execution_contract": "none|one_shot|parent_user_input|multi_turn_user_decision",
        "native_child": "required|forbidden|not_supported|conditional"
      },
      "observed": {
        "host_visible": "visible|not_visible|not_observable",
        "cold_discovery": "observed|not_observed|not_observable",
        "candidate_load_validation": "observed|not_observed|not_observable",
        "skill_md_loading": "observed|not_observed|not_observable",
        "native_child": "started|awaiting_user_answer|completed|not_started|not_supported|not_observable",
        "writes_or_external_calls": []
      },
      "assertion": {
        "status": "pass|fail|not_observable",
        "achieved_boundary": "repo_verified|filesystem_projected|host_loaded|candidate_discovery_only|candidate_load_validated|host_specific_live_accepted",
        "evidence_refs": ["<redacted path or host event id>"]
      }
    }

Verifier 必须拒绝以下组合：

- expected cold discovery 为 forbidden，而 observed 为 observed；
- router validation 被写成 SKILL.md 已读取；
- ZCode 或无 child 的 host 以 native live accepted 结论收口；
- multi_turn_user_decision 被 cold-capability-runner 执行或总结；
- target-bound 缺 workbook/sheet/cell/tab/URL/目标状态仍声明 pass；
- controlled_write 缺 exact write set、minimum proof、stop 或实际写入清单；
- scenario 缺失、重复、枚举值漂移或 evidence_refs 为空。

### 3.2 29 组 Scenario Matrix

新建 tracked 文件 tests/fixtures/cold-skill-routing/scenarios.json。它是测试输入，不是 router 的运行时语义模型，也不得被 production code 读取。

顶层固定包含：

    {
      "schema_version": 1,
      "source_provenance": {
        "source_kind": "user_supplied_attachment",
        "source_sha256": "d03ad0d4f7459f425e3c9fbc6e20350d46dde2e2deb7249ea29b8c332c5d366b",
        "source_description": "用户提供的 29 组显式和隐式工作流测试范例"
      },
      "scenarios": []
    }

每个条目至少有 id、source_index、variant、request_verbatim、route_class、cold_discovery、allowed_candidate_names、forbidden_events、execution_contract、side_effect_ceiling、required_context、verification_mode。请求原文必须逐字转录；后来新增的范例必须标记 source_kind=derived_test_case，不能伪装为用户语料。

隐式场景的 allowed_candidate_names 可以是兼容集合或空集合，不能为了测试方便将自然语言硬钉成唯一技能。它的 oracle 是“发现是否允许、最多一次、是否越权、contract 是否正确”，不是某个固定名称。

## 4. 场景源分类表

| 附件编号 | 类别 | route_class | cold discovery | 关键验收 oracle |
| --- | --- | --- | --- | --- |
| 1 | grill-with-docs 文档审问 | cold_candidate | 显式 required；隐式 conditional | multi_turn_user_decision，design-griller，一题一轮，完整三成员 closure |
| 2 | grill-me 原生审问 | visible_direct | forbidden | direct native 对照，无 router |
| 3 | code-review-and-quality | visible_direct | forbidden | read-only quality report |
| 4 | systematic-debugging | visible_direct | forbidden | 先复现/测量，未授权不改 |
| 5 | research 官方资料 | visible_direct | forbidden | 一手链接与不确定性 |
| 6 | verification-before-completion | visible_direct | forbidden | fresh lowest-sufficient proof |
| 7 | codebase-design | visible_direct | forbidden | read-only deep-module 分析 |
| 8 | PowerShell automation | visible_direct | forbidden | PowerShell 7，写入另行 admission |
| 9 | capability-router 自检 | discovery_only | conditional | 返回候选/closure/hash/contract，不执行 |
| 10 | skill-creator | visible_direct | forbidden | 只计划，不创建 |
| 11 | skill-installer | visible_direct | forbidden | 只评估，不安装 |
| 12 | documents | artifact_workflow_deferred | conditional | 路由与 Word render/视觉验收分开 |
| 13 | PDF | artifact_workflow_deferred | conditional | 文本提取与 key-page render 分开 |
| 14 | presentations | artifact_workflow_deferred | conditional | 无障碍/版式质量另跑 |
| 15 | spreadsheets | artifact_workflow_deferred | conditional | 公式、类型、结果另跑 |
| 16 | Excel live control | target_bound | forbidden | workbook、sheet、cell 必须存在；否则 platform_na |
| 17 | in-app browser | target_bound | forbidden | URL/可见状态/明确动作必须存在 |
| 18 | Chrome control | target_bound | forbidden | 已登录 target tab 和明确动作必须存在 |
| 19 | image generation | artifact_workflow_deferred | forbidden | 可预览图片，路由与成品质量分开 |
| 20 | image editing | artifact_workflow_deferred | forbidden | source image 与精确编辑范围必须存在 |
| 21 | controlled-write plan | write_plan_only | forbidden | exact write set/proof/risk/rollback，尚不写 |
| 22 | read-only audit | visible_direct | forbidden | 禁写、禁安装、禁 commit/push |
| 23 | design comparison | visible_direct | forbidden | 仅能改变选择的问题 |
| 24 | multi-turn user decision | visible_direct | forbidden | visible grill-me 一题一轮等待用户；作为 multi-turn 直达对照 |
| 25 | one-shot read-only | cold_candidate | conditional | runner 只在 read-only admission 下启动 |
| 26 | implicit invocation evidence | discovery_only | conditional | 七项 event field 均记录 |
| 27 | discover but do not execute | discovery_only | conditional | 只读发现，authorization 仍 not_granted |
| 28 | execution_contract branching | cold_candidate | conditional | 四分支 + unknown/external fail-closed |
| 29 | daily default wording | ordinary_no_skill | conditional | 宿主先判断；允许不 discovery |

#12–#15、#19–#20 必须保留在 matrix，但 verification_mode 是 routing_only_then_artifact_run。#16–#18 在未提供真实对象状态时只能报告 platform_na，禁止通过猜测去控制应用或浏览器。

## 5. 原子任务卡

### CSR-100：静态固定两个 bridge 的 model/effort

- **Goal**：消除 design-griller 和 cold-capability-runner 无意继承全局 default subagent model 的断点。
- **Current evidence**：overrides/resources/native-agent-bridge 中两个 TOML 缺 model 与 model_reasoning_effort；历史 child 曾解析到 Sol，但该历史不能作 current acceptance。
- **Dependencies**：无。
- **Exact write set**：overrides/resources/native-agent-bridge/design-griller.toml；overrides/resources/native-agent-bridge/cold-capability-runner.toml；已经存在的产品文档仅做必要同义更新。
- **Implementation contract**：在 description 后、sandbox_mode 前各新增且只新增：

    model = "gpt-5.6-terra"
    model_reasoning_effort = "high"

  不得加入 provider、model_provider、base_url、api_key、auth、secret、fallback、profile 或 session 字段；不得更改既有 sandbox 或 developer_instructions。
- **Test cases**：两个模板均恰有一个 Terra/high 字段对；name、ownership marker、sandbox 原样保留。
- **Minimum verification**：pwsh -NoProfile -File .\build.ps1；pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/NativeAgentBridge.Tests.ps1；确认 skills.ps1 无生成漂移。
- **Out of scope**：~/.codex/config.toml、~/.codex/agents、Cockpit、provider/auth、ignored reports。
- **Stop / rollback**：若当前 parser 不接受字段或只能靠改全局 config 继续则停；git revert repo-side 小提交。
- **Truth boundary / class**：repo_verified；auto。

### CSR-110：模板模型字段与禁止字段测试

- **Goal**：让 CSR-100 由 deterministic test 而非 prose 约束。
- **Current evidence**：tests/Unit/NativeAgentBridge.Tests.ps1 已覆盖 dry-run、ownership、backup 和 receipt hash，但未检查模型 pin。
- **Dependencies**：CSR-100。
- **Exact write set**：tests/Unit/NativeAgentBridge.Tests.ps1；必要时仅 tests/fixtures/native-agent-bridge 下 static TOML fixture。
- **Public contract**：两份受管 template 必须是 Terra/high；禁止精确 TOML key provider、model_provider、base_url、api_key、auth、fallback；Sync-NativeAgentBridge 的 source_sha256/target_sha256 contract 不变。
- **Test cases**：正例两模板；缺 model、缺 effort、重复字段、错 model、错 effort、出现禁字段的负例；source content 的 name/marker/sandbox regression。
- **Minimum verification**：CSR-100 focused proof + 新 Pester；测试只用 temp root，不读取 live host config。
- **Out of scope**：不改 src/Application/NativeAgentBridge.ps1，不增加 model resolver。
- **Stop / rollback**：若需要真启动 child 才能决定测试结果则停；git revert 同一切片。
- **Truth boundary / class**：repo_verified；auto。

### CSR-120：来源可追溯的 29 组场景矩阵

- **Goal**：把用户批准语料固化为机器可验证的 routing oracle，不引入第二语义路由器。
- **Current evidence**：用户附件 29 组；现有 P0 receipt 只覆盖 8 类。
- **Dependencies**：CSR-100/110。
- **Exact write set**：tests/fixtures/cold-skill-routing/scenarios.json；tests/Unit/ColdSkillRoutingScenarios.Tests.ps1；必要的 runbook/plan 同义链接。
- **Implementation contract**：所有 source_index=1..29 无缺失/重复；显式与隐式变体分别保存；route_class 仅可为 visible_direct、cold_candidate、discovery_only、ordinary_no_skill、write_plan_only、target_bound、artifact_workflow_deferred；cold_discovery 仅可为 required、forbidden、conditional。
- **Test cases**：verbatim 非空、provenance hash、合法枚举；#1 三成员 multi-turn；#2/3–8/10–11/21–23 禁 discovery；#16–18 required_context；#12–15/19–20 deferred；#27 no execute；#28 contract 分支；#29 可 no discovery。
- **Minimum verification**：JSON parse + focused scenario Pester。不需要 host projection 或 29 个二进制 fixture。
- **Out of scope**：不改 skills.json、catalog、router runtime；不创建 Office/image 成品。
- **Stop / rollback**：原始附件/哈希无法核实，或被迫给隐式 prompt 指定唯一冷技能时停；git revert matrix/test。
- **Truth boundary / class**：repo_verified；auto。

### CSR-130：Receipt v2 verifier 与 legacy migration

- **Goal**：从机制上消除 pass 字段同时表示“期望满足”和“事件已发生”的过度声明。
- **Current evidence**：现行 runbook 使用 legacy 单字段；reports/cold-skill-eval/2026-08-23-cold-routing-p0/receipt.json 必须保留为原件。
- **Dependencies**：CSR-120。
- **Exact write set**：scripts/quality/verify-cold-skill-routing-receipt.ps1；tests/Unit/ColdSkillRoutingReceipt.Tests.ps1；tests/fixtures/cold-skill-routing/receipts；docs/runbooks/cold-skill-routing-acceptance.md。
- **Public contract**：verifier 接收 ReceiptPath、ScenarioMatrixPath、AllowLegacyMigration；非零退出给稳定 finding code；只读 verifier 不写 live receipt。迁移输出保留 legacy_receipt_path + legacy_receipt_sha256，不能重写原件。
- **Test cases**：合法 candidate_load_validated；discovery forbidden yet observed；router claimed SKILL.md loaded；ZCode claimed native accepted；multi-turn sent to runner；target-bound 无对象；controlled-write 缺字段；场景缺失/重复；legacy migrate 保留 not_observable。
- **Minimum verification**：focused receipt Pester + direct verifier on valid/invalid fixtures + git diff --check。
- **Out of scope**：不改 router JSON schema、不建长期 receipt 数据库、不读取 provider/session 私密数据。
- **Stop / rollback**：若 verifier 需要语义排序或对 host 会话进行写操作则停；git revert script/test/fixture/runbook。
- **Truth boundary / class**：repo_verified；auto。

### CSR-140：junction 与 execution contract 最小集成回归

- **Goal**：新文档和测试合同不得削弱既有 cross-root router fail-closed 防线。
- **Current evidence**：tests/Unit/CapabilityRouterCrossRepo.Tests.ps1 覆盖 router junction、environment junction、physical counterpart 缺失；CapabilityRouter.Tests.ps1 覆盖 contract。
- **Dependencies**：CSR-110、CSR-120、CSR-130。
- **Exact write set**：优先只改上述两个 router test 文件；仅发现真实 contract gap 时才改 router source，不为让新文档“通过”放宽路径规则。
- **Test cases**：CatalogPath junction 正例；跨根 env-var junction 正例；counterpart missing 负例；entrypoint/package hash stale、reparse escape、closure violation fail-closed；grill-with-docs 三成员 closure 不能进 runner；MaxCandidates 超限为 domain_hint_required + zero candidate。
- **Minimum verification**：
  - pwsh -NoProfile -File .\build.ps1
  - pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/NativeAgentBridge.Tests.ps1
  - pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/ColdSkillRoutingScenarios.Tests.ps1
  - pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/ColdSkillRoutingReceipt.Tests.ps1
  - pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/CapabilityRouterCrossRepo.Tests.ps1
  - pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/CapabilityRouter.Tests.ps1
- **Out of scope**：构建生效、host、29 次 live execution。
- **Stop / rollback**：需放宽 containment/reparse/hash 或增加 semantic selector 时停；git revert。
- **Truth boundary / class**：repo_verified；auto。

### CSR-150：提交后的受控 host projection

- **Goal**：将已提交的 source templates 以既有 promotion contract 投影到 Codex custom agent 根，并留下精确恢复证据。
- **Current evidence**：Sync-NativeAgentBridge 已强制 ~/.codex/agents target、source/target hash、backup root、promotion context 和 receipt。
- **Dependencies**：CSR-140 green、本切片已提交、worktree clean、当前用户授权。
- **Exact write set**：~/.codex/agents/design-griller.toml；~/.codex/agents/cold-capability-runner.toml；ignored reports/native-agent-bridge/current.json；仅 receipt 指名的 ~/.codex/skills-manager-agent-backups 路径。
- **Procedure**：
  1. 读取 git status、HEAD、模板 SHA 和旧 receipt。
  2. 执行 pwsh -NoProfile -File .\skills.ps1 构建生效；禁止手写 target TOML。
  3. 比较 receipt 的 source_revision、definition、source/target SHA、backup_paths、native_mutations。
  4. 只读检查 target TOML 含 Terra/high 且无 provider/auth。
- **Minimum verification**：两个 source/target SHA 相等；无未列 host 写入；skills.ps1 无生成漂移。
- **Out of scope**：~/.codex/config.toml、Cockpit、服务重启、plugin cache、其他 user agents。
- **Stop / rollback**：dirty worktree、promotion 拒绝、目标路径漂移、需要 auth/provider 或 backup 逃逸即停；只能使用本 receipt 的 backup_paths 回滚。
- **Truth boundary / class**：filesystem_projected；human-authorized host write。

### CSR-160：fresh Codex native child 验收

- **Goal**：用当前 Codex host event 证明 model pin、child 创建和 contract 分流。
- **Current evidence**：历史 Sol 成功及 503 都是 pre-change baseline，不能替代本任务。
- **Dependencies**：CSR-150 receipt；fresh Codex app/CLI/IDE session；用户愿意回答首个设计问题。
- **Exact write set**：ignored reports/cold-skill-eval/<run-id>/receipt.v2.json 及最小文本 fixture；禁止业务代码写入。
- **Live sequence**：
  1. 显式 $grill-with-docs；记录 router candidate/closure、design-griller child id、Terra/high、单个首问和 awaiting_user_answer。
  2. 用户给出真实决策答案；parent 回传给同一 child，child id 不变，最后得到 decision capsule。
  3. 显式 domain-modeling；仅完整 one_shot + read-only admission 才启动 cold-capability-runner，记录 zero writes。
  4. 显式 $grill-me；作为 visible direct 对照，router event 必须 not_observed。
  5. 每一步均由 receipt v2 verifier 审计。
- **Minimum verification**：child id、model/effort、lifecycle event；multi-turn same-child continuity；runner 实际 write set 为空；visible direct 无 router 事件。
- **Out of scope**：不重启 Cockpit、不改 auth/provider、不做 controlled write、不外推 78 个技能。
- **Stop / rollback**：wrong model/effort、503/auth、child 不可观测、contract 降格、需外部副作用时保存 fail/not_observable receipt 并停；桥接回滚使用 CSR-150 receipt。
- **Truth boundary / class**：仅当前 host 的 host_specific_live_accepted；human-interactive host acceptance。

### CSR-170：隐式语义样本与工件专项

- **Goal**：获得三正三负 fresh-host 观测，并将 artifact correctness 与 routing correctness 拆开。
- **Current evidence**：CSR-160 只覆盖 explicit representative paths；附件包含 artifact 和 target-bound 类请求。
- **Dependencies**：CSR-160；未完成时只能执行 not_observable 或 fixture-only 子集，不得称 live pass。
- **Exact write set**：ignored reports/cold-skill-eval/<run-id>/receipt.v2.json；实际授权时独立 reports/cold-skill-artifacts/<run-id>。
- **Test matrix**：
  - 三个隐式 cold 正例取 #1/#25/#28 的不同自然语言；记录是否发现、domain hint、候选允许集合、single discovery、contract、越权情况。合理拒绝要如实记录 reason。#24 另作 visible multi-turn 直达对照，不计入 cold positive。
  - 三个负例取普通解释、visible direct、纯 policy 讨论；不得 router、child、side effect。
  - #12–#15/#19–#20 先 routing-only，再由对应 skill 做独立 render/visual/data run。一个环节失败不得伪装为另一个环节失败。
  - #16–#18 缺真实 target 时写 platform_na、reason、alternative verification，不操作应用。
- **Minimum verification**：receipt verifier；六个 fresh-host 原始事件不复用；artifact run 另有输入/输出 hash 与 rendered evidence。
- **Out of scope**：不从三样本推断触发率，不加词法 router，不反复调参直到“通过”。
- **Stop / rollback**：需访问未授权帐户、不可回滚 external effect 或为了指标强行调用 router 时停；仅删除本 run ignored output。
- **Truth boundary / class**：observed/platform_na；human-authorized observation。

### CSR-180：design-griller execution admission P0

- **Goal**：把 `router validation != execution authorization` 落到可重算的 read-only admission 与单题 plan seam，防止 raw selection、stale closure 或 parent 自动代答被当成多轮执行许可。
- **Exact write set**：`src/Domain/ExecutionAdmission.ps1`；`build.ps1`；`overrides/resources/native-agent-bridge/design-griller.toml`；受影响 unit tests；本计划的本任务卡片。不得改 router 语义选择、provider/auth/config、runner 或宿主进程。
- **Interface**：`New-ExecutionAdmission` 接收单一精确 validation、原始请求、admitted goal、只读 read set、authority basis 与 issued time，产生 content-addressed `admission_id`；`New-ExecutionPlan` 仅派生 `ask_one_question` 的 `plan_id`；`Test-ExecutionAdmissionRevalidation` 在 spawn 前复核 closure/read-set hash、catalog fingerprint、effective contract 与 plan/admission identity。
- **Hard invariants**：仅 `multi_turn_user_decision / design-griller / parent / one_question_then_wait`；`requested_operation=read_only` 且 exact write set 为空；closure/read set 必须是 workspace 内精确文件及 SHA-256；unknown/external、多个根候选、hash/contract 漂移、raw selection/contract 或不具可归因回答来源的 follow-up 一律拒绝。可归因来源包括真人逐字回答和永久合同允许的 `authorized_ai_delegate_answer`；后者必须绑定授权证据与 SHA-256，且不得升级为真人接受或 `host_specific_live_accepted`。
- **Minimum verification**：valid admission/plan、write-set tamper、closure hash drift、contract mismatch 的 focused Pester；build 后核对 `skills.ps1` 无漂移；模板静态测试。
- **Truth boundary / class**：`repo_verified`。模板文本与 repo-side revalidation 只能形成 `soft_guard_only`，直到 fresh host 能在 spawn 前实际调用该 seam、记录权威 effect observation，并由逐轮真实用户回答完成同 child interview。
- **Stop / rollback**：任何需要让仓库接管 host session、解密 parent-child payload、伪造用户来源、修改 auth/provider 或扩展到 runner/controlled-write 时停止；回滚仅撤本卡片 source/template/test/doc 变更。

### CSR-181：one-shot cold-capability-runner execution admission

- **Goal**：复用同一 admission/plan 深模块，把 `one_shot / cold-capability-runner / runner / parent_contract` 也纳入可重算的执行许可；消除 runner 只依赖 TOML prose 判断 admission 的缺口。
- **Exact write set**：`src/Domain/ExecutionAdmission.ps1`；`overrides/resources/native-agent-bridge/cold-capability-runner.toml`；受影响 unit tests；本任务卡片。不得改 provider/auth/config、router 语义选择或宿主 orchestrator。
- **Hard invariants**：one-shot admission 必须绑定 schema-v2 `execution_admission`、精确 validation snapshot、entrypoint/package hash、非空 hash read set、空 exact write set、minimum proof、`parent_contract` stop；plan 必须绑定同一 admission id、`run_once` action、`cold-capability-runner` adapter 与 revalidated closure。one-shot 不得创建 successor admission 或接受后续用户回答。
- **Minimum verification**：valid one-shot admission/plan；missing/mismatched contract；package-local resource drift；write-set tamper；multi-turn successor misuse；build 后 generated seam 无漂移。
- **Truth boundary / class**：`repo_verified`；fresh host 仍需记录真实 child id、解析 model/effort、完成事件与零写入，才能报告 `host_specific_live_accepted`。
- **Stop / rollback**：若需要 host session hook、controlled-write admission 或 provider/auth 变更则停止；回滚仅撤本卡片 source/template/test/doc 变更。

### CSR-190：parent-side successor-admission continuation guard

- **Goal**：避免 parent 在后续 `followup_task` 中把前一轮 admission 或原始 router selection 直接复用为新一题的执行许可。每个真实用户回答必须由新的、不可变的 successor admission 和 plan 绑定。
- **Exact write set**：`src/Domain/ExecutionAdmission.ps1`；`overrides/patches/grill-me/SKILL.md`；受影响 unit tests；本任务卡片。不得改 router 语义选择、host config、provider/auth、runner 或宿主进程。
- **Interface**：`New-ExecutionAdmissionSuccessor` 接收 predecessor admission/plan、原始请求、可归因用户回答、当前 validation、issued time 与 repo root；它先复核 predecessor，再生成带 `prior_admission_id` 与回答 SHA-256 的新 admission/plan。`Test-ExecutionAdmissionContinuation` 复核请求、scope、read set、validation snapshot、时间顺序和 plan binding。
- **Hard invariants**：schema version 已升级为 `2` 以区分带 attempt identity 的 admission；successor 不能复用 admission identity 或 `attempt_id`；每次 `New-ExecutionAdmission` 自动生成新的 32 位小写 hex attempt identity，并将其纳入 immutable canonical payload 与 `admission_id` 哈希。successor 必须绑定精确 predecessor、非空用户回答哈希和更晚 issued time；不能改变 request、goal、authority basis、operation、proof、stop、read set 或 validated selection。回答原文不持久化，仅其 SHA-256 写入不可变 payload。
- **Truth boundary / class**：`repo_verified`；调用方遵守时为 `parent_side_soft_guard_only`。当前 Codex 没有可验证的 pre-followup hook，缺少该 host capability 时必须报告 `host_hard_gate=platform_na`，不得将文件投影或 prompt 文本外推为强制执行。
- **Replay boundary**：`attempt_id` 防止相同内容的 admission 共享 identity，但一次性消费记录与宿主级 replay fail-closed 仍依赖未观测的 pre-followup/execute hook；当前只报告 `repo_verified` 与 `parent_side_soft_guard_only`，不声称 host-level single-use enforcement。
- **Stop / rollback**：若需要拦截宿主 `followup_task`、读取/改写 host session、伪造用户来源或修改宿主配置即停；回滚仅撤本卡片列出的 source/template/test/doc 变更。

## 6. 验证、提交与报告

每个 repo-side 切片按最低充分顺序运行：

1. pwsh -NoProfile -File .\build.ps1。
2. 受影响 Pester；CSR-140 集成时运行五个 focused test files。
3. git diff --check。
4. 纯文档仅运行 pwsh -NoProfile -File .\scripts\quality\run-local-quality-gates.ps1 -Profile docs；任何 source/test/script/template 切片运行同命令的 -Profile auto；只有项目风险分类触发时才 run full。
5. 核对 git diff -- skills.ps1 和 git status --short。

CSR-150 之前必须先完成 repo-side 本地提交。本文档的落盘不授权 commit、push、host projection、provider/auth 改动、重启或 live acceptance。

每项完成报告必须列出 Task、实际 write set、命令或 host event、assertion、实际 truth boundary、deferred/platform_na、回滚入口。只有 CSR-160 的完整 fresh-Codex child 事件可写 host_specific_live_accepted。
