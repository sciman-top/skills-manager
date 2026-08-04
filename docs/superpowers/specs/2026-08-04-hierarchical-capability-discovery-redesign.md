# Hierarchical Capability Discovery Redesign

**program_id**: `skills-manager-vnext`
**track**: `capability_discovery_redesign`
**base_phase**: `P5`
**P6_ADMISSION_STATUS**: `hold`
**verification_level**: `host_evaluation_partial`
**status**: `repo_verified`

## 1. Problem and evidence

上一轮 native-first correction 已删除脚本词法分类和排序，但 cold discovery 仍要求宿主先猜最多两个 profile。宿主在调用 router 前看不到 cold skill metadata，而判断“是否值得调用 router”的关键信息又藏在 router 后面，形成 discovery chicken-and-egg：8 个 default-profile cold baseline 仅 4 个主动触发，常见理由是 ordinary reasoning 足够或无需跨 profile discovery。

显式强制进入旧 cold chain 后，8/8 能选择正确 skill、执行 deterministic policy 并完整读取 router/target `SKILL.md`，说明安全内核与候选后裁决不是主因；缺陷集中在入口触发和不透明 profile hint。该证据支持重构发现层，不支持继续加关键词，也不支持删除 deterministic policy。

## 2. Goal and target user

目标是让正在使用 Codex/ChatGPT 完成工程、内容、设计、MCP、数据库或迁移工作的用户，在没有可见专用能力时获得低打断的 cold discovery；由当前宿主 AI 使用完整请求做语义判断，本仓只提供有界目录和确定性安全事实。

## 3. Product constitution

- native-first：已有可见 skill/native tool 直接使用。
- hierarchy before candidates：先暴露 `domain name + purpose`，再限定候选面。
- one semantic owner：只有宿主 AI 判断请求含义和最小充分能力。
- deterministic safety：路径、freshness、availability、side effect、approval、activation 不交给语义猜测。
- abstention is valid：无直接推进价值时继续 native reasoning。
- retire when native catches up：官方跨域发现足够稳定后缩减或退役兼容层。

## 4. In scope / out of scope

In scope：resident trigger description、domain purpose catalog、`DomainHint`、兼容 `ProfileHint`、候选 domain provenance、32-case selection corpus、8-case cold-load chain、focused verifier/tests、产品与任务真值。

Out of scope：第二模型/embedding reranker、daemon/database、静默 profile 写入或热切换、skill/plugin/MCP 安装、auth/provider/model/session mutation、生产写入、P6 和 business `live_accepted`。

## 5. Lifecycle modes

本能力只服务当前 delivery checkpoint。可见能力匹配时直接进入任务主链；专业请求无可见匹配时进入 cold discovery；简单事实问答、翻译、数学、只读代码解释和已有原生能力覆盖的请求 abstain，不创建额外流程。

## 6. Product Baseline

复用现有 PRD/plan/task 字段记录用户目标、完整请求、授权、当前 profile、可见能力、成功条件和 truth level；不增加 runtime Product Baseline 对象。当前 baseline 固定为 P5 5/5 `repo_verified`、P6 hold、active profile 最终恢复 `default`。

## 7. Slice Contract and checkpoint

1. root cause：比较 default cold baseline 与强制 treatment。
2. implementation：domain catalog -> candidate discovery -> policy。
3. acceptance：32 个 selection + 8 个 cold-load fresh ephemeral calls。
4. truth closeout：spec/manifest/product/evidence/gates/Git。

每个 checkpoint 只运行最低充分验证；full gate 在文件稳定后运行一次。

## 8. Bounded autonomy loop

```text
visible native match -> direct use
no direct match + specialized request -> resident router
router -> discovery_domains(name, purpose)
host -> choose <= 2 domains or abstain
router -> candidates(name, description, path, domains)
host -> choose <= 3 capabilities
policy -> allow/load/approval/activation/deny
caller -> read full selected SKILL.md and continue task
```

