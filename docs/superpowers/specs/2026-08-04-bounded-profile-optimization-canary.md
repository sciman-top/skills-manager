# Bounded Profile Optimization Canary

**program_id**: `skills-manager-vnext`

**track**: `profile_optimization_canary`

**base_phase**: `P5`

**P6_ADMISSION_STATUS**: `hold`

**implementation_scope**: `repo_side_bounded_transaction`

**host_replay_status**: `not_run_for_this_track`

**live_acceptance**: `not_run`

## 1. Problem and root cause

native-first correction 已把自然语言语义所有权归还宿主 AI，profile reconciliation advisor 也能发现 stale/unrouted/budget/overlap 并校验 proposal；但链路固定终止于 `apply_allowed=false`。因此 skill 增删或 description 变化后，宿主可以给出正确建议，却没有 freshness、原子备份、receipt、fresh-task replay 和失败回滚组成的可执行闭环。

根因不是关键词不足，而是 proposal 后不存在受控事务 seam。恢复词法 router、让模型直接编辑 JSON，或把 freshness/权限/冲突交给概率判断都会重新引入已证实的误路由和状态漂移。

## 2. Goal

建立低打扰但可审计的 profile 优化闭环：宿主 AI 读取完整请求、skill description、profile 用途和上下文后生成最小 proposal；确定性内核只允许有界的非活动 profile canary，记录 backup/receipt；独立 fresh ephemeral task replay 通过后接受，失败则自动回滚。

## 3. Product constitution

- 语义准确度由已经处理完整上下文的宿主 AI 提供，不启动第二个 router/model call。
- 状态正确性由确定性代码提供：hash freshness、对象、protected kind、冲突、no-op、预算、动作上限、原子写、receipt 和回滚。
- 自治必须可审计：常驻授权可减少逐次询问，不能取消 receipt、失败报告和 truth boundary。
- `active_profile` 是 skills-manager 策展字段，不是 Codex 原生 runtime/profile API。
- profile promotion 只在新任务边界验证；当前任务不宣称热更新 initial catalog。
- 没有真实 inventory change 或净收益证据时不机械处理全部 `unrouted`。

## 4. Scope

In scope：advisor 增加 host handoff；proposal apply preview；最多 5 个 changed skills、10 个 actions；禁止修改当前 active profile membership；原子写 `skills.json`；ignored backup/receipt；fresh-task replay contract；replay 失败自动回滚；benchmark 报告 execution/restoration boundary；CLI manager、focused tests、产品/任务/evidence 同步。

Out of scope：provider/API 调用、后台 watcher/daemon/database、模型自改 skill description、安装/删除 skill/plugin/MCP、宿主 auth/model/sandbox/session mutation、当前任务热切换、永久自动切换 `active_profile`、P6、M1 pilot、business `live_accepted`。

## 5. Target flow

```text
inventory or metadata changed
  -> deterministic advisor diagnostic
  -> host AI inspects full descriptions and emits minimum proposal
  -> deterministic preview: freshness/object/no-op/conflict/budget/policy/limits
  -> non-active profile canary apply
  -> atomic backup + receipt
  -> fresh ephemeral host replay with direct/indirect/negative/edge prompts
  -> pass: accepted (host_evaluation_partial_pass)
  -> fail: hash-guarded automatic rollback
```

此链路是 `host-assisted autonomous maintenance`，不是仓库脚本自行调用宿主 AI。宿主已经在处理 skill 变更任务时，应根据 `host_handoff` 自动生成 proposal 并调用确定性步骤；脱离宿主单独运行 CLI 时，脚本不会伪造语义判断。

## 6. Host handoff

无 proposal 的 advisor 输出：

```text
host_handoff.required=true
host_handoff.semantic_owner=host_ai
host_handoff.next_action=inspect_full_skill_descriptions_and_create_minimum_proposal
host_handoff.base_config_sha256
host_handoff.profile_names[]
host_handoff.candidate_names[]
host_handoff.constraints[]
```

