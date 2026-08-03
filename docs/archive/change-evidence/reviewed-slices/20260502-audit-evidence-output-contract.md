# Audit Evidence Output Contract

- rule_ids: R1, R6, R8
- risk: low
- target_disposition: clarify audit prompt write boundaries without changing recommendations schema or apply behavior
- basis: A dry-run-only audit execution produced expected command evidence files. The built-in prompt did not explicitly separate outer-AI hand-write boundaries from command-generated evidence outputs.

## Changes

- Updated audit prompt contract to `audit-prompt-v20260502.1`.
- Clarified in generated `ai-brief.md` text that audit commands may automatically write `preflight-report.json`, `dry-run-summary.json`, `apply-report.json`, and `docs/change-evidence/*.md`.
- Clarified in runtime `outer-ai-prompt.md` output contract that these files are expected command evidence outputs and should not be hand-written or hand-edited by the outer AI agent.
- Added unit assertions for target-repo brief, profile-only brief, and runtime outer prompt wording.
- Rebuilt root `skills.ps1` from `src/Commands/AuditTargets.ps1`.

## Commands

- `.\build.ps1`
- `.\tests\run.ps1 -TestName AuditTargets`
- `.\skills.ps1 发现`
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
- `.\skills.ps1 构建生效`

## Key Output

- `Build success: D:\CODE\skills-manager\skills.ps1`
- `Tests Passed: 332, Failed: 0` for unit tests
- `Tests Passed: 11, Failed: 0` for E2E tests
- `Your system is ready for skills-manager.`
- `构建完成：agent/ (共 91 项技能)`

## Rollback

- `git restore -- src/Commands/AuditTargets.ps1 tests/Unit/AuditTargets.Tests.ps1 skills.ps1 docs/change-evidence/20260502-audit-evidence-output-contract.md`
- Re-run `.\build.ps1` and `.\skills.ps1 构建生效` after rollback if generated entrypoint or agent output needs to be refreshed.
