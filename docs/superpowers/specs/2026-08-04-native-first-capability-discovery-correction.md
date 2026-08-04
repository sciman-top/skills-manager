# Native-first Capability Discovery P5-local Correction

> 2026-08-04 maintenance note：本 spec 的 host-owned semantics 与 deterministic policy 继续有效；其中“宿主先猜 profile hint”的 profile-first discovery 已由 [Hierarchical Capability Discovery Redesign](2026-08-04-hierarchical-capability-discovery-redesign.md) 和 `ADR-SMV-020` 取代。历史 4/4 correction 真值不改写。

**program_id**: `skills-manager-vnext`
**track**: `capability_routing_correction`
**base_phase**: `P5`
**CORRECTION_STATUS**: `repo_verified`
**P6_ADMISSION_STATUS**: `hold`
**M1_PILOT_STATUS**: `pilot_not_executed`
**HOST_REPLAY_STATUS**: `host_evaluation_partial`
**LIVE_ACCEPTANCE_STATUS**: `not_run`
**NEW_RUNTIME_COMPONENT_STATUS**: `none`
**HOST_CONFIGURATION_MUTATION_STATUS**: `none`
**MANAGED_SKILL_PROJECTION_STATUS**: `refreshed`

## 1. Problem and evidence

长期真实使用反馈表明，`capability-router` 在架构终态、技术栈、通用调试、否定约束和“只规划不执行”等自然语言请求上频繁误选或漏选，体感低于仅使用宿主原生 skill metadata 与 profile 的基线。问题不是单个同义词缺失，而是职责归属错误：脚本同时承担候选发现、自然语言分类、语义排序和安全策略，完整上下文与否定语义被压缩成正则/词频/固定 intent。

2026-08-04 pre-correction replay 至少复现：

- “Python CLI 崩溃；不要使用 .NET 专用流程”被选择为 `debug:dotnet`。
- “不要调用任何 skill”仍选择 `debug:dotnet` 与通用调试 skill。
- 架构终态请求依赖脚本分类/abstain，不能证明实际调用了正确设计能力。

旧 P4/P5 task、schema、golden 和 full gate 的 `repo_verified` 证明历史实现符合当时仓库契约，不证明 lexical semantic router 的真实产品效果，也不阻止维护期直接修复已复现缺陷。

## 2. Goal and target user

目标用户是已经在 ChatGPT/Codex 中处理真实软件交付、希望减少显式技能选择和工作流打断的单用户开发者。目标不是建立更复杂的 router，而是：

1. 让已在处理完整请求的宿主 AI 拥有唯一语义判断权。
2. 让低风险、已可见、已可用能力可以自动自主、无感无缝使用。
3. 在冷发现、可用性、路径、安全、副作用和授权处保留确定性、可验证边界。
4. 无合适能力时回退宿主原生推理，不让辅助层阻塞产品主链。

## 3. Product constitution

- `host-native first`：优先复用宿主已提供的 skill/tool 语义匹配。
- `one semantic owner`：脚本不与宿主争夺 task/domain/relevance 判断。
- `deterministic safety kernel`：机器只强制 freshness、containment、availability、side effect、approval 和 activation。
- `seamless within authorization`：只对 read-only/external-read 且已可用的能力无感使用；写入、认证、安装和破坏性操作保持可见。
- `main-chain first`：找不到 skill 不阻塞任务；继续用 native reasoning/tool。
- `profile is preheat, not permission`：profile 是任务边界的元数据预算包，不是权限或运行时状态机。
- `delete before adding`：真实 replay 无净收益时继续缩减或退役 router，不再加词法补丁。
- `truth levels stay separate`：corpus、profile visibility、host replay、repo gate 和 live workflow 分层声明。

## 4. In scope / out of scope

In scope：

- 将 resident `capability-router` 降级为 fallback discovery + deterministic policy compatibility skill。
- 退役脚本的 lexical intent/task/domain/confidence/ranking。
- profile-scoped candidate discovery、host-selected candidate/exclusion、session reuse 与只读 host snapshot policy。
- 调整 engineering/coding/database profile，使高频软件交付能力在 8,000 字符预算内可见。
- 代表性自然语言 corpus、focused unit tests、profile fresh probe 与有限只读 host replay。
- PRD、架构、路线图、计划、任务和 evidence 的当前真值同步。