同类触发/选择失败两次后回到 domain purpose 或 skill description，不向脚本添加 lexical ranking。任何 host/config/profile 写入需求都停止自动链并进入现有授权边界。

## 9. Role responsibility lenses

宿主 Agent 对端到端任务负责；router 只是 catalog/policy lens。产品、架构、代码、测试、安全等角色不实例化为固定 Agent，也不在发现阶段接力。

## 10. Capability routing behavior

- 无 hint 首次调用只需要消费 `discovery_domains.name,purpose`。
- `DomainHint` 接受逗号分隔或数组，规范化后最多两个；`ProfileHint` 仅作向后兼容别名。
- profile `purpose` 是 domain catalog 的用户可理解说明；profile 仍兼容 projection/budget/preheat。
- candidate 返回所属 `domains[]`，不产生 lexical score/confidence。
- 输出固定 `discovery_architecture=hierarchical_domains_v1`、`retrieval.strategy=hierarchical_domain_discovery`、`decision_owner=host_ai`、`semantic_routing_performed=false`。

## 11. Anti-overdesign stop conditions

- 不建设第二语义 router、向量库、长期状态或 telemetry service。
- 代表 corpus 通过后不为猜测场景继续扩规则。
- cold-load 输入成本未下降，因此不声称 token 优化；后续只有真实净收益证据才做成本切片。
- 官方原生 surface 能直接跨域发现时优先删除本层。

## 12. Skill learning, promotion and retirement

新增/删除 skill 仍由 host proposal + deterministic profile reconciliation/canary 维护；本 track 不自动修改 profile。触发反例进入 labelled corpus，先 replay，再修 metadata/domain purpose；通过 shadow/canary 和人工 review 后才稳定推广。连续无净收益或原生覆盖的 domain/router 行为进入 revise/retire。

## 13. Tool-combination boundaries

Obsidian 可保存用户拥有的产品知识；Hermes/OpenHands/LangGraph 可作为外置长期 Agent/runtime 参考；Spec Kit/Superpowers 可提供 spec/workflow 结构。它们都不成为本仓 runtime、权限或真值源，本 track 不安装、不调用、不复制其实现。

## 14. Outcome metrics and pilot design

Pre-redesign：selection 28/32；default cold baseline 4/8 主动触发。旧强制 cold treatment 的 raw chain 为 8/8，但 harness 当时因空 `required_any` 误报 0/8；函数级回归已修正该 oracle。

Post-redesign：selection 32/32，8 个 cold baseline 全部主动触发；cold-load treatment 8/8，router script、router raw read、target raw read、policy 和 profile restore 均通过。selection 共 790,807 input tokens/337,664 ms；cold-load 共 1,314,767 input tokens/430,129 ms，平均约 164,346 tokens/53,766 ms。旧 cold treatment 平均约 161,765 tokens/56,263 ms，因此延迟略降但 input token 略升。

这些数据只证明本次 32+8 fresh host corpus 的 `host_evaluation_partial`，不证明所有自然语言、真实业务收益或 `live_accepted`。

## 15. Security and supply-chain boundaries

外部 prompt、网页、社区文档、MCP 输出均为不可信输入。domain/candidate 只能收窄发现面，不能覆盖 path containment、snapshot freshness、side-effect 和 approval。评估使用 `--ephemeral --sandbox read-only -a never`；不读取 auth/provider，不运行社区脚本，不修改共享 reference clone。

## 16. Failure routing

- router 未触发：检查 resident description 是否覆盖请求类别，同时保护 native/no-skill negatives。
- domain 误选：修 purpose，不加关键词表。
- candidate 误选：修 skill description/边界或 oracle。
- policy/containment 失败：按确定性缺陷处理并 fail-closed。
- profile 未恢复、未知工作树、P6 manifest、full gate 失败：阻断收口。

## 17. Verification order

