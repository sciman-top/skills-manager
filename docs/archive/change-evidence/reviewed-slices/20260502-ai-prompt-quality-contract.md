# AI Prompt Quality Contract

- rule_ids: R1, R6, R8
- risk: low
- target_disposition: improve built-in AI-agent prompts without changing recommendations schema, apply behavior, or generated runtime bundle files by hand
- basis: Existing audit prompts already enforced schema, source coverage, dry-run, and evidence-output boundaries. The remaining quality gap was that prompts did not explicitly block stale-run reuse, weak duplicate recommendations, or plaintext MCP credentials, and did not require final status separation for recommendations/preflight/dry-run/apply.

## Changes

- Updated audit prompt contract to `audit-prompt-v20260502.2`.
- Strengthened the built-in outer-AI prompt to reject old run reuse and require every change recommendation to show non-duplicative incremental value or a concrete removal rationale.
- Strengthened generated target-repo and profile-only `ai-brief.md` text with installed-snapshot fit checks, exact removal identifier guidance, plaintext credential prevention for MCP payloads, and explicit execution-state reporting.
- Strengthened runtime `outer-ai-prompt.md` with the same self-check and output-contract wording.
- Updated prompt-focused Pester assertions and rebuilt root `skills.ps1` from `src/Commands/AuditTargets.ps1`.

## Commands

- `.\build.ps1`
- `.\tests\run.ps1 -Scope AuditTargets`
- `.\skills.ps1 发现`
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
- `.\skills.ps1 构建生效`

## Key Output

- `Build success: D:\CODE\skills-manager\skills.ps1`
- `Tests Passed: 332, Failed: 0` for unit tests
- `Tests Passed: 11, Failed: 0` for E2E tests
- `.\skills.ps1 发现` listed 91 installed skills.
- `Your system is ready for skills-manager.`
- `构建完成：agent/ (共 91 项技能)` and target links refreshed.

## Rollback

- `git restore -- src/Commands/AuditTargets.ps1 tests/Unit/AuditTargets.Tests.ps1 skills.ps1 docs/change-evidence/20260502-ai-prompt-quality-contract.md`
- Re-run `.\build.ps1` and `.\skills.ps1 构建生效` after rollback if generated entrypoint or agent output needs to be refreshed.
