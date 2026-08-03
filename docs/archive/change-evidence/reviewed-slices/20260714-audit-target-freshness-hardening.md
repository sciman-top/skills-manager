# Audit target freshness hardening evidence

- date: 2026-07-14
- risk: medium
- target_disposition: make target-repository freshness, preflight failures, repository scan facts, and dry-run summaries machine-verifiable without changing apply authorization
- live_configuration_changed: false
- apply_executed: false
- commit_or_push_executed: false

## Root causes and changes

- `workflow-report.json` hashed bundle files and live skill/MCP state but did not re-read target repository HEAD or worktree state.
- ordered-dictionary scan targets were rendered as `*` in `decision-insights.json`.
- repository scan facts did not recognize PowerShell entrypoints or supported commands explicitly declared in README/agent-rule files.
- invalid recommendations could throw before `preflight-report.json` was written.
- `dry-run-summary.json` lacked `mode/success/persisted`, and category-specific empty reasons required undocumented prefixes.
- target status now separates product input from `docs/change-evidence/<date>-audit-runtime-*` evidence so the workflow does not flag its own generated evidence as product drift.
- the automatic-evidence exemption is anchored to the repository-root evidence path; nested product paths with similar names remain part of the drift fingerprint.
- `target_repo_drift` failure reports now route recovery to a fresh target scan instead of a generic retry.

## Verification

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` -> exit 0; generated `skills.ps1` refreshed from `src/`.
2. Focused red/green suite `tests/Unit/AuditTargetsHardening.Tests.ps1` -> initial 6 failures, followed by isolated red checks for preflight target drift and automatic-evidence separation; final 9 tests passed, 0 failed, including nested lookalike-path rejection and the target-drift rescan recovery assertion.
3. Compatibility suite `tests/Unit/AuditTargets.Tests.ps1` -> 88 passed, 0 failed.
4. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` -> exit 0; unit and E2E suites completed with 0 failures.
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0; existing `apply_targets` performance warning remained non-blocking.
6. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` -> exit 0.
7. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` -> exit 0; full local quality gates passed, generated sync matched, and repository hygiene reported only the three pre-existing untracked audit-runtime evidence files.
8. PowerShell AST parse for all changed source and test files -> passed; final tracked diff and untracked-file whitespace checks -> passed.

## Worktree boundary and rollback

- Pre-existing untracked files preserved unchanged:
  - `docs/change-evidence/20260714-audit-runtime-dry-run-20260714-175610-135-181332.md`
  - `docs/change-evidence/20260714-audit-runtime-scan-20260714-174614-402-174747.md`
  - `docs/change-evidence/20260714-audit-runtime-scan-20260714-175610-135-175742.md`
- This slice changes only `build.ps1`, generated `skills.ps1`, `src/Commands/AuditTargets.ps1`, `src/Commands/AuditTargets.TargetState.ps1`, `src/Commands/AuditTargets.Apply.ps1`, `src/Commands/AuditTargets.Workflow.ps1`, `tests/Unit/AuditTargetsHardening.Tests.ps1`, and this evidence file.
- Rollback only those files from this slice. Do not restore, delete, or overwrite the pre-existing audit-runtime evidence files or unrelated repository history.
