# 冷技能路由实跑验收 Runbook

**契约**: 2.0

**版本**: receipt v2

**性质**: 显式 host-specific 验收工作流；不属于普通编码完成条件
**关联**: [路线图](../product/cold-skill-routing-roadmap.md)、[实施计划](../product/cold-skill-routing-implementation-plan.md)

## 1. 目的与适用边界

本 Runbook 验收以下链路是否在指定宿主中真实发生：

    宿主判断可见能力是否足够
    -> 一次有界 cold discovery（仅必要时）
    -> 宿主语义选择
    -> capability-router 精确闭包验证
    -> admission
    -> execution_contract 分流
    -> 当前宿主的 SKILL.md / native child / 结果事件

它不验收“宿主是否总能理解任意隐式语言”，不把一次代表性任务推广为全部冷目录，不产生任何执行授权，也不替代仓库单元测试。

### 1.1 不可合并的真值层

| 层级 | 必须有的证据 | 明确不证明 |
| --- | --- | --- |
| repo_verified | build、Pester、verifier | host 已加载、SKILL.md 已读、child 已创建 |
| filesystem_projected | source/target SHA、bridge receipt、backup paths | fresh Codex session 已采用模板 |
| host_loaded | fresh host 的可观察加载事实 | child lifecycle 或业务结果 |
| candidate_discovery_only | router 候选/域结果 | 精确选择、SKILL.md load、执行 |
| candidate_load_validated | selected entry/closure/hash/contract 全部通过 | native child 或副作用已经发生 |
| host_specific_live_accepted | 当前宿主的 child id、lifecycle、实际行为、evidence ref | 其他宿主、其他模型、其他 77 个冷技能 |
| observed | 有界样本的真实事件 | 统计触发率或全局语义正确性 |

router 永远保持 writes_performed=false 与 execution_authorization.status=not_granted。可发现、可验证的候选若无 admission，不得被 runner 执行。

### 1.2 宿主能力差异

- Codex Desktop、CLI、IDE：支持 custom agent / native child 时，只有可观察 child id、model、effort、lifecycle 才能达到 host_specific_live_accepted。
- ZCode 或不暴露 native child lifecycle 的宿主：parent 可按 contract 代行交互，但 native_child 必须是 not_supported 或 not_observable；最高只能报告 parent-mediated observation。
- 工具、catalog reader、测试 harness 或 assistant prose：只可当较低层证据，不能作为 native host evidence。

不得通过重启、kill、修改 Cockpit、provider、auth、plugin cache 或 ~/.codex/config.toml 来让验收“通过”。出现这些需求时记录 blocker，停止本 run。

## 2. 前置条件与输入冻结

1. 记录当前 repo HEAD、git status、host 名称、执行表面（Codex/ZCode）、模型与 reason effort。
2. 完成当前切片对应的 repo gate。junction 基线至少包含：

       pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/CapabilityRouterCrossRepo.Tests.ps1
       pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/CapabilityRouter.Tests.ps1

3. 当本 run 依赖 bridge model pin 或 receipt v2 时，先完成 CSR-100 至 CSR-140 的 repo-side commit；无当前明确授权不得运行 构建生效。
4. 所有临时输入位于：

       reports/cold-skill-eval/<run-id>/fixtures/

   不使用不存在的 D:\fixtures\plan.md 或 docs/product/x.md 占位路径。fixture 只应为可公开、最小、无敏感信息的文本；不得修改业务源码。
5. 复制本 run 所用 scenario matrix 的 SHA-256 到 receipt metadata。matrix 必须来自 tracked tests/fixtures/cold-skill-routing/scenarios.json。

## 3. P0 代表性场景

P0 是最小链路，不是 29 组场景的全量 live execution。每个场景的原始语句、路由类型和 oracle 由 scenario matrix 约束；这里提供可复现的代表 prompt。

| ID | 请求语料 | 预期 route class | 必需或禁止的事件 |
| --- | --- | --- | --- |
| S01 | $grill-me 帮我审问 reports/cold-skill-eval/<run-id>/fixtures/plan.md 这个方案 | visible_direct | 可见直达；cold discovery 不得发生 |
| S02 | 请用 $grill-with-docs，结合 reports/cold-skill-eval/<run-id>/fixtures/plan.md 和相关官方资料逐轮审问；一次只问一个会改变决策的问题，不改文件 | cold_candidate | 精确 closure 校验后 design-griller，一题一轮等待用户 |
| S03 | 请用 domain-modeling 只读审视 reports/cold-skill-eval/<run-id>/fixtures/order-model.md，不修改文件 | cold_candidate | one_shot + read-only admission 才可 runner；实际写集为空 |
| S04 | 我要以逐轮审问方式打磨设计：每轮只问一个会改变方案走向的问题，结合已有项目与官方资料，不修改文件 | cold_candidate | 仅宿主判断可见技能不足时一次 decision discovery；不强绑唯一候选 |
| S05 | 解释 route-capability.ps1 中 fingerprint 校验的作用 | ordinary_no_skill | router、child、side effect 均不得发生 |
| S06 | 只列出 decision 域候选及其 closure、availability、entrypoint hash 和 execution_contract；不要加载、不要执行、不要改文件 | discovery_only | router 只读；execution authorization 仍 not_granted |
| S07 | 对受控写 cold skill 先只给 implementation plan：exact write set、minimum proof、rollback 与 stop；尚不修改文件 | write_plan_only | 无实际 write；计划不可被 runner 当 admission |
| S08 | 只读核实官方一手资料是否可访问；若当前宿主无法读取，说明原因与替代验证 | target_bound | 网络/官方源不可用时 platform_na；不阻塞其余场景 |

