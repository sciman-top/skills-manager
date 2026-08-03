# 2026-08-04 Native-first capability routing correction evidence

**program_id**: `skills-manager-vnext`
**track**: `capability_routing_correction`
**base_phase**: `P5`
**status**: `repo_verified`
**verification_level**: `repo_verified`
**P6_ADMISSION_STATUS**: `hold`
**M1_PILOT_STATUS**: `pilot_not_executed`
**HOST_REPLAY_STATUS**: `host_evaluation_partial`
**LIVE_ACCEPTANCE_STATUS**: `not_run`

## 1. Authorization and problem

用户明确反馈 `capability-router` 在精准识别、正确调用 skills 上长期低于预期，甚至不如只使用 profiler；授权优先使用宿主 AI 原生语义，必要时彻底重构/退役 router，并要求以多类真实自然语言场景全面验证。用户同时要求保留“智能化、自动自主、无感无缝切换”，但不得把安装、认证、写入或破坏性动作隐藏化。

本切片归宿是 P5-local regression correction，不是 P6：保留 P5 5/5 历史 `repo_verified`，`P6_ADMISSION_STATUS: hold`，不创建 Phase 6 manifest；Lean Delivery M1 10-task pilot 未执行。

## 2. Worktree boundary

- baseline branch: `main...origin/main`
- baseline HEAD: `45e68d3e1d50bc4652c84157ffc3f392c33405a0`
- 初次检查只发现本 correction 已知的 router/profile/corpus/test/README/PRD 修改；未发现需回退的独立用户改动。
- `agent/` 为 generated output，不手改；最终由 `build.ps1` 从 `overrides/`/config 投影。
- 未修改 `imports/**`、`vendor/**`、provider/auth/sandbox/session/plugin 状态或宿主配置。

## 3. Pre-correction reproduction

使用当前投影脚本重放：

| Prompt | Observed |
| --- | --- |
| `请先理解这个仓库，设计模块化的工程终态、技术栈和架构边界，只给方案不要编码。` | `architecture_assessment`，未选择候选，不能证明正确设计能力调用 |
| `这个 Python CLI 在空配置时崩溃，请定位根因并修复；不要使用 .NET 专用流程。` | 错选 `debug:dotnet` |
| `不要调用任何 skill，也不要切换 profile，直接解释这段错误。` | 仍选 `debug:dotnet,debugging-and-error-recovery` |

根因：脚本把候选发现、lexical task/intent/domain、普通名称子串和安全策略合并；它看不到宿主完整推理，普通能力名即使位于否定句也会获得分数/显式选择资格。继续增加 negative keyword 只会扩大双重语义决策和维护面。

## 4. Target architecture

```text
visible metadata -> host AI semantic match -> direct native use
no match/discovery -> profile candidates -> host adjudication -> deterministic policy -> activation/native fallback
```

- semantic owner: `host_ai`
- router semantic work: `semantic_routing_performed=false`
- deterministic ownership: containment, freshness, availability, side effect, approval, activation, session reuse
- profile: bounded preheat at task boundary, never a permission boundary or silent hot switch
- no match: continue native reasoning; do not block main chain

该方案在当前约束下 Pareto-optimal：不增加第二次模型调用、daemon、数据库、凭据或额外 token；保留 cold discovery 与安全 policy；守住 8,000 字符 profile 预算；比全手工选择少打断。它不是永恒最优，官方原生 discovery/trace 覆盖或真实 replay 无净收益时继续 shrink/retire。

## 5. Official evidence

2026-08-04 使用 `openai-docs` helper 获取当前 Codex manual：

