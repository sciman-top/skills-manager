# SMV-P6-007 Native Metadata Evaluation Evidence

**task**: `SMV-P6-007`
**task_truth_level**: `repo_verified`
**phase_truth_level**: `planning_contract`
**runtime_migration**: `not_started`
**profile_router_cold_load_retirement**: `not_started`
**host_loaded**: `not_run`
**live_accepted**: `not_run`
**full_gate**: `not_passed`
**provider_calls**: `0`
**native_mutations**: `0`
**writes**: `0`

## Scope and write-set

This slice adds a small, host-owned activation evaluation corpus and a deterministic metadata contract verifier:

- `config/native-skill-activation-corpus.json`
- `scripts/verify-native-skill-metadata.ps1`
- `tests/Unit/NativeSkillMetadata.Tests.ps1`
- `overrides/custom/capability-router/agents/openai.yaml`
- `docs/change-evidence/20260807-p6-native-metadata-evaluation.md`

The corpus has ten cases across `direct`, `indirect`, `negative`, `ambiguous` and `no_skill`. It includes four representative metadata targets and one formerly unreachable target (`grill-with-docs`). Negative cases require abstention and ambiguous cases declare a bounded `minimal_set`; no-skill controls have no required or forbidden skill. The corpus is an expectation source only. It does not call the router, rank candidates, or assign semantic confidence.

The verifier checks metadata source presence, description length, unique activation groups, non-overlapping observable trigger phrases, category coverage, required/forbidden boundaries, case counts, formerly-unreachable counts and the declared native-only/fallback metric taxonomy. It reports `decision_owner=host_ai`, `semantic_selection_applied=false`, `provider_calls=0`, `native_mutations=0` and `writes=0`. The explicit 384-character metadata limit accommodates the existing 350-character `grill-with-docs` frontmatter without rewriting an external/generated skill; an injected 400-character metadata fixture is rejected.

The capability-router override now describes a deterministic policy-validation/fallback role and keeps host semantic selection, negative constraints, profile immutability and host-state immutability authoritative. `allow_implicit_invocation` remains unchanged for the P6 compatibility window; default-path retirement remains P6-010/P6-012 scope.

## Red-green and verification evidence

- RED: `Invoke-Pester tests/Unit/NativeSkillMetadata.Tests.ps1` before adding the verifier/corpus reported `2 failed, 0 passed`; the direct probe confirmed the expected feature-missing error: `scripts/verify-native-skill-metadata.ps1` was not recognized as a script file.
- GREEN: `Invoke-Pester tests/Unit/NativeSkillMetadata.Tests.ps1` → `2 passed, 0 failed, 0 skipped`. The tests cover the complete category contract and fail-closed overlong metadata.
- METADATA VERIFIER: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-native-skill-metadata.ps1 -Json` → `pass=true`, `target_count=4`, `case_count=10`, `formerly_unreachable_skill_count=1`, `finding_count=0`.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success`.
- DEPENDENCY/FOCUSED REGRESSION: P6 metadata, routing, projection, planner, catalog and eligibility tests → `54 passed, 0 failed, 0 skipped`.
- GENERATED SYNC: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/check-generated-sync.ps1 -AllowDirtyWorktree` → passed; consecutive build hashes agree.
- CONFIG CONTRACT: `scripts/verify-skills-config.ps1 -Mode enforce` → `valid=true`, `finding_count=0`.
- ROUTING CONTRACT: `scripts/verify-skill-routing.ps1 -Json` → `ok=true`, `blocking=false`; one pre-existing non-blocking `strong_trigger_signal` warning remains.

Full quality gate was intentionally not run in this slice and is not a pass claim.

## Truth boundary and rollback

This is repository-verified only. It does not prove probabilistic host selection, full `SKILL.md` injection, native invocation, host loading, business acceptance or runtime migration. P6 remains `planning_contract`; profile/router/cold-load retirement remains open, and `host_loaded`/`live_accepted` remain `not_run`.

To roll back this slice, restore the prior capability-router `agents/openai.yaml`, remove the activation corpus, verifier, focused test and this evidence file, and restore `SMV-P6-007` to `pending` in the manifest/plan/todo. Keep P6-001 through P6-006 evidence, generated output, host configuration and unrelated concurrent watch-runtime changes unchanged.
