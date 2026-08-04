# Host skill selection effectiveness and hierarchical cold discovery

**date**: 2026-08-04
**program**: `skills-manager-vnext`
**track**: `capability_discovery_redesign`
**base phase**: P5 5/5 `repo_verified`
**P6 admission**: `hold`
**truth level**: `repo_verified + host_evaluation_partial`

## 1. Authorization and problem

用户长期观察到 capability-router 误识别、漏调用和过度治理，明确授权重新设计/重构，并要求用多类别中英文真实自然语言全面实跑。目标不是让脚本代替宿主语义，而是验证 `host-native semantic selection + cold discovery + deterministic policy + full SKILL.md load` 是否能形成有界自动闭环。

## 2. Root cause

旧 correction 已删除 lexical ranking，但仍要求宿主先提供 profile hint。default profile 看不到 cold skill metadata，宿主又需要先知道 cold capability 值得发现才会调用 router，形成信息循环。重构前 8 个 default cold baseline 只有 4 个主动触发；漏触发覆盖 existing marketing-copy editing、technical proposal coauthoring、domain modeling、modern Python migration。

强制 treatment 的 raw chain 为 8/8：目标 skill、router script、router 全文读取、target 全文读取和 deterministic policy 均正确。这把根因定位到 trigger/profile-first entrance，而不是 policy kernel。

## 3. Architecture decision

```text
visible skill/native tool -> direct use
no direct match + specialized request
  -> resident capability-router
  -> discovery_domains(name + purpose)
  -> host chooses <= 2 domains
  -> candidates(name + description + path + domains)
  -> host semantic adjudication
  -> deterministic containment/freshness/availability/side-effect policy
  -> full selected SKILL.md read
```

profile 保留为 domain/index partition、projection/budget/preheat compatibility surface；不做当前 turn 热切换，不静默改 `active_profile`。

## 4. Write set

- Runtime source/config：`overrides/capability-router/**`、`skills.json`、`config/skills.schema.json`。
- Verifier/evaluation：`scripts/verify-capability-routing.ps1`、`scripts/evaluate-host-skill-selection.ps1`、`config/host-skill-selection-evaluation.json`。
- Tests：`tests/Unit/CapabilityRouter.Tests.ps1`、`tests/Unit/HostSkillSelectionEvaluation.Tests.ps1`。
- Product/planning：PRD、architecture、roadmap、product index、README、AGENTS、spec、manifest、plan、todo、本 evidence。
- Generated `agent/` 只由 build/projection flow 生成，未手改；raw host reports 留在 ignored `reports/host-skill-selection-acceptance/`。

独立边界：`tests/Unit/WatchInterruptedTask.Tests.ps1` 在本切片实施后作为未知、无关的未跟踪改动出现；本切片不修改、不回滚、不暂存该文件。

## 5. Official and community basis

- OpenAI Codex/Skills 当前模型：初始只暴露 skill `name + description + path`，选中后才读取完整 `SKILL.md`；initial catalog 有上下文预算。Adopt progressive disclosure、focused trigger description 和 host-native semantic selection。
- OpenAI execution plans/evals：adapt labelled positive/negative/edge prompt replay、tool selection/arguments 与 truth boundary；不把模型分数作为唯一硬门禁。
- Agent Skills / OpenAI plugins：adopt metadata-first discovery 和 plugin/skill 分层；不复制 runtime。
- obra/superpowers：adapt behavior acceptance 与 evidence-before-claims；reject mandatory bootstrap/TDD/role conveyor。
- Spec Kit、OpenHands、LangGraph、Hermes、Obsidian：defer 为外置 spec/runtime/knowledge 组合参考；不安装、不成为本仓真值。

## 6. Implementation and regression details