`candidate_names` 是待语义审查输入，不是“必须路由”列表。宿主必须允许 no-op：新增低频 skill 保持 cold/explicit 可能是最优结果。

## 7. Apply preview and limits

`New-SkillProfileReconciliationApplyPlan` 复用现有 planner，增加：

- proposal/current config SHA-256 freshness。
- `changed_skills <= 5`、`actions <= 10`。
- changed profile 默认保留至少 256 字符 metadata headroom；仅低于 hard ceiling 仍不足以进入自动 canary。
- 至少一个有效 action。
- 所有 action 只能指向非活动 profile。
- `activation_boundary=fresh_task`。
- 稳定 operation/proposal identity。

preview 仍为 zero-write。只有显式 token `APPLY_PROFILE_RECONCILIATION_CANARY` 才进入 apply；这表示当前宿主已消费用户授权或登记的常驻策略，不代表模型自我授权。

## 8. Atomic apply and receipt

apply 在写前重新核对 config hash，使用单 writer lock，备份原始 bytes，以 atomic replace 写 `skills.json`，再重新运行 projection/budget/policy 诊断。任何异常恢复原始 bytes。

receipt 至少记录：operation/status、config path、before/after hash、proposal hash、active profile、changed skill/profile、exact actions、backup path、replay 状态和 `live_accepted=not_run`。receipt/backup 位于 ignored `reports/`，不进入活跃 evidence ledger。

## 9. Replay and acceptance

replay 使用现有 `benchmark-codex-skill-profiles.ps1 -Execute`，每次 `codex exec --ephemeral --sandbox read-only` 都是新任务。报告必须声明：

- `execution_boundary=fresh_ephemeral_task`。
- `original_profile` 与 receipt active profile 一致。
- `restored_profile` 与 original 一致。
- 每个 changed profile 至少四个不同 case；日常只测 changed profile/skill，完整 profile corpus 仅在 description/profile 结构变化或 closeout 使用。
- 每个 added skill 至少一项 required positive 和一项 forbidden negative case。
- 每个 changed skill 至少一项 negative case。
- 每个 result parse、exit 和 expectation 均通过。

Codex JSONL 当前没有独立“完整 SKILL.md 已执行”事件，因此通过状态只能是 `host_evaluation_partial_pass`，不能晋级为 `host_loaded` 或 `live_accepted`。LLM replay 也不是唯一门禁；它位于 deterministic plan/apply/profile contract 之后。

## 10. Acceptance and rollback

接受 token 为 `ACCEPT_PROFILE_RECONCILIATION_CANARY`。接受前再次核对当前 config hash 等于 receipt after hash。replay 失败且调用方指定 `RollbackOnFailure` 时，事务先记录失败报告，再使用受控回滚；目标或 backup 任一 hash 漂移则 fail-closed，不覆盖后续用户改动。

显式回滚 token 为 `ROLLBACK_PROFILE_RECONCILIATION_CANARY`。回滚可处理 `canary_applied | replay_failed | accepted`，但永远要求 receipt target、derived backup path 和 before/after hashes 一致。

## 11. `active_profile` boundary

canary 不允许永久修改 active profile，也不允许改当前 active profile 的 membership。benchmark 可为 fresh task 临时选择被测 profile，但必须在 `finally` 恢复原 profile并由报告复核。外层进程被强制终止仍可能跳过 finally，因此任何执行型 replay 后都必须独立读取 `skills.json` 确认恢复；不自动 kill/restart Codex。

官方 Codex 支持 skill 文件变化检测、App Server `skills/changed` 和 `skills/list(forceReload=true)`，也支持按路径 enable/disable；官方稳定文档没有 skills-manager `active_profile` 或当前任务 profile hot switch。故本项目只把 `forceReload/fresh task` 作为生效/验证边界，不将自有字段伪装成原生能力。

## 12. Automation levels

