# 2026-08-04 Skill Profile Reconciliation Advisor Evidence

**program_id**: `skills-manager-vnext`

**track**: `profile_reconciliation_advisor`

**base_phase**: `P5`

**verification_level**: `repo_verified`

**P6_ADMISSION_STATUS**: `hold`

**live_acceptance**: `not_run`

## Authorization and problem

用户授权按建议自动自主连续执行。前序真实反馈已证明 lexical capability router 精度低于仅依赖宿主语义和 profile 的基线；native-first correction 已完成。本切片处理其后续缺口：skill 新增、删除或 metadata 变化后，profile membership 可能 stale、unrouted、重叠或超预算，但不能用关键词自动归类或静默修改配置。

实施起点为 clean `main...origin/main`，两端均为 `6f427584eb68bbe9f4a50d1ad2ab6ebbf6e4f14e`。本切片未发现或覆盖既有用户改动。

## Adopt / adapt / reject / defer

- adopt：Codex 官方 skill progressive disclosure、`name + description` 宿主语义匹配、有限 metadata budget、direct/negative prompt replay。
- adapt：将宿主语义结果压缩为带 `base_config_sha256` 的 proposal，由现有 projection core 校验。
- reject：skill 名称关键词/正则自动 profile 分类、第二个 LLM/embedding router、把全部 unrouted 自动加入 profile、静默 active profile 切换。
- defer：reviewed apply、host-native profile projection、真实维护净收益 pilot；均需独立授权和证据。
- community：沿用 native-first correction 已记录的 Agent Skills、Superpowers、OpenAI plugins revision/disposition；本切片未复制源码、未运行社区脚本、未安装插件。

官方依据来自 2026-08-04 刷新的 Codex manual：skill 初始暴露 `name + description`，选中后再加载完整内容；implicit invocation 依赖 description；初始 metadata 受有限预算；metadata revision 应以 direct/negative labelled prompts、precision/recall 和 replay 验证。官方页面入口：`learn.chatgpt.com/docs/build-skills.md`、`developers.openai.com/plugins/guides/optimize-metadata.md`、`developers.openai.com/plugins/concepts/skills.md` 与 `agentskills.io/specification`。

## Changes and write boundary

- product/planning：PRD 增加 `FR-SEL-013/014`、`NFR-SAF-003` 和 `MET-014`；架构增加 profile reconciliation 数据流与 `ADR-SMV-018`；路线图、索引、README、spec、manifest、plan/todo、AGENTS 同步。
- implementation：`New-SkillProfileReconciliationPlan` 复用 canonical/reachability/budget/policy；`skill-profile reconcile` 与 standalone script 只输出 JSON plan。
- tests：focused Pester 覆盖 current diagnostic、valid add/remove、stale hash、schema/owner、unknown、protected、conflict/no-op、reason、budget、stale reference 和 malformed JSON。
- generated：`skills.ps1` 仅由 `build.ps1` 从 `src/` 重建。
- no-write：未修改 `skills.json`、`agent/`、`vendor/`、imports、runtime reports、Codex config、provider/auth/model/sandbox/session/plugin/MCP 状态。

## Deterministic current-repository result

`scripts/plan-skill-profile-reconciliation.ps1 -Json -NoExit`：

```text
schema_version=1
decision_owner=host_ai
semantic_routing_performed=false
pass=true
apply_allowed=false
writes_performed=false
active_profile=default
unrouted_count=48
profile_count=16
overlap_observation_count=6
all_profiles_budget_pass=true
```

48 个 unrouted 和 6 个 overlap 只是当前观察，不是自动变更建议。低频 explicit/cold skill 保持 unrouted 可能是正确设计。

## Verification record

| Order | Command | Result |
| ---: | --- | --- |
| 1 | `pwsh ... -File build.ps1` | pass；生成 `skills.ps1` |
| 2 | Pester `SkillProjection.Tests.ps1,SkillProfileReconciliation.Tests.ps1` | 38/38 pass |
| 3 | `plan-skill-profile-reconciliation.ps1 -Json -NoExit` | pass；48 unrouted、16 profiles、6 overlaps、zero-write |
| 4 | `verify-skills-config.ps1` | pass；before/after hash 相同；1 个 legacy schema observation |
| 5 | `verify-skill-routing.ps1` | pass；default、findings=0 |
| 6 | `verify-skill-integrity.ps1` | pass；107 skills |
| 7 | `verify-capability-routing.ps1 -Json` | 27/27；semantic auto/negative/side-effect violations 均为 0 |
| 8 | `verify-vnext-planning.ps1 -Json` | pass；P5 5/5，0 finding |
| 9 | `verify-lean-ai-delivery-planning.ps1 -Json` | pass；maintenance 4/4，P6 hold，0 finding |
| 10 | `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | pass；所有 full stages 通过；`total_elapsed_ms=188168` |

## Truth boundary and rollback

本切片达到 `profile reconciliation advisor repo_verified`。这不证明 profile 已自动优化、宿主 proposal 普遍正确、reviewed apply 已实现、host loaded、M1 pilot 或 business `live_accepted`。

回滚只撤销本切片 manifest 声明的 source/script/test/docs/task/evidence，并由 `build.ps1` 重建 `skills.ps1`；不得覆盖 P0-P5、Lean maintenance、native-first correction 历史资产或任何用户/宿主配置。
