# Implementation Plan: skills-manager vNext Phase 3

**program_id**: `skills-manager-vnext`
**current_phase**: `P3`
**task_truth**: `tasks/skills-manager-vnext-phase3.tasks.json`
**status**: complete

## 1. Goal

实现只读 plugin inventory、manifest/supply-chain lint、单一 fixture-only Codex skills-only exporter 与分层 eval；安装、认证、marketplace mutation、provider 和 host write 保持禁用。

Post-closeout follow-through：增加 `rule-estate-audit`，从工作区直属 Git 根生成 Codex/Claude 联合规则审计；允许 reviewed 单仓规则 create/update，继续禁止全局用户目录和批量跨仓覆盖。

## 2. Execution contract

- 当前 task 只以 P3 manifest 为真源；P0/P1/P2 作为历史 manifest/evidence 保留。
- 每个 slice 按 `build -> targeted test -> contract/invariant -> full` 收口。
- inventory/lint/eval 默认 zero-write；exporter 必须 fixture marker + exact root + explicit token。
- 只支持有当前官方 docs/help/fixture 的 Codex skills-only plugin shape。
- P4 只由独立 evidence gate 决定，不因 P3 代码完成自动启动。

## 3. Ordered work

| Order | Task | Slice | Exit checkpoint |
| ---: | --- | --- | --- |
| 1 | `SMV-P3-001` | planning + entry evidence | P3=7 tasks，官方 surface 与两个 workflow 已证明 |
| 2 | `SMV-P3-002` | inventory adapter | 三 scope 保持，zero side effects |
| 3 | `SMV-P3-003` | manifest lint | shape/source/version/license/path fail-closed |
| 4 | `SMV-P3-004` | bounded exporter | fixture-only two-skill exact round-trip |
| 5 | `SMV-P3-005` | layered eval | static/behavior blocking，model optional |
| 6 | `SMV-P3-006` | CLI + acceptance | four JSON commands，generated/compat guards |
| 7 | `SMV-P3-007` | closeout + P4 gate | P3 repo closeout，P4 decision machine truth |

## 4. Verification order

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-phase4-entry-gate.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000
python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-host-capability-matrix.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

## 5. Phase completion rule

七个 P3 task 全部 done，fixture inventory/lint/export/eval、P4 decision verifier 与 full gate 通过。最高仅 `repo_verified`；plugin install、host load 和 live workflow 均未执行。