额外硬回归：在仓内 router、.agents junction router 和跨根 router 中，以 CatalogPath、SKILLS_MANAGER_CAPABILITY_CATALOG 和 env-var junction 运行合法/非法 catalog。物理 counterpart 缺失、hash 漂移、closure 越界和 reparse escape 必须 fail-closed。

## 4. Receipt v2 格式

每场景一条 record，所有 evidence 都必须是工具/host/file event。不得以助手“我使用了某技能”的自然语言作为 evidence。

    {
      "schema_version": 2,
      "run_id": "<yyyy-mm-dd-cold-routing-p0>",
      "scenario_id": "S02",
      "request_verbatim": "<原始请求>",
      "expected": {
        "route_class": "cold_candidate",
        "cold_discovery": "required",
        "execution_contract": "multi_turn_user_decision",
        "native_child": "required"
      },
      "observed": {
        "host_visible": "not_visible",
        "cold_discovery": "observed",
        "candidate_load_validation": "observed",
        "skill_md_loading": "not_observable",
        "native_child": "awaiting_user_answer",
        "child_id_or_reason": "<Codex child id or reason>",
        "effective_execution_contract": {
          "mode": "multi_turn_user_decision",
          "native_agent": "design-griller",
          "conversation_owner": "parent",
          "stop_condition": "one_question_then_wait"
        },
        "model": "gpt-5.6-terra",
        "model_reasoning_effort": "high",
        "writes_or_external_calls": []
      },
      "assertion": {
        "status": "pass",
        "achieved_boundary": "host_specific_live_accepted",
        "evidence_refs": [
          "<redacted router event reference>",
          "<redacted Codex child lifecycle event>"
        ]
      }
    }

状态的含义：

| 字段 | 允许值 | 规则 |
| --- | --- | --- |
| host_visible | visible / not_visible / not_observable | metadata 可见不等于 SKILL.md loaded |
| cold_discovery | observed / not_observed / not_observable | expected forbidden + observed 为硬失败 |
| candidate_load_validation | observed / not_observed / not_observable | observed 表示精确 router 结果，不表示 child |
| skill_md_loading | observed / not_observed / not_observable | 只能由 host/child 的可观察读取事件确认 |
| native_child | started / awaiting_user_answer / completed / not_started / not_supported / not_observable | ZCode 不能写 started |
| assertion.status | pass / fail / not_observable | not_observable 不能因为 expected 满足而自动转 pass |

禁止的结论：

- S02 在首问后直接写 completed 或 decision capsule。
- S02 用 cold-capability-runner 代替 design-griller。
- S03 在无 admission、contract mismatch、unknown/external effect 时启动 runner。
- S01、S05、S07 在发现、child 或写入发生后仍 pass。
- 仅 router output 就将 skill_md_loading 记 observed。
- ZCode parent-mediated 结果写 host_specific_live_accepted。

## 5. Legacy receipt migration

旧格式 receipt 保留为证据原件，尤其是 reports/cold-skill-eval/2026-08-23-cold-routing-p0/receipt.json。迁移必须创建同目录 receipt.v2.json，且不更改旧文件字节。

迁移步骤：

1. 计算 legacy 文件 SHA-256，写入 legacy_receipt_path 和 legacy_receipt_sha256。
2. 将旧的 pass/fail 字段拆成 expected 与 observed。只有旧原件明确给出 host/tool event 时，observed 才能是 observed/started/completed。
3. native child、SKILL.md loading、child id、model/effort 或 same-child continuity 未记录时，一律 not_observable。
4. 若 legacy run 的 host 是 ZCode，native_child 写 not_supported 或 not_observable；assertion 最高为 candidate_load_validated 或 parent-mediated observation。
5. 运行 receipt verifier。verifier 不允许迁移输出因“历史结论为 pass”而获得 live acceptance。

迁移输出示例：

    {
      "legacy_receipt_path": "reports/cold-skill-eval/2026-08-23-cold-routing-p0/receipt.json",
      "legacy_receipt_sha256": "<sha256>",
      "migration_notes": [
        "native child lifecycle was not observable in the source host",
        "router validation retained as candidate_load_validated"
      ]
    }

## 6. Fresh Codex 验收步骤

### 6.1 CSR-R3 前置投影

仅在已提交、worktree clean 且获当前授权时：

