# skills-manager vNext planning contract

## Scope and boundary

- Task: `SMV-P0-001` only.
- Source/target: product intent was converted into PRD, architecture, roadmap, Phase 0 spec, machine-readable task manifest, implementation plan, todo, verifier, tests, README/AGENTS routing and this evidence.
- Runtime boundary: no Phase 0 product capability, rule apply, plugin install, MCP projection or host-local configuration was implemented or changed.
- Initial worktree: `main...origin/main` was clean before this slice; the final dirty set is limited to the task manifest `write_set`.

## Decisions

- Keep a PowerShell modular monolith with deterministic single-file distribution; treat this as the best fit for current constraints, not a permanent global optimum.
- Keep rules advisory-first. Phase 1 is read-only; explicit path-scoped apply cannot enter before Phase 2 gates.
- Keep `skills.json` as current skill/MCP runtime truth and keep project rule ownership in each target repository.
- Do not restore a central target registry, cross-repository synchronizer, daemon, database, GUI, provider/model/auth/session manager or agent runtime.
- Maintain detailed machine tasks only for the current implementation Phase.

## Sources reviewed

### Official

- OpenAI Codex manual cache refreshed on 2026-08-01: Best practices, AGENTS.md, Plugins, Plugin architecture, Skills, MCP and Hooks sections.
- Public links are recorded in `docs/product/skills-manager-vnext-prd.md` so later implementation tasks can refresh the exact surface they depend on.
- The current official guidance supports short repo-owned AGENTS files, focused skills, native plugin discovery/install, MCP for live external data/actions, and hooks for deterministic lifecycle enforcement.

### Repository and community

| Source | Revision/state read | Decision |
| --- | --- | --- |
| `D:\CODE-other\governed-ai-coding-runtime` | `bbf5aba4b221ecf5ac0279ad41c9c51c104b4191`; static archive, local `main` ahead of `origin/main` by 1 | Adapt rule layering/minimization/native probes; reject retired registry/sync/cross-repo audit runtime. |
| `D:\CODE\external\skills-manager-references\core\openai-skills` | `49f948faa9258a0c61caceaf225e179651397431`; README declares repository deprecated in favor of `openai/plugins` | Create `SMV-P0-002`; do not modify the shelf or installed skills in this task. |
| `wshobson/agents` | `c4b82b0ad771190355eb8e204b1329732a18449a` | Adapt small plugin shapes and structural checks; reject importing its multi-agent/model structure. |
| `obra/superpowers` | `3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9` | Adapt evidence-first verification and focused workflows; reject always-on process control. |
| `mattpocock/skills` | `ed37663cc5fbef691ddfecd080dff42f7e7e350d` | Adapt composable focused skills; reject workflow takeover. |

External sources were read-only inputs. Their instructions were not inherited and no upstream script was run.

## Changes

- Added the vNext product index, PRD, architecture, roadmap and Phase 0 spec.
- Replaced the stale current implementation plan/todo with the Phase 0 execution view while retaining the JSON manifest as task truth.
- Added a planning verifier that checks required assets/markers, task IDs, phases, statuses, risks, dependencies/cycles, requirement/ADR references, forbidden write sets, plan/spec/todo coverage, todo status and exact evidence for done tasks.
- Added Pester fixtures for valid planning, duplicate IDs, unknown dependencies, todo coverage/status drift and missing done-task evidence.
- Added the planning contract to the quality gate after dependency baseline and before doctor contract.
- Updated README/AGENTS routing and documented current implementation truth.

## Verification

The fixed order was `build -> test -> contract/invariant -> hotspot/full`.

| Command | Result |
| --- | --- |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0; generated `skills.ps1` successfully. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` | exit 0; Unit 510/510, E2E 12/12, zero failed/skipped/pending/inconclusive. |
| targeted `ProductPlanning.Tests.ps1` and `QualityGateScripts.Tests.ps1` | exit 0; 6/6 and 7/7. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000` | exit 0; current config contract valid, doctor ready. |
| `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` | exit 0; repository baseline verified. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json` | exit 0; tasks=9, done=1, open=8, findings=0. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | exit 0; build, hygiene, generated sync, 105-skill integrity, routing findings=0, dependency, planning, doctor contract and tests passed. |
| `git diff --check` | exit 0; only Git line-ending conversion warnings. |

## N/A and open acceptance

| Type | Reason | Alternative verification | Evidence | Expires/recovery |
| --- | --- | --- | --- | --- |
| `platform_na` host load | Planning-only task does not change host state; probing would not validate a new host capability. | Repo planning verifier and full gate. | This file and full-gate output. | Run a fresh native probe in the first task that changes a host surface. |
| `gate_na` live workflow | No product behavior or user workflow was added. | Product/Phase acceptance remains explicitly pending. | Roadmap and task manifest. | Execute the Phase-specific real workflow before any `live_accepted` claim. |
| `gate_na` external refresh/apply | Reference shelf correction is `SMV-P0-002`; running refresh or changing installed capabilities would cross this task boundary. | Read current manifest, local revisions and deprecation notice. | Sources table above. | Execute only inside `SMV-P0-002` with its rollback and supply-chain checks. |

## Rollback

Remove or restore only the files listed by `SMV-P0-001`, rerun `build.ps1`, the planning verifier and the full gate, and preserve all skill/MCP/audit/import and host-local state. Do not use whole-worktree reset/checkout as rollback.

## Truth boundary

This evidence can close only `SMV-P0-001` at `planning_contract`/repo-verifier scope. `SMV-P0-002` through `SMV-P0-009`, Phase 0 product code, host loading and live workflow acceptance remain open.

## 2026-08-01 rule-governance addendum

- Added `docs/product/rule-governance-adoption-matrix.md` and refined PRD/architecture/roadmap around `common + platform_delta + project_action` responsibility coverage.
- Adopted the reference repository's layering, minimization and native-evidence patterns; adapted fixed headings, byte/line budgets and wrappers into configurable profiles; rejected central registry/sync/cross-repo writeback and heavy policy infrastructure.
- Re-read `D:\CODE-other\governed-ai-coding-runtime` at clean revision `bbf5aba4b221ecf5ac0279ad41c9c51c104b4191` and the current 2026-08-01 Codex manual sections for AGENTS discovery/customization/rules. No reference script was run and no external file was changed.
- This addendum strengthens the planning contract only. Rules Advisor discovery, findings and apply remain P1/P2 work.
