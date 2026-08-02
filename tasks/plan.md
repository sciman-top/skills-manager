# Implementation Plan: skills-manager vNext Phase 2

**program_id**: `skills-manager-vnext`
**current_phase**: `P2`
**task_truth**: `tasks/skills-manager-vnext-phase2.tasks.json`
**status**: complete

## 1. Goal

实现 fixture-only transactional explicit apply：plan -> diff -> freshness/root/token guard -> atomic apply -> receipt -> exact rollback；真实 global/project/host 写入保持禁用。

## 2. Execution contract

- 当前 task 只以 P2 manifest 为真源；P0/P1 作为历史 manifest/evidence 保留。
- 每个 slice 按 `build -> targeted test -> contract/invariant -> full` 收口。
- planner 必须 zero-write；executor 仅允许 TestDrive/fixture root，真实仓 apply fail-closed。
- semantic recommendation 不得生成 desired content 或授权 apply。
- fault injection 只通过测试参数，不提供 production bypass。

## 3. Ordered work

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-P2-001` | planning truth | P2=7 tasks, historical routing, write boundary |
| 2 | `SMV-P2-002` | RulePatchPlan | deterministic plan/diff/schema/sensitive guard |
| 3 | `SMV-P2-003` | apply guards | root/reparse/freshness/token/fixture-only |
| 4 | `SMV-P2-004` | executor | atomic replace/receipt/exact rollback |
| 5 | `SMV-P2-005` | fault recovery | stage/replace/receipt/concurrency/cleanup |
| 6 | `SMV-P2-006` | CLI + MCP adapter | fixture-only JSON CLI, MCP parity |
| 7 | `SMV-P2-007` | acceptance | fixture matrix, real hash guard, full gate |

## 4. Verification order

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000
python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

## 5. Phase completion rule

7 个 P2 task 已全部 done，fault/concurrency/sensitive fixtures、真实规则/config hash guard 和 full gate 已通过。当前最高仅 `repo_verified`；不得自动进入 P3，不得把 fixture apply 写成 host/live acceptance。