- 增加 `DomainHint`、`discovery_architecture=hierarchical_domains_v1`、`discovery_domains[]`、`retrieval.strategy=hierarchical_domain_discovery` 和 candidate `domains[]`。
- 为全部 16 profiles 增加 `purpose`，schema 保持可选兼容。
- `ProfileHint` 继续兼容；逗号字符串和数组最多规范化为两个 hint。
- resident description 明确 cold professional positives 与 factual/translation/math/read-only explanation/native negatives。
- 一次 projection build 因 router description 令 `dotnet=8007/8000` 失败；构建器自动回滚生成目录和 cache。压缩 description 后在不提高预算上限的情况下通过。
- evaluator 曾把缺失 `required_any` 变成空字符串，导致 raw chain 8/8 却 report 0/8；过滤空白 alternative，并用抽取的真实函数做回归测试。旧报告顶层 `pass=false` 不作为准确率证据，只引用 raw `chain_passed=8`。

## 7. Fresh host acceptance

| Run | Mode | Result | Tokens / duration | Truth |
| --- | --- | --- | --- | --- |
| `20260804-162419-461` | pre-redesign cold treatment | raw chain 8/8；旧 oracle 顶层误报 | 1,294,123 input；450,102 ms | baseline/raw-chain only |
| `20260804-171325-247` | post-redesign selection | 32/32；8/8 cold baselines 主动触发 | 790,807 input；337,664 ms | host_evaluation_partial |
| `20260804-172034-406` | post-redesign cold-load | 8/8；router script/raw read、target raw read、policy、restore 全通过 | 1,314,767 input；430,129 ms | host_evaluation_partial |

32 selection cases 为 16 中文/16 英文，覆盖 direct、indirect、negative、ambiguous、architecture/stack/end-state、multi-intent/cross-profile、side-effect/authorization、native/no-skill。8 cold-load cases覆盖 Python tests、文案编辑、技术提案、UI review、domain model、Python migration、.NET architecture 和 MCP builder。

成本结论：cold-load 平均时延约从 56,263 ms 降至 53,766 ms（约 -4.4%），平均 input tokens 从 161,765 增至 164,346（约 +1.6%）。所以准确触发/链路 corpus 有改善，token 成本没有改善。

## 8. Verification record

已完成的 focused evidence：

- `CapabilityRouter.Tests.ps1`: 14/14。
- `HostSkillSelectionEvaluation.Tests.ps1`: 5/5。
- `verify-capability-routing.ps1 -Json`: 27/27，0 findings。
- post-redesign selection：32/32。
- post-redesign cold-load：8/8。

Closeout verification：

- `build.ps1`：pass。
- affected Pester（router、routing verifier、host evaluator、schema、projection）：60/60。
- `verify-capability-routing.ps1 -Json`：27/27，0 findings；semantic/negative/side-effect violations 均为 0。
- config/integrity contracts：0 findings，107 skills verified。
- P5 planning：5/5；Lean maintenance planning：4/4。
- 16-profile fresh loading probe：16/16，最终恢复 `default`；最紧预算 dotnet 7960/8000。
- 唯一 full quality gate：Unit 757/757、E2E 18/18，全部 contract/hygiene/generated-sync 通过，总耗时 194,651 ms。该 Unit 总数包含并存独立 heartbeat 切片的 4 个测试，本功能 focused 证据仍以上述 60/60 为准。
- 完成态同步后按风险只重跑 planning/static/Git boundary，不重复 full suite。

## 9. Truth boundary

可声明：当前仓实现了 host-native semantic selection + hierarchical cold discovery + deterministic policy 的 P5-local 实现，并在 32+8 代表性 fresh ephemeral host corpus 中获得 `host_evaluation_partial` 证据。

不可声明：所有自然语言 100% 正确；宿主静默优化/切换 profile；profile 是 Codex 原生热切换；token 成本下降；真实产品交付效率提升；business `live_accepted`；P6 admitted。

## 10. Rollback

按 manifest write set 撤销本 track 的 override/config/schema/evaluator/test/docs/task 增量，再运行 `build.ps1` 重建 generated projection。保留 P0-P5、历史 correction/profile manifests/evidence、ignored raw reports和独立 `WatchInterruptedTask.Tests.ps1`；不得覆盖 auth/provider/plugin/session 或用户文件。
