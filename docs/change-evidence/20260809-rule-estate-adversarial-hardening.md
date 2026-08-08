# RuleEstate adversarial hardening evidence

- Scope: `RuleDiscovery` and `RuleEstate` static governance only; no target-repository rule, provider, profile, auth, VPS, SSH, or business-runtime mutation.
- Official basis: current Codex manual `Custom instructions with AGENTS.md` confirms first-non-empty global/project discovery, per-directory precedence, empty-file skipping, and fresh-run loading; `codex debug prompt-input --help` confirms the local non-provider prompt assembly probe.
- Root causes: empty candidates were selected by existence; project mappings could enlarge the authoritative constraint set; duplicate mappings were collapsed before coverage; directories could satisfy S5; expired N/A, hard budgets, and mandatory contract structure did not consistently block the command.
- Fix: select first non-empty candidates; derive expected IDs only from global C; preserve repeated actions; reject grouped/unknown/duplicate mappings; require concrete enforcement files; fail on expired N/A, hard budget, missing `1/A/B/C/D`, invalid Claude wrappers, and hard global drift.
- Documentation: default examples use dynamic discovery; optional `--registry` is documented only as snapshot drift comparison, never target truth. v1 primary and compatibility summary fields are distinguished.
- Focused verification: `RuleDiscovery.Tests.ps1` 8/8 and `RuleEstate.Tests.ps1` 29/29 passed after the adversarial cases first failed against the prior implementation.
- Dynamic estate verification: default discovery found 9 targets, 144/144 textual mappings, 0 semantic gaps, 0 findings; `structural_pass=true`, `semantic_coverage_pass=true`, `enforcement_verified=true`, `writes=0`, `provider_calls=0`.
- Independent target evidence: 9/9 recorded `After AGENTS SHA-256` values match current `AGENTS.md`; eight remote-backed repositories are clean and `0/0` against `origin/main`; the poster repository remains local-only with its 255 pre-existing business changes preserved.
- Full gate: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` passed in `346857ms`; 1133/1133 tests plus build, generated-sync, hygiene, lock parity, skill/reference/dependency/planning/runtime-policy contracts passed.
- Fresh host load: `codex debug prompt-input` passed 9/9; every target prompt contained global v9.73, the current project title/review release, and its current S5 mapping. No model/provider call was made.
- Rollback: revert only this evidence file and the listed source/test/docs/generated files from this slice; do not alter target repositories or ignored receipts.
- Truth boundary: `repo_verified=passed`; `host_loaded=codex_fresh_prompt_verified`; `claude_loaded=not_run`; `live_accepted=not_run`.