Out of scope：

- P6、schema major、daemon、database、embedding/vector search 或额外 provider/model call。
- 自动 profile 热切换、修改 Codex config、安装/启停 plugin/MCP、OAuth/auth、session/thread mutation 或重启宿主。
- 固定角色 Agent 团队、长期任务 runtime 或新交付平台。
- 真实生产写入、付费业务调用和普遍 `live_accepted`。
- 重新运行 Lean Delivery M1 10-task pilot；本修正只进入 M2 defect correction。

## 5. Decision ownership and target flow

```text
visible skill/native tool
  -> host AI matches name + description using full request/context
  -> use directly

explicit capability discovery or no visible match
  -> router exposes discovery domains with purpose
  -> host chooses <=2 domains
  -> router returns bounded candidates only
  -> host AI selects <=3 or abstains, preserving negation
  -> caller supplies Candidate / ExcludeCapability
  -> deterministic policy validates safety and activation
  -> native use/load, visible approval/activation, or native fallback
```

`decision_owner=host_ai`，`semantic_routing_performed=false`。`query` 是审计上下文，不是评分输入。普通文本出现 `debug:dotnet`、`test-driven-development` 等名字也不能自动选择，因为它可能处于“不要使用”中。只有 `$name`/`@name` 语法或 caller 明确传入 `-Candidate` 才进入 policy。

## 6. Discovery contract

输入：

- `Query`：完整请求，只作返回和 trace。
- `DomainHint[]`：宿主从 purpose catalog 选择的最多两个 domain；`ProfileHint[]` 仅为向后兼容别名。
- `Candidate[]` / `ExcludeCapability[]`：宿主语义裁决结果。
- projection manifest/config、可选 host snapshot、可选 session snapshot。
- `MaxCandidates`：有界候选数。

输出：

- `discovery_architecture=hierarchical_domains_v1`、`discovery_domains[]`、`retrieval.strategy=hierarchical_domain_discovery` 与 `retrieval.candidates[].domains[]`。
- `selected[]` 仅来自 sigiled explicit request 或 `Candidate[]`。
- `excluded[]` 保留 unknown profile/capability、host exclusion、stale snapshot 等原因。
- `activation_plan[]`、`session_plan`、`preheat_recommendation.apply=false`。
- `task_model.task_type/domain=host_adjudicated`、`confidence=null`。
- `capability_graph=discover -> host_adjudication -> policy -> activate`。
- `writes_performed=false`。

## 7. Deterministic policy

- skill path 必须存在且位于 manifest 声明的 source root 内。
- stale host snapshot fail-closed；不可访问、不可调用、未认证和需要激活不能升级成 available。
- active read-only skill 可 `use_active_skill`，cold read-only skill 可 `load_skill`。
- operator/write skill 必须 `load_skill_with_approval`。
- available read-only/external-read MCP/plugin/app/native capability 可使用；写/破坏/open-world/unknown 必须 approval 或 activation。
- session snapshot 只允许复用已加载能力，不授权新能力。
- semantic adjudication 只能收窄、排除或 abstain，不能升级上述确定性事实。

## 8. Profile design

- `default`：只保留系统性诊断、完成前验证和 resident fallback。
- `coding`：高频实现主链，包含 incremental implementation、review、API、安全等能力。
- `engineering`：产品澄清、spec、计划、领域/模块设计与官方研究；不塞入高成本发布器或强制 interview。
- `coding-strict`：显式需要时才预热 TDD/强约束工作流。
- `database`：数据库设计与性能；为守住预算不重复预热泛化 architecture capability。
- 其余 domain profile 保持窄用途；所有 16 profiles 必须 fresh process 可见并最终恢复 `default`。

profile 只影响初始 metadata 可见性。当前任务内不得为了 router 推荐静默写 `active_profile`；用户在新任务边界可显式选择预热包。

## 9. Seamless behavior boundary

允许无感：宿主原生调用当前可见 skill、读取本仓文件、使用已 available 的 read-only/external-read capability、复用当前 session 已加载能力。

