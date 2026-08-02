# SMV-P0-007 host capability and truth-state matrix

## Scope

- Added a versioned, read-only repository contract for Codex, ChatGPT Work, Claude, Gemini and Trae capability surfaces.
- Added a fail-closed verifier and Pester fixtures for invalid enums, missing affirmative evidence, unknown-surface writes and automated live acceptance.
- Added the contract to the local quality-gate chain after `skills-config-contract` and before planning/doctor.
- No host configuration, installed plugin/skill inventory, authentication, provider, model, session or target repository was scanned or changed.

## Evidence basis

| Source | Current observation | Allowed claim |
| --- | --- | --- |
| Codex manual, `AGENTS.md` section | refreshed 2026-08-01 | global/root-to-cwd discovery, fresh-run/session activation and configurable combined project-doc budget |
| Codex manual, customization/rules sections | refreshed 2026-08-01 | separate AGENTS/skills/plugins/MCP surfaces; experimental exec rules and `execpolicy check` boundary |
| `codex --version` / `codex --help` | `codex-cli 0.145.0` | CLI exists; no loaded-config claim |
| `claude --version` / `claude --help` | `2.1.206` | partial CLAUDE.md auto-discovery/skills boundary; no full precedence or hosted claim |
| current repository projection code/config | current worktree | repo-managed skill/MCP target shapes; no host-load/provider/live claim |
| governed runtime reference | clean `bbf5aba4b221ecf5ac0279ad41c9c51c104b4191` | static layering/model inspiration only |

## Contract decisions

- `truth_states` includes `repo_verified`, `host_loaded`, and `live_accepted`, but automated maxima exclude `live_accepted`.
- `supported` and `partial` require evidence references. `unknown` and `platform_na` must have zero managed writes and remain `not_verified`.
- ChatGPT Work local rule-file projection remains `unknown`. Claude rule guidance remains `partial`. Gemini/Trae rule guidance remains `unknown`.
- Managed paths describe repository ownership boundaries, not current machine inventory or permission to write during validation.

## Verification

- Matrix verifier: exit 0, 5 hosts, 7 evidence records, 0 findings, input hash unchanged.
- Targeted Pester: `HostCapabilityMatrix.Tests.ps1` 6/6; ProductPlanning + QualityGateScripts 15/15.
- Full local quality gate: exit 0; build/generated sync, 105-skill integrity, routing findings 0, dependency/config/host/planning/doctor contracts passed; Unit 543/543 and E2E 12/12.
- Final planning verifier after status reconciliation: must report tasks=9, done=6, open=3, findings=0; recorded by the final verification pass for this slice.

## Rollback

Remove only the matrix, verifier, targeted tests and this evidence; restore the touched README/AGENTS/planning/quality-gate lines. Do not change any host-local file as rollback.

## Truth boundary

The matrix is a `repo_verified` capability contract. It is not a live host inventory and does not prove `host_loaded`, provider connectivity, plugin authorization or `live_accepted`.
