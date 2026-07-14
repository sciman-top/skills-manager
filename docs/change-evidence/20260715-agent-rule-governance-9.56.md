# Agent Rule Governance 9.56

- verified_at: `2026-07-15T00:30:00+08:00`
- scope: `AGENTS.md` global review marker only; existing audit-target work and runtime evidence remain user-owned and separate.
- pre_existing_dirty: `docs/change-evidence/20260714-audit-runtime-scan-20260714-235154-812-235330.md` was present before this task and is not part of rollback or commit.
- protected_unrelated_dirty: `tests/Unit/AuditTargets.Tests.ps1` is outside this task write-set and is not staged, reverted, or committed.
- compatibility: project contract remains `2.0`; `CLAUDE.md` remains the one-line `@AGENTS.md` wrapper.

## Ordered gates

| stage | command | exit | key result |
|---|---|---:|---|
| build | `build.ps1` | 0 | generated `skills.ps1` synchronized |
| test | `tests/run.ps1` | 0 | Unit 484 and E2E 12 passed |
| contract/invariant | `skills.ps1 doctor --strict --threshold-ms 8000`; dependency baseline verifier | 0 | doctor and baseline passed; non-blocking apply-targets performance warning retained |
| hotspot/full | `run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | 0 | full local quality gate passed |
| rule contract | control-repo `verify-target-project-rules.py --require-all` | 0 | project rule/wrapper/workflow passed |

Gate-generated audit runtime artifacts from this verification were removed; the pre-existing user evidence was preserved. Rollback is limited to this evidence file and the `AGENTS.md` 9.56 marker.