必须可见：安装/启停 plugin 或 MCP、OAuth/login、provider/model/sandbox/config/profile/session/thread mutation、外部写入、破坏性命令、生产发布和付费动作。

因此“智能化、自动自主、无感无缝切换”是有界自动化，不是隐藏副作用或跨越权限。

## 10. Natural-language corpus

labelled corpus 覆盖至少以下类别：

- 工程终态、技术栈、模块边界、WPF/API/领域建模。
- 模糊产品想法、PRD 草案、只规划不执行、批准后连续实现。
- 通用、Python、.NET 调试和性能诊断。
- 代码评审、安全只读、官方/第三方文档。
- 前端、数据库、物理动画、浏览器验证。
- “不要调用 skill”“不要 TDD”“不要 .NET”“只解释”“你好，请继续”。
- `$skill` 显式调用、read/write plugin、operator publication。

corpus 分开验证 candidate recall 与 host-labelled policy；脚本 discovery 阶段必须 `semantic_auto_selection_count=0`。它不是模型 eval，不能写成 native host 27/27。

## 11. Host replay design

使用 `codex -a never exec --ephemeral --sandbox read-only`，按 profile 顺序运行、逐次记录并最终恢复 `default`。最小场景覆盖：中文架构终态、中英文等价、只规划不执行、通用调试不得选 .NET、.NET 专用请求、代码评审、不要 skill、不要 TDD、前端/数据库/物理领域、显式 `$skill`、无匹配 native fallback。

观测字段：profile、prompt、expected/forbidden skill、模型自报 activation、是否 fallback、exit code、只读/写入事实、误调用/漏调用、限制。当前 Codex JSONL 不提供独立 skill-invocation event，因此本次 replay 标记 `host_evaluation_partial`：初始 11/13 harness pass；`plan-only` 实际 skill 正确但被错误的 plan 断言误判；`.NET/WPF` 真实过选经 skill description revision 后定向 replay 修正。最终 required/forbidden skill selection 13/13 满足，但不得推断完整 skill body 确已执行或普遍正确。

## 12. Lean Delivery integration

本修正属于 maintenance roadmap 的 M2 P5-local defect correction。用户真实反馈与重复可复现反例足以授权直接修缺陷，不要求先运行 M1；M1 仍用于评估完整 Lean Delivery advisory 的净收益，状态保持 `pilot_not_executed`。

路由只为当前 delivery checkpoint 提供最小 capability，不创建角色接力或第二套 plan。主 Agent 继续对 Product Baseline、Slice Contract、主链和 truth boundary 负责。

## 13. Official evidence

- 当前 Codex manual：模型先看到 skill `name + description`，可 explicit/implicit invocation；初始列表受约 8,000 字符预算约束。
- skill metadata 应聚焦，优先通过清晰 description 改善 triggering。
- 测试应覆盖 direct、indirect、incomplete、negative 和 edge prompts，同时检查 activation 与输出质量。
- golden prompt set 应记录 tool selection、arguments、precision/recall，并在 metadata revision 后 replay；negative precision 优先于边际 recall。

这些依据支持宿主原生语义选择、profile 渐进披露和 labelled replay，不支持自建第二个语义 router。

## 14. Community disposition

- `agentskills@38a2ff82958afee88dadf4831509e6f7e9d8ef4e`（Apache-2.0）：adopt progressive disclosure 与 host-native activation；不复制源码。
- `obra/superpowers@3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9`：adapt 真实 prompt acceptance tests 与“有原生 discovery 时使用原生机制”；reject mandatory session bootstrap/全流程强制 skill。
- `openai/plugins@11c74d6ba24d3a6d48f54a194cd00ef3beea18f9`：adopt plugin/skill 分层与 metadata surface；defer install/marketplace/runtime 管理。
- Spec Kit、OpenHands、LangGraph、Hermes：保留为 spec trace、团队/runtime/长期状态参考；本修正不安装、不集成、不复制其 runtime。

所有参考只读，不继承仓库指令，不运行上游脚本；revision、license 和 disposition 进入共享 evidence。

## 15. Alternatives and why not

