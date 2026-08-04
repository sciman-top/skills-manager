# Skill Profile Reconciliation Advisor Maintenance Design

**program_id**: `skills-manager-vnext`

**track**: `profile_reconciliation_advisor`

**base_phase**: `P5`

**P6_ADMISSION_STATUS**: `hold`

**implementation_scope**: `repo_side_plan_only`

**live_acceptance**: `not_run`

> Historical boundary: this track remains the repo-verified zero-write advisor. The separately versioned `profile_optimization_canary` track consumes its validated proposal and adds an explicitly tokened non-active-profile canary; this document's plan-only evidence is not rewritten as apply evidence.

## 1. Problem and evidence

native-first routing correction 已把自然语言语义所有权归还宿主 AI，但 skill 新增、删除或 description 变化后，`skills.json.skill_projection.profiles.*.enabled_names` 仍需维护。当前 projection 能 fail-closed 检查失效引用和预算，也能报告 `unrouted`，但没有统一入口把这些事实组织成可审阅的 maintenance plan。人工直接编辑容易漏掉 stale、预算、alias/resident/system 边界；按 skill 名称自动归类又会恢复已经证明效果不佳的 lexical router。

当前真实仓基线：`active_profile=default`，16 个 profile 预算通过，存在 48 个 `unrouted`。这些数量是 2026-08-04 的当前诊断输入，不是“48 个都应加入 profile”的产品结论；低频技能保持 explicit/cold use 可能是正确状态。

## 2. Goal and target user

为维护 skills-manager 的高级用户和宿主 Agent 提供一个 network-free、zero-write 的 profile reconciliation advisor：自动发现确定性 drift，接收宿主基于完整语义作出的窄 proposal，输出可复核的精确 change-set，避免静默配置变化和第二套路由器。

## 3. Product constitution

- 宿主 AI 拥有语义归属；仓库只拥有 inventory、freshness、预算、冲突与安全 policy。
- `unrouted` 是观察，不是错误；overlap 是 review signal，不是自动删除授权。
- plan 与 apply 分离；本 track 只实现 plan。
- profile 是 metadata 预热包，不是权限、安装状态或当前任务热切换机制。
- 原生能力增强时继续 shrink/retire 本 advisor。

## 4. In scope / out of scope

In scope：复用 canonical projection；诊断 stale profile/resident 引用、unrouted、全部 profile budget、三 profile 以上 overlap；解析 host proposal；校验 config hash、对象存在性、protected skill、add/remove/no-op、理由、动作上限、预算和 routing policy；输出 stable JSON；CLI 薄入口、Pester、产品/规划/evidence。

Out of scope：关键词/embedding/LLM router、provider call、daemon/database、修改 `skills.json`、自动 apply、active profile 切换、安装/删除 skill、host config/plugin/MCP/auth/session mutation、P6、M1 pilot、业务 live acceptance。

## 5. Ownership and input contract

proposal schema：

```json
{
  "schema_version": 1,
  "decision_owner": "host_ai",
  "base_config_sha256": "<current skills.json sha256>",
  "changes": [
    {
      "skill": "example-skill",
      "add_profiles": ["engineering"],
      "remove_profiles": [],
      "reason": "Host used the full skill description and profile purpose."
    }
  ]
}
```

`reason` 是审阅依据，不参与代码语义评分。proposal 最多 50 个 skill change；同一 skill 不得重复，单项必须至少有一个 add/remove。

## 6. Current diagnostics

planner 先复制 projection 配置并移除 profiles/active/resident/aliases，重建 canonical inventory；随后以原配置检查：

- profile/resident 指向不存在 canonical skill。
- 非 system、非 alias、非 resident 且不属于任何 profile 的 `unrouted_names`。
- 每个 profile 的 skill metadata、external reserve/actual 和 budget verdict。
- 同一 skill 显式属于三个及以上 profile 的 overlap observation。
- routing policy enforce finding。

诊断不根据名字、description 关键词或 corpus 自动给出 profile。

## 7. Deterministic validation

- proposal schema 必须为 1，`decision_owner` 必须为 `host_ai`。
- `base_config_sha256` 必须等于当前 `skills.json` 文件 SHA-256。
- skill 必须是 canonical；profile 必须存在。
- system、resident 和 alias skill 禁止 proposal mutation。
- add/remove 不得重叠；add-existing、remove-missing 均 fail-closed。
- reason 非空；change 数量有界；同一 skill 只能出现一次。
- proposed `active_profile` 必须与 current 完全相同。
- proposed projection 必须可构建，全部 profile budget pass，routing policy 不得 blocking。

## 8. Output contract

```text
schema_version=1
command=plan-skill-profile-reconciliation
decision_owner=host_ai
semantic_routing_performed=false
pass=<deterministic verdict>
apply_allowed=false
writes_performed=false
config_sha256
proposal_supplied
current { active_profile, unrouted_names, profile_budgets, all_profiles_budget_pass }
actions[] { operation, skill, profile, path, before, after, reason }
proposed
overlaps[]
finding_count/findings[]
```

## 9. CLI and script behavior