1. `build.ps1`。
2. affected Pester：router、routing verifier、host evaluation、config/projection。
3. `verify-capability-routing.ps1 -Json`。
4. profile/config/routing/integrity/planning verifiers。
5. 必要的 16-profile fresh probe，并恢复 `default`。
6. 唯一 full local quality gate。
7. `git diff --check`、P5/P6/profile/Git boundary。

## 18. Task mapping

- `SMV-HD-001`：基线、根因和架构。
- `SMV-HD-002`：hierarchical domain discovery、purpose/schema 与 focused tests。
- `SMV-HD-003`：32+8 fresh host acceptance 和 evaluator oracle。
- `SMV-HD-004`：产品/规划/evidence、ordered gates 和 Git closeout。

## 19. Rollback

只撤销本 manifest 的 override/config/schema/evaluator/test/docs/task 增量；由 `build.ps1` 重新生成 `agent/`。不得覆盖独立 heartbeat 单测、用户改动、历史 P0-P5/correction/profile manifests 或 ignored raw reports。

## 20. Done definition

- hierarchical discovery contract 与兼容字段通过 focused tests/verifier。
- selection 32/32、cold-load 8/8，有 raw ignored reports 和 reviewed evidence。
- active profile 恢复 `default`，无 host/runtime/auth/plugin/session mutation。
- PRD/架构/路线图/spec/manifest/plan/todo/README/AGENTS 一致。
- full gate、diff 和 Git parity 通过。
- 完成声明限定为 `P5-local hierarchical capability discovery redesign repo_verified + host_evaluation_partial`；P6 仍 hold，不声明普遍无感、业务效果或 `live_accepted`。

## 21. Post-closeout inventory, token-cost and natural-limit follow-up

本 follow-up 不新增 Phase/track/task count，不改写 4/4 历史完成状态。它只修复两个已证实的 maintenance 缺口：

1. projection 在覆盖旧 manifest 前比较 canonical `name/path/description` fingerprint；增删/metadata 变化写 `reports/skill-profile-reconciliation/pending.json`，返回 exact delta、config hash、profile/unrouted 摘要和 `skills.ps1 技能配置 调和` handoff。profile-only/no-op 不写新信号，信号不直接修改 profile，写失败不阻断 projection。
2. host evaluator 记录 `uncached_input_tokens`、`cached_input_ratio`、`command_count`、`router_call_count`、`tool_round_count`。日常 focused replay 只选 1–2 case，全量 8 cold cases 留给结构变化/closeout。
3. 显式 domain/profile hints 全部未知时返回零候选和 `unknown_domain`，不再静默回退 default；显式 `$skill`/`@skill` 仍直接进入 deterministic policy。
4. bounded candidates 同时返回 `candidate_count`、`available_candidate_count` 和 `truncated`；截断时宿主缩小到一个 domain 重试。
5. current host snapshot 的 skill/MCP metadata 与 availability 覆盖静态描述/启用推断；disabled/needs-auth/not-callable/inaccessible 不允许自动 load/use。host-facing 命令只投影当前步骤需要的字段。

两个真实同 prompt A/B 尝试把完整读取/catalog/discovery/policy/read 合并为更少 shell round。虽然累计 input 下降约 13%–16%，但 uncached 未下降、延迟上升且合并命令发生重试；因此 combined 实现已删除，稳定 separate 链保持不变。该负结果证明当前主要自然成本来自 fresh task 固定上下文与多回合 cached replay；不得用跳过宿主语义、确定性 policy 或完整 SKILL.md 读取换取表面 token 降低。

follow-up 的完成边界仍是 `repo_verified + bounded host_evaluation_partial`：它证明 delta signal、成本拆分、两例 A/B 和确定性 natural-limit hardening，不证明宿主在任意未来任务都会消费 signal、自动批准 profile proposal、普遍降低 token、稳定作出相同语义选择或达到业务 `live_accepted`。