1. 执行 pwsh -NoProfile -File .\skills.ps1 构建生效。
2. 读取 reports/native-agent-bridge/current.json。
3. 对 design-griller 和 cold-capability-runner，比较 source_sha256 与 target_sha256；确认 source_revision 是本次提交，backup_paths 精确、无意外 definitions。
4. 只读检查 ~/.codex/agents 下两文件：均为 Terra/high，且无 provider/auth/base_url/secret/fallback。
5. 将 receipt 的 source revision、source/target hash 和 backup path 写进本 run metadata。

成功仅为 filesystem_projected；不得在此时报告 host_loaded 或 live acceptance。

### 6.2 设计审问多轮路径

1. 新开 Codex fresh session。保存 session/host 的 redacted identity 与 start timestamp。
2. 提交 S02 原始语句。记录 discovery 是否发生、被选 closure、design-griller child id、解析 model/effort、首问内容与 awaiting_user_answer。
3. 校验首轮只包含一个会改变方案决策的问题；不得同时输出结论、第二问、文件修改或 child replacement。
4. 用户给出真实答案。parent 只将答案转给同一个 child。
5. 记录续轮 child id 与首轮完全一致，并在决策确实收敛时记录 decision capsule。
6. receipt v2 中 skill_md_loading 只有在 host 能提供实际读入证据时才记 observed；child name/描述不是该证据。

### 6.3 单轮只读 runner 路径

1. 在独立 fresh Codex session 运行 S03。
2. admission 必须携带原始请求、完整 router validation、唯一 selected entry、validated closure、effective execution contract、requested_operation=read_only、empty exact write set、minimum proof、stop。
3. 记录 cold-capability-runner child id、Terra/high、completed 事件、输入/输出 evidence reference。
4. 最后用文件变更/工具 event 核对实际 write set 为空。任何写入、外部调用、第二候选或 contract mismatch 都是 fail。

### 6.4 可见直达对照

在 fresh session 运行 S01。记录 grill-me 的 native 交互事件，同时验证 cold_discovery=not_observed、candidate_load_validation=not_observed。它是避免“所有 explicit skill 都被 router”这一回归的对照。

### 6.5 隐式三正三负样本

CSR-R5 使用六个互不复用的 fresh-host session：

- 三个 cold 正例选自 S04/#1/#25/#28 的不同措辞。不要规定唯一候选；记录 host 判定、可用 domain hint、是否一次 discovery、候选集合、contract、结果和不确定性。#24 作为 visible multi-turn 直达对照，不计入 cold positive。
- 三个负例选普通解释、可见直达、纯 policy 讨论。若有 router/child/side effect，立刻 fail，不通过重写 prompt 掩盖。
- #12–#15/#19–#20 的 artifact 一律单独创建 run 目录并按对应 documents/pdf/presentations/spreadsheets/image 的 render/inspection contract 审核。冷路由 pass 不代表格式/视觉/公式 pass，反向亦然。

## 7. 失败分类与停止条件

| 发现 | 分类 | 当次行动 | 不要做什么 |
| --- | --- | --- | --- |
| catalog invalid、junction physical counterpart 缺失 | deterministic router failure | 保留 receipt，复现 focused test，定位 path/hash | 取消 reparse/containment |
| model/effort 非 Terra/high | deployment mismatch | 保存 child/config evidence，检查 source->target hash | 改 global default 或声称历史数据通过 |
| 503/auth/provider | host availability blocker | 记录 host-specific fail，停止当次 live acceptance | 重启/改 auth/provider 或将失败改为 not_applicable |
| child 不可观测 | observability blocker | assertion=not_observable，保留较低边界 | 由 parent prose 推断 child |
| multi-turn 被摘要 | contract violation | assertion=fail，检查 parent/bridge contract | 让 runner 给一次性结论 |
| unexpected write/external call | admission violation | 停止、保存精确 write/call evidence，走本次 rollback | 继续扩展 write set |
| target-bound 缺对象 | platform_na | 写 reason、alternative verification、recovery condition | 猜测 workbook/tab/URL 或操作别的目标 |

全局 stop：不 push、不发布、不扩展到完整 78 技能、不变更 provider/auth/config、不重启宿主。要继续任何上述操作都需要独立的当前授权。

## 8. 最终汇总模板

每个 run 的最终报告使用如下结构：

| 字段 | 内容 |
| --- | --- |
| Run / host | run id、host surface、fresh-session identity（脱敏） |
| Inputs | repo SHA、matrix SHA、bridge receipt SHA |
| Scenarios | 每项 expected、observed、assertion、evidence refs |
| Highest boundaries | 每项独立列出，禁止使用一个全局 live pass |
| Failed / not observable / platform_na | 原因、恢复条件、是否阻塞后续阶段 |
| Writes / rollback | 实际写入、backup paths、清理结果 |
| Scope held | 未运行的场景、未改的 host/provider/auth、未外推的技能范围 |

只有具备当前 Codex child id、model/effort、lifecycle、same-child 多轮或 zero-write runner 证据的场景可以写 host_specific_live_accepted。其他记录必须如实保留在其实际较低层。