- source: [Codex manual](https://developers.openai.com/codex/codex-manual.md)
- local cache: `C:\Users\sciman\AppData\Local\Temp\openai-docs-cache\codex-manual.md`
- lines 19430-19456：ChatGPT/Codex 先看到 skill `name + description`，由宿主决定 explicit/implicit invocation；初始列表最多约 2% context 或 8,000 字符。
- lines 19576-19588：skill 应聚焦，优先 instructions，使用真实 prompts 验证 description 是否正确触发。
- lines 23518-23569：[Optimize Metadata](https://developers.openai.com/plugins/guides/optimize-metadata.md) 要求 direct/indirect/negative golden prompts、precision/recall、一次改一个 metadata 字段和 revision replay，negative precision 优先。

采纳：host-native metadata matching、progressive disclosure、真实 labelled prompts、负向 precision、只读/side-effect annotations。拒绝从这些文档推导“脚本关键词评分更可靠”或“repo corpus 等于 live acceptance”。

## 6. Community evidence and disposition

只读检查，没有继承外部仓指令、运行上游脚本或复制源码：

| Source | Revision / license | Disposition |
| --- | --- | --- |
| `agentskills` | `38a2ff82958afee88dadf4831509e6f7e9d8ef4e`, Apache-2.0 | adopt README 的 discovery(name/description) -> activation(full SKILL.md) progressive disclosure |
| `obra/superpowers` | `3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9` | adapt clean-session/real-prompt acceptance tests；adopt Codex native discovery；reject mandatory session bootstrap 和全任务强制流程 |
| `openai/plugins` | `11c74d6ba24d3a6d48f54a194cd00ef3beea18f9`, per-plugin | adopt plugin manifest/skills/MCP 分层；defer marketplace/install/runtime 管理 |
| Spec Kit / OpenHands / LangGraph / Hermes | 当前 reference shelf / 既有评估 | defer 到有真实 spec/runtime/long-state consumer；本切片不安装或集成 |

## 7. Write set

- source/config: `overrides/capability-router/**`、`overrides/custom-windows-wpf-teacher-app/SKILL.md`、`config/skill-routing-policy.json`、`config/capability-routing-golden.json`、`skills.json`
- verifier/tests: `scripts/verify-capability-routing.ps1`, `scripts/verify-codex-skill-profiles.ps1`, `tests/Unit/CapabilityRouter.Tests.ps1`, `tests/Unit/CapabilityRoutingVerifier.Tests.ps1`, `tests/Unit/SkillProjection.Tests.ps1`
- product/planning: PRD、架构、路线图、产品索引、correction spec/manifest、`tasks/plan.md`、`tasks/todo.md`、`AGENTS.md`
- user docs/evidence: `README.md`, `README.en.md`, 本文件
- generated projection: 仅由 `build.ps1` 生成的 `agent/capability-router/**`

## 8. Behavior changes

- 删除 lexical intent/task/domain/confidence/ranking；输出 `host_adjudicated`/`null`。
- `ProfileHint` 仅决定候选池；`Candidate`/`ExcludeCapability` 表达宿主裁决。
- 普通无 sigil 的 capability 名不自动选择；仅 `$name`/`@name` 或 caller `Candidate` 进入 policy。
- 保留 path containment、stale snapshot fail-closed、MCP availability、session reuse、operator approval、read-only auto-use。
- coding 增加 incremental implementation；engineering 聚焦产品/spec/计划/领域/架构/研究；database 增加 performance 并去除重复泛化 architecture 以满足预算。
- 首轮 host replay 发现 generic WPF dependency-injection debugging 过选 `custom-windows-wpf-teacher-app`；其 description 收窄为教师/课堂产品需求，并显式排除通用 WPF/.NET 错误、DI、构建和后端调试。

## 9. Verification results

| Command / check | Result | Boundary |
| --- | --- | --- |
| focused Pester `CapabilityRouter.Tests.ps1,CapabilityRoutingVerifier.Tests.ps1` | 15 passed, 0 failed | override discovery/policy and verifier contract |
| `scripts/verify-capability-routing.ps1 -Json` | 27/27 pass; semantic auto selection 0; negative violation 0; side-effect violation 0 | labelled repo corpus, not native model eval |
| pre-correction replay | 2 concrete negative violations reproduced | root-cause evidence, not a benchmark |
| 13-case `codex -a never exec --ephemeral --sandbox read-only` replay | 初始 harness 11/13；plan-only skill selection 正确但 plan assertion 错误；WPF generic-debug 存在真实过选 | self-reported activation；JSONL 无独立 skill-invocation event |
| targeted revision replay | plan-only corrected assertion pass；收窄 WPF skill metadata 后不再过选教师产品 skill | required/forbidden selection 汇总 13/13；证据仍为 `host_evaluation_partial` |
| WPF skill `quick_validate.py` | pass | skill structure/frontmatter only |
| `skills.ps1 构建生效` | pass；108 skills；13 overrides；受管 Junction 目标一致 | managed skill projection refreshed；provider/auth/model/sandbox/plugin/session 未修改 |
| `verify-codex-skill-profiles.ps1` after metadata revision | 16/16 fresh pass；restored `default` | visibility/budget only；dotnet 7944/8000, engineering 7739/8000, database 7579/8000 |
| skills config/routing/integrity verifiers | pass；routing findings 0；integrity verified 107 | repository/projection contracts |
| vNext + Lean planning verifiers | P5 5/5 done, findings 0；maintenance 4/4 done, findings 0 | P5/M0 planning truth only |
| first full gate attempt | unit 727 passed, 2 failed；E2E 18 passed | 发现旧 `SkillProjection.Tests.ps1` 仍锁定 profile 重组前的 coding count 与 engineering `draft-tickets` 常驻契约；门禁正确阻断收口 |
| focused profile-contract repair | `SkillProjection.Tests.ps1` 30 passed, 0 failed | 测试同步当前 spec/profile 真值；`coding` 包含 incremental implementation，`engineering` 以 planning skill 取代重复 ticket draft 常驻 |
| full quality gate after repair | unit 729 passed, 0 failed；E2E 18 passed, 0 failed；build/generated sync/integrity/routing/config/planning/doctor contracts 全部通过 | P5-local correction repository closeout；未执行 live action |

一次执行型 host pilot 在只读架构评审中超过 180 秒，被外层 timeout 终止；没有模型结果，不能算 pass/fail routing evidence。timeout 跳过了 wrapper `finally`，随后显式核对并恢复 `skills.json` 与 projection manifest 到 `default`；未 kill/restart Codex。

full gate 首次失败后按根因修复并完成必要复验；最终 diff/Git/remote parity 在提交推送步骤核对。失败重跑属于门禁修复，不是重复堆叠独立 full suite；未在 full 前后另行调用 `tests/run.ps1`。

## 10. Truth boundary

- P5 history: 5/5 `repo_verified`, unchanged.
- correction: 4/4 `repo_verified`; this proves repository discovery/policy/profile contracts, not universal host semantics.
- deterministic corpus: validates candidate/policy fixtures, not model semantics.
- profile probe: 16/16 fresh visibility/budget pass and restored default；不证明正确 invocation。
- host replay: `host_evaluation_partial`；13 类 required/forbidden selection 在 metadata revision replay 后满足，但实际完整 SKILL body invocation 不可从 CLI JSONL 独立观测。
- M1 pilot: `pilot_not_executed`.
- P6: hold; no Phase 6 manifest.
- business `live_accepted`: not run.

## 11. Rollback

Revert only files listed in the correction manifest. Restore source/config first, then run `build.ps1` to regenerate `agent/`; do not edit generated files directly. Preserve P0-P5 historical manifests/spec/evidence, maintenance-design assets, user imports/vendor/audit/MCP changes and all host-local auth/provider/plugin/session state.