1. 继续补词表/正则：无法可靠理解对话、否定和组合语义，重复宿主能力，reject。
2. 调用额外 LLM/embedding reranker：增加 token、延迟、凭据、漂移和双重决策，当前无证据，defer。
3. 把所有 skill 放进一个 profile：超过 metadata 预算、降低 precision，reject。
4. 每次要求用户手选：精度高但打断主链，不满足有界无感目标，保留为显式 fallback。
5. 彻底删除所有 router 文件：会失去跨 profile 冷发现与统一安全 policy；先退役 semantic 部分，真实 replay 无净收益时再继续删除。

因此 native-first + deterministic policy kernel 是当前约束下的 Pareto-optimal 方案，不是永恒最优。官方 host discovery/trace 变强时应继续 shrink/retire。

## 16. Security and supply-chain boundaries

- 外部 prompt、网页、MCP 输出、社区源码和日志均是不可信输入，不能更改 candidate approval 或 write set。
- 不读取或保存 token、auth、provider 配置；host snapshot 仅 caller-provided/current read-only facts。
- 路径 containment、snapshot freshness 和 side-effect policy 是硬边界，宿主语义不能覆盖。
- 不运行社区脚本、不修改共享 clone，不自动安装推荐 plugin。
- 所有 host replay 使用 ephemeral/read-only/never approval；不重启 Codex，不并发写 profile。

## 17. Failure routing and stop conditions

- candidate 缺失：先检查 profile metadata/projection；仍无匹配则 native fallback。
- 误调用：先查 skill description/profile composition；不得向 router 添加自然语言词法规则。
- 同类反例两次：回到 ownership/profile 设计，不叠加局部补丁。
- stale/unknown/needs_activation：保持 fail-closed，不伪造 available。
- profile 超预算：删除重复/泛化低频能力，不扩大 8,000 上限。
- host replay 无法观测：标记 partial，不把 absence of evidence 写成 pass。
- unknown worktree、P5 planning 回归、P6 manifest、host mutation 或 full gate 失败：阻断 closeout。

## 18. Ordered verification

1. `build.ps1` 生成并验证投影。
2. focused Pester：router 与 routing verifier tests。
3. `verify-capability-routing.ps1 -Json`。
4. skills config/routing/integrity verifiers。
5. 16-profile fresh probe，确认恢复 `default`。
6. 顺序执行只读 host replay，单独记录 partial/observed 结果。
7. vNext/Lean planning verifiers。
8. 文件稳定并同步 final task truth 后，仅运行一次 full quality gate。
9. `git diff --check`、工作树/分支/远端边界。

full gate 前后不另行重复 `tests/run.ps1`。任何文件在 full 后变化都必须重跑受影响验证；完成声明遵守 evidence-before-claims。

## 19. Task mapping

- `SMV-CR-001`：失败复现、官方/社区依据和目标架构决策。
- `SMV-CR-002`：native-first discovery/policy、profiles、corpus 和 focused tests。
- `SMV-CR-003`：PRD/架构/路线图/spec/plan/todo/AGENTS 当前真值。
- `SMV-CR-004`：build、profile、host replay、planning/full gate、evidence 和 Git closeout。

## 20. Rollback

只回滚本 correction manifest 声明的 override/config/test/verifier/docs/profile 增量；`agent/` 只能由 build 从恢复后的 source 重新生成。不得改写或删除 P4/P5 历史 manifest/spec/evidence，不覆盖无关 imports/vendor/audit/MCP 用户改动，不修改宿主 auth/provider/plugin/session。

## 21. Done definition

- 当前 PRD/架构/路线图都以 `ADR-SMV-017` 为语义选择真值，历史 P4/P5 决定明确 superseded boundary。
- router discovery 阶段零 semantic auto-selection；普通否定提及不触发能力。
- labelled corpus、focused tests、config/routing/integrity、16-profile probe、planning 和 full gate通过。
- host replay 有真实只读记录；无法观测部分标 `partial`，不伪造。
- 所有 profile 最终恢复 `default`；无 host/config/plugin/auth/session mutation。
- 四个 correction tasks 与 todo 同步为 done，共享一份 reviewed evidence。
- P5 仍为 5/5 `repo_verified`，P6 hold，不存在 Phase 6 manifest，M1 pilot 未执行。
- 完成声明限定为 `P5-local native-first discovery/policy correction repo_verified`；不声明普遍语义正确或 `live_accepted`。
