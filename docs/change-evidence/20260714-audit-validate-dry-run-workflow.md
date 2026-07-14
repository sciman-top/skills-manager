# 2026-07-14 Audit Validate Dry-Run Workflow

- rule_ids: R1, R2, R3, R4, R6, R7, R8, E4, E5
- risk: low; repository-side validation and dry-run orchestration only
- target_disposition: make `recommendations validation -> preflight -> dry-run -> four-category report` fail closed and machine-verifiable without changing apply authorization
- run: `reports/skill-audit/20260714-014727-970`

## Basis

- The former CLI required separate preflight and dry-run commands. The dry-run implementation revalidated schema, source coverage, decision quality, and installed-state freshness, but did not enforce the preflight prompt-contract and user-profile checks as one transaction-like workflow.
- `dry-run-summary.json` recomputed display indexes instead of carrying an explicit original-index invariant through the plan.
- There was no single report tying recommendation validation, preflight, input stability, dry-run, `persisted=false`, and the four ordered categories together.
- A local command cannot make the external AI research judgment that creates `recommendations.json`; missing recommendations must be reported as `recommendations_missing`, not presented as automatic generation.

## Changes

- Added `src/Commands/AuditTargets.Workflow.ps1` with the `校验预演` / `validate-dry-run` orchestration path.
- Kept existing `预检`, direct apply internals, and explicit `--apply --yes` behavior compatible. Normal CLI dry-run and non-stale `应用确认` now use the validated workflow.
- Added `workflow-report.json` with stage status, recommendation SHA-256, before/after input fingerprints, live-state comparison, report paths, `persisted`, changed counts, and four categories in fixed order.
- Added explicit `original_index` to each skill/MCP add/remove plan item and preserved it in console and JSON summaries.
- Added per-category `empty_reason` so the unified report is sufficient for a four-category no-op summary.
- Split orchestration into a focused source fragment instead of growing the existing 1,300+ line apply module.

## Runtime Evidence

- `recommendations_sha256`: `0606a94bd689594c9b6e88923ca4e706abe6da9808e47374fed63e8c8139c68e`
- `workflow-report.json`: `success=true`, `persisted=false`, `input_stability.preflight_matched=true`, `input_stability.live_state_matched=true`, `input_stability.matched=true`.
- All workflow stages passed: recommendations validation, preflight, dry-run, and input stability.
- Preflight issues: 0; prompt contract matched; managed-skill, external-skill, and MCP staleness were all false.
- Category order and counts: `1:add:0`, `2:remove:0`, `3:mcp_add:0`, `4:mcp_remove:0`.
- Final generated runtime evidence: `docs/change-evidence/20260714-audit-runtime-dry-run-20260714-014727-970-054738.md`.

## Verification

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` -> exit 0.
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` -> exit 0; E2E summary `12 passed / 0 failed`.
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0; the existing `apply_targets` performance warning remained non-blocking.
4. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` -> exit 0.
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 审查目标 校验预演 --recommendations reports\skill-audit\20260714-014727-970\recommendations.json --dry-run-ack "我知道未落盘"` -> exit 0.
6. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` -> exit 0; full local quality gates passed, including generated-sync, skill integrity, routing observation, dependency baseline, doctor JSON contract, Unit, and E2E tests.

## Existing Dirty Worktree Boundary

- Before this slice, the worktree already contained skill-routing governance, audit snapshot/external capability, MCP/config, release packaging, reference refresh, generated `skills.ps1`, tests, and runtime evidence changes.
- This slice intentionally touched only `build.ps1`, `skills.ps1` (generated), `src/Commands/AuditTargets.Apply.ps1`, `src/Commands/AuditTargets.Args.ps1`, `src/Commands/AuditTargets.Plan.ps1`, `src/Commands/AuditTargets.Workflow.ps1`, `tests/Unit/AuditTargets.Tests.ps1`, this evidence, and the final runtime evidence.
- No unrelated import, routing, MCP, release, reference, or target-repository change was reverted or reordered.

## N/A Boundaries

- recommendations apply: `gate_na`; reason = the user requested validation and dry-run, not live installation/removal; alternative_verification = preflight + validated dry-run + workflow report; evidence_link = this file and the final runtime evidence; expires_at = explicit user approval of `--apply --yes`.
- live Codex/MCP projection or process restart: `platform_na`; reason = outside this repository-side workflow and not authorized; alternative_verification = file-level fingerprints, live mapping fingerprints, strict doctor, and no-persistence report; evidence_link = `workflow-report.json`; expires_at = explicit live-projection authorization.

## Rollback

- Remove only `src/Commands/AuditTargets.Workflow.ps1`, its single assembly entry in `build.ps1`, the new command aliases/dispatch in `AuditTargets.Args.ps1`, the original-index additions in `AuditTargets.Plan.ps1` and `AuditTargets.Apply.ps1`, the `应用确认` workflow call change, the focused tests, this evidence, and the final generated runtime evidence.
- Re-run `build.ps1` after reverting source fragments so `skills.ps1` is regenerated from the preserved source tree.
- Do not use whole-file restore on shared dirty files and do not revert pre-existing routing, snapshot, MCP, release, reference, or generated changes.
