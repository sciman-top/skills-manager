# 2026-08-04 Bounded profile optimization canary evidence

**program_id**: `skills-manager-vnext`
**track**: `profile_optimization_canary`
**base_phase**: `P5`
**status**: `repo_verified`
**verification_level**: `repo_verified + host_evaluation_partial`
**P6_ADMISSION_STATUS**: `hold`
**M1_PILOT_STATUS**: `pilot_not_executed`
**LIVE_ACCEPTANCE_STATUS**: `not_run`

## 1. Authorization and problem

用户要求尽量使用宿主 AI 原生语义，实现 skill/profile 的智能、自动、自主、低打扰维护，同时保留 freshness、预算、no-op、冲突、安全校验、active profile 和代表 prompt replay 全链路；并持续强调不要过度设计、不要在主链未通时堆门禁和 token。

现有 profile reconciliation advisor 已能生成精确 zero-write plan，但固定 `apply_allowed=false`。本切片在用户“按建议自动自主连续执行/继续”的授权下实现 proposal 后的 P5-local bounded transaction，不启动 P6，不调用新的 provider，不安装插件/MCP，不修改 auth/model/sandbox/session。

## 2. Root cause and decision

根因是 proposal 后没有 transaction/replay seam，而不是词法规则不足。目标责任分层：

```text
semantic fit                  = current host AI
freshness/object/conflict     = deterministic planner
bounded state mutation        = atomic canary + receipt
semantic effect observation   = fresh ephemeral replay
failure recovery              = hash-guarded rollback
```

完全静默且无 receipt 的模型写入被拒绝；完全手工逐次审批也被拒绝为默认。采用常驻授权下的非活动 profile canary，永久 active profile 切换和宿主高风险变化继续可见。

## 3. Official boundary

2026-08-04 通过 `openai-docs` helper 刷新 Codex manual：