- `skills.ps1 skill-profile reconcile`：当前诊断 JSON。
- `skills.ps1 skill-profile reconcile <proposal.json>`：proposal dry-run JSON。
- `scripts/plan-skill-profile-reconciliation.ps1 -ProposalPath <path> -Json [-NoExit]`：独立入口。
- pass exit 0；blocking finding exit 2；`-NoExit` 保留 JSON 供测试/调用方消费。

不提供 `--apply`，避免一个看似方便的参数绕过 reviewed write seam。

## 10. Bounded autonomy loop

```text
inventory change
  -> advisor diagnostic
  -> host reviews descriptions and proposes minimum changes
  -> deterministic planner
  -> if blocked: host revises once from finding codes
  -> if same issue fails twice: stop and reconsider profile purpose/budget
  -> reviewed apply remains separate and not implemented here
```

## 11. Anti-overdesign stop conditions

- 不为 48 个 unrouted 机械创建 profile 或 membership。
- 不新增第二套 profile schema、database、telemetry、background watcher 或 skill lifecycle daemon。
- 不把 overlap count 变成硬阈值；只有预算和确定性完整性是 blocking。
- 不因未来 apply 可能需要事务而现在实现 apply framework。
- focused unit tests 覆盖每类风险即可，不叠加同义 E2E fixture。

## 12. Security and supply-chain boundaries

proposal 和 skill metadata 均视为不可信输入；reason 不能覆盖 deterministic policy。planner 不读 auth/provider/token，不访问网络，不执行 skill 内容或社区脚本。输入路径只用于读取显式 proposal；输出不持久化。外部 system/plugin metadata 仍只通过现有 projection inventory 进入预算。

## 13. Official and community basis

当前 Codex manual 表明宿主先看到 skill `name + description`，模型可 explicit/implicit invocation，初始 metadata 受有限上下文预算约束；metadata 优化应以真实 direct/negative prompts 和 precision/recall replay 验证。这支持“宿主语义 + repository deterministic budget”，不支持关键词自动归类。

社区参考继续沿用 native-first correction 的 disposition：Agent Skills progressive disclosure adopt；Superpowers 的真实 prompt acceptance tests adapt；OpenAI plugins 的 metadata 分层 adopt；OpenHands/LangGraph/Hermes 的 runtime/long-state design defer。本 track 不安装、不复制上游源码。

## 14. Failure routing

- stale hash：重新运行诊断并由宿主基于新 inventory 生成 proposal。
- stale profile reference：先恢复/移除真实配置引用；本 planner 不猜替代 skill。
- unknown/protected/no-op/conflict：修正 proposal，不放宽规则。
- budget exceeded：减少 proposed membership 或优化真实 description；不提高 8,000 ceiling。
- routing policy blocking：回到 policy/profile 设计，不通过 bypass。
- 同一 finding 两次：停止局部 proposal，重新确认 profile 目的和是否应保持 unrouted。

## 15. Verification order

1. `build.ps1`。
2. `SkillProfileReconciliation.Tests.ps1`。
3. 当前仓 `plan-skill-profile-reconciliation.ps1 -Json -NoExit`。
4. capability/config/routing/integrity 与 planning contracts。
5. 文件稳定后一次 full quality gate。
6. `git diff --check`、P6 manifest absence、active profile default、Git parity。

full gate 前后不重复完整 `tests/run.ps1`。

## 16. Task mapping

- `SMV-PR-001`：产品/架构/spec 与 owner boundary。
- `SMV-PR-002`：pure planner、CLI/script 和 negative tests。
- `SMV-PR-003`：产品索引、README、plan/todo/AGENTS 与 manifest。
- `SMV-PR-004`：ordered verification、shared evidence、status/Git closeout。

## 17. Rollback

只撤销本 manifest write set 中的 planner、script、test、docs/task/evidence 增量，并由 `build.ps1` 从恢复后的 `src/` 重建 `skills.ps1`。不回滚 P0-P5、maintenance design 或 routing correction 历史资产，不修改 `skills.json`、agent/vendor/import/runtime report 或宿主配置。

## 18. Truth boundary

本实现最多声明 `profile reconciliation advisor repo_verified`。它不证明宿主每次 proposal 的语义正确、不证明 profile 已自动优化、不证明 apply、host load、真实维护净收益或 `live_accepted`。M1 10-task pilot 仍为 `pilot_not_executed`；P6 继续 hold，不创建 Phase 6 manifest。

## 19. Retirement

当官方 profile/skill metadata 管理覆盖 diagnostics、budget、reviewed plan/apply 时，优先适配或删除本 advisor；当真实维护样本显示它没有减少 stale/unrouted 修复时间、反而增加 token/流程时，删除 proposal 层，仅保留现有 projection fail-closed checks。

## 20. Done definition

- current repo diagnostic pass，输出真实 unrouted/budget/overlap 且 zero-write。
- fresh host proposal 可产生 exact add/remove actions；所有负向类别 fail-closed。
- active profile 始终为 default，`skills.json` 和宿主配置无改动。
- PRD/ADR/spec/manifest/plan/todo/README/AGENTS/evidence 一致。
- affected tests、contracts、一次 full gate 通过。
- 四个 `SMV-PR` tasks done，共享一份 reviewed evidence。
- P5 仍 5/5 `repo_verified`，routing correction 仍 4/4，P6 hold，M1 pilot 未执行。