- 静默只读：inventory/hash、stale/unrouted/budget/overlap、host handoff、proposal preview。
- 常驻授权下自动：非活动 profile bounded canary、backup/receipt、fresh-task replay、失败回滚。
- 必须可见：永久 active profile 切换、大批量 membership 删除/重组、host config、skill/plugin/MCP 安装删除、auth/provider/model/sandbox/session 和外部写入。

## 13. Security

proposal、skill metadata、corpus 和模型输出均视为不可信输入。reason 和 replay score 不能覆盖 deterministic policy。事务不读 token/auth/provider，不执行 skill 内容或社区脚本；benchmark 显式 read-only/ephemeral。receipt 不记录 prompt secrets；可提交 evidence 只记录命令、汇总和 truth boundary。

## 14. Failure routing

- stale hash：重新诊断，由宿主基于新 inventory 生成 proposal。
- unknown/protected/no-op/conflict：修 proposal，不放宽规则。
- active profile target：改为非活动 canary；若必须改变当前可见集，留到新任务显式 promotion。
- budget exceeded：减少 membership/描述重复，不提高 8,000 ceiling。
- replay positive/negative coverage 缺失：补代表性 prompt，不接受。
- replay expectation fail：自动回滚；同类语义失败两次后重新审查 skill description/profile purpose。
- rollback target stale：停止自动写入，保留 receipt 并报告人工合并点。

## 15. Official and community basis

- OpenAI Build skills：宿主从 name/description 做 explicit/implicit activation；初始 catalog 受 2% context 或 8,000 字符预算；skill 变化可自动检测，未出现时重启。
- OpenAI App Server：`skills/changed` 是 invalidation signal，`skills/list(forceReload=true)` 可重新扫描；这支持 fresh reload，不证明当前 turn 热注入。
- Agent Skills：adopt progressive disclosure 与模型/harness 职责分层。
- Superpowers：adapt deterministic tests 与真实 LLM behavior eval 分层，旧断言必须由真实场景覆盖后才能删除。
- LangGraph：adapt checkpoint/receipt/recovery 思想；defer runtime graph/checkpointer。

不复制或运行上游源码；revision 和 license 继续以 reference shelf/current evidence 为准。

## 16. Verification order

1. `build.ps1`。
2. `SkillProfileReconciliation.Tests.ps1`、`SkillProfileReconciliationTransaction.Tests.ps1`、`SkillProfileBenchmark.Tests.ps1`。
3. 当前仓 advisor JSON 和 benchmark no-execute plan。
4. profile/config/routing/integrity/planning contracts。
5. 至少一组真实 fresh host natural-language replay；若未执行，本 track 状态必须保留 `host_replay_not_run`。
6. 文件稳定后唯一 full gate。
7. `git diff --check`、active profile、P6 manifest 和 Git boundary。

## 17. Task mapping

- `SMV-PO-001`：根因、官方边界、目标契约和任务真值。
- `SMV-PO-002`：host handoff、bounded transaction、manager、benchmark contract 和 focused tests。
- `SMV-PO-003`：自然语言 replay、产品/文档/evidence、ordered closeout。

## 18. Rollback

代码回滚仅撤销本 manifest write set，并由 `build.ps1` 重建 generated `skills.ps1`。运行时 canary 使用 receipt 的 backup/hash 回滚；不覆盖无关 imports/vendor/audit/MCP 或用户工作树修改。不改写 P5、routing correction 和 plan-only advisor 的历史 evidence。

## 19. Done definition

- advisor 能输出机器可读 host handoff；没有第二个 semantic router。
- 非活动 profile canary 的 freshness/limit/active-profile/atomic/receipt/rollback tests 通过。
- fresh replay contract 有正负覆盖、恢复核对和失败自动回滚。
- 产品/架构/路线图/spec/manifest/plan/todo/README/AGENTS 一致。
- 当前 `active_profile=default`，P5 仍 5/5 `repo_verified`，P6 hold，无 Phase 6 manifest。
- 完成声明限定为 `profile optimization transaction repo_verified`；未执行真实 replay 时不得声明语义效果，任何 replay 也只标 `host_evaluation_partial`。