- [Build skills](https://learn.chatgpt.com/docs/build-skills.md)：宿主先看到 name/description，决定 explicit/implicit activation；初始列表最多约 2% context 或 8,000 字符；skill 变化可自动检测，未出现时重启。
- Codex App Server manual：`skills/changed` 是 invalidation signal；`skills/list(forceReload=true)` 可刷新磁盘 inventory。
- config/manual 只证明按 skill path enable/disable；未发现 skills-manager `active_profile`、当前 turn profile hot switch 或自动回写本项目 profile 的官方稳定契约。

因此 fresh task/force reload 是验证边界；本项目自有 `active_profile` 不伪装成 Codex runtime profile。

## 4. Community disposition

只读参考，不继承指令、不运行上游脚本、不复制源码：

| Source | Revision | Disposition |
| --- | --- | --- |
| `agentskills/agentskills` | `38a2ff82958afee88dadf4831509e6f7e9d8ef4e` | adopt progressive disclosure；宿主/模型决定 activation，harness 处理 discovery/trust/path |
| `obra/superpowers` | `3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9` | adapt deterministic tests 与真实 LLM behavior eval 分层；reject mandatory all-task workflow |
| OpenAI plugins | current reference shelf, per-plugin license | adopt metadata/replay 分层；不复制 marketplace/runtime |
| LangGraph | prior reviewed reference | adapt checkpoint/receipt/recovery；defer graph runtime/database |

## 5. Implementation

- advisor 增加 `host_handoff`，明确 `semantic_owner=host_ai`、base hash、候选和约束。
- 新 `Application/SkillProfileReconciliation.ps1`：apply preview、最多 5 skill/10 action、默认 256 字符 budget headroom、active profile target 禁止、single-writer、atomic backup/write、receipt、accept/rollback。
- 新 manager script 提供 `Plan | Apply | Accept | Rollback`，显式 token，不自行调用模型。
- benchmark 报告增加 `execution_boundary=fresh_ephemeral_task` 和 `restored_profile`。
- replay 要求每个 changed profile 至少 4 case、added skill 同时有 positive/negative coverage；失败可自动回滚。
- `skills.json` 的 `content` profile 经真实 canary 接受 `doc-coauthoring`；`default` 未改变。

## 6. Failed candidate and anti-overdesign correction

首个 host proposal 是 `context-engineering -> engineering`。原 hard ceiling planner 显示 `7956/8000`，虽 pass 但只剩 44 字符；在任何 description 小改后都可能失效。模型 replay 未启动，事务按 receipt 恢复原 hash。

由此新增 deterministic `MinBudgetHeadroomChars=256` 及负向测试。这个失败没有通过提高 8,000 ceiling 或放宽门禁处理。

随后尝试用 minimal scratch cwd 降低 replay token；两场景仍为 49,746 input tokens，约 24.9k/次，与仓库 cwd 无实质改善。该开关和测试已删除，避免保留无净收益分支。保留的成本策略是只测 changed profile/skill 的 4–6 个场景，完整 corpus 只在结构变化/closeout 使用。

## 7. Accepted real canary

proposal：`doc-coauthoring -> content`。语义依据是其完整 description 专用于协同撰写文档、proposal、技术 spec 和 decision doc；`content` 已承载 editing/formatting/publishing。deterministic preview：

- current active profile: `default`
- changed profiles: `content`
- action count: 1
- proposed content budget: `7397/8000`
- headroom: 603（minimum 256）
- freshness/object/protected/no-op/conflict/policy: pass

执行 6 个 fresh ephemeral、read-only、顺序自然语言场景：

| Case | Required/forbidden | Observed | Result |
| --- | --- | --- | --- |
| 中文技术方案协同写作 | require `doc-coauthoring` | `doc-coauthoring` | pass |
| English architecture decision coauthoring | require `doc-coauthoring` | `doc-coauthoring` | pass |
| 中文仅校对 | require `copy-editing`, forbid candidate | `copy-editing` | pass |
| English finished Markdown formatting | require formatter, forbid candidate | `baoyu-format-markdown` | pass |
| 中文仅发布 | require publishing, forbid candidate | `custom-creator-publishing` | pass |
| English explicit negative | forbid candidate | `documents:documents` | pass |

汇总：6/6 expectation pass，0 delegation，0 worktree，`original_profile=default`，`restored_profile=default`，81,687 ms，148,192 input tokens，1,192 output tokens。receipt 状态为 `accepted`，replay 为 `host_evaluation_partial_pass`，`live_accepted=not_run`。

限制：Codex JSONL 没有独立 skill-body invocation event；结果证明模型在 fresh task 中选择/排除正确名称，不证明完整 skill workflow 或跨任务普遍正确。

## 8. Worktree and write set

baseline：`main...origin/main`，HEAD `65ccf1208285026e563062cf1a43d44f8668fa5a`，起点干净。实现修改 source/build/generated、manager/planner/benchmark、focused tests、`skills.json` content membership、产品/spec/manifest/plan/todo/README/AGENTS 和本 evidence。runtime proposal/corpus/report/receipt/backup 位于 ignored `reports/`。

未修改 imports/vendor、provider/auth/model/sandbox/session、plugin/MCP 安装、宿主进程或 P6 manifest。benchmark 只通过既有 profile projection 临时写受管 skill enablement，并恢复 `default`。

## 9. Verification

最终有序结果：

- transaction red-green：新增“另一 writer 已持锁”回归后为 8 pass/1 fail；cleanup 改为仅 lock owner 删除锁，重新 build 后 9/9 pass。
- affected Pester：`SkillProjection`、`SkillRouting`、`SkillIntegrityScript`、advisor、transaction、benchmark 共 72/72 pass。
- current advisor：pass、zero-write、16 profiles、48 unrouted；`content=7397/8000`。
- benchmark no-execute plan：valid，`execution_boundary=fresh_ephemeral_task`，24 planned calls；未重复执行全量模型 corpus。
- real canary：6/6，`host_evaluation_partial_pass`。
- capability routing corpus：27/27；semantic auto selection、negative constraint 和 side-effect violation 均为 0。
- config enforce：pass，before/after hash 相同；仅保留既有 `legacy_schema_version_missing` observation。
- routing/integrity：routing findings 0；107 skills verified。
- 16-profile fresh visibility：16/16 pass；`content=7397/8000`；最终恢复 `default`。
- planning：P5 5/5、maintenance design 4/4，finding 均为 0；Phase 6 manifest absent。
- 唯一 full gate：pass；build、完整 tests、repo hygiene、generated sync、integrity、routing、dependency、config、host-capability、planning、doctor JSON 全部通过，`total_elapsed_ms=185762`。
- final independent boundary：`skills.json.active_profile=default`、projection manifest `default`、`content` 包含 `doc-coauthoring`、P6 manifest absent。
- Git closeout：本 reviewed slice 按常驻授权提交并推送 `origin/main`；最终 SHA 和 local/remote parity 由收口回执报告。

## 10. Rollback

运行态：使用 ignored receipt/backup 和 exact before/after hash；目标漂移时 fail-closed。仓库侧：只撤销 profile optimization manifest 的 write set，先恢复 source/config，再运行 `build.ps1` 重建 `skills.ps1`。不得覆盖无关用户改动或改写 P5/CR/PR 历史 evidence。

## 11. Truth boundary

- P5: 5/5 `repo_verified`, unchanged.
- profile optimization track: 3/3 `repo_verified`.
- host replay: `host_evaluation_partial_pass`, not a universal semantic guarantee.
- active profile: restored `default`; accepted membership only affects future `content` tasks.
- P6: hold; Phase 6 manifest absent.
- M1 pilot: not executed.
- business `live_accepted`: not run.
