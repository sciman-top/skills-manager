# SMV-P6-009 Native/Legacy Shadow Comparison Evidence

**task**: `SMV-P6-009`
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

This slice adds a zero-write comparator for paired native-only and legacy result files:

- `scripts/compare-native-and-legacy-skill-selection.ps1`
- `tests/Unit/NativeSkillSelectionShadow.Tests.ps1`
- `docs/change-evidence/20260807-p6-native-legacy-shadow.md`

The comparator reuses the P6-007 activation corpus contract as the expectation source, reads native and legacy observations independently, and never invokes either selector. Native observations remain authoritative; legacy output is comparison-only and cannot override runtime. A missing native trace stays `host_evaluation_partial`, is excluded from native regression scoring, and cannot be converted into a false negative. Disagreements remain explicit in the report.

The report now exposes a zero-regression threshold for evaluated native cases (`max_native_false_positive_count=0`, `max_native_false_negative_count=0`, partial cases excluded) and a staged disposition. The fixture disposition is `retire_legacy_semantic_authority_keep_compatibility_shadow`: the legacy semantic selector is eligible for staged retirement, while the compatibility shadow remains until the P6-010/P6-012 removal gate and fresh host evidence. This is a report decision only; it does not mutate runtime, profile state or host state.

## Red-green and verification evidence

- RED (initial feature): `Invoke-Pester tests/Unit/NativeSkillSelectionShadow.Tests.ps1` → `2 failed, 0 passed`; the expected feature-missing condition was the absent comparator script.
- DEBUG RED (implementation defect): after the initial comparator implementation, the same fixture exited `1` without JSON and direct reproduction reported `Argument types do not match`. A minimal PowerShell reproduction isolated the cause to `@($genericList).Count`; the fix changed only the three report count expressions to native `.Count` access.
- RED (threshold/disposition contract): after adding the new assertions, the focused test reported `1 passed, 1 failed`; the failure was the expected missing `regression` output.
- GREEN: `pwsh -NoProfile -Command '& { $r = Invoke-Pester -Path "tests/Unit/NativeSkillSelectionShadow.Tests.ps1" -PassThru; ... }'` → `2 passed, 0 failed, 0 skipped`.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit `0`, `Build success`.
- DEPENDENCY/FOCUSED REGRESSION: P6-009 plus P6-006/P6-007/P6-008 dependency tests (`NativeSkillSelectionShadow`, `NativeSkillMetadata`, `NativeInvocationTrace`, `NativeSkillProjection`, `SkillProjection`, `NativeMetadataPlanner`, `HostCapabilityAdapter`, `HostCapabilitySnapshot`, `SkillCatalogCompiler`, `SkillEligibilityPolicy`) → `68 passed, 0 failed, 0 skipped`.
- PAIRED FIXTURE REPLAY: the isolated two-case fixture exercised by the focused test and direct comparator run → `pass=true`, `paired_case_count=2`, `disagreement_count=2`, `provider_calls=0`, `native_mutations=0`, `writes=0`.
- PAIRED METRICS: native `evaluated=1`, `partial=1`, `false_positive=0`, `false_negative=0`, `mean_ttfv_ms=160`, `tool_rounds=3`; legacy `evaluated=2`, `partial=0`, `false_positive=0`, `false_negative=1`, `mean_ttfv_ms=210`, `tool_rounds=9`; `correction_count=1`, `correction_rate=0.5`.
- REGRESSION/DISPOSITION: native threshold `pass=true`; partial cases were excluded; disposition was `retire_legacy_semantic_authority_keep_compatibility_shadow`, runtime mode `shadow_only`, and full removal gate `P6-010_and_P6-012`.
- HOTSPOT: comparator source scan found no file-write, network, process or clock calls; runtime report counters remained zero.
- CONTRACTS: `scripts/verify-native-skill-metadata.ps1 -Json` → `pass=true`, `finding_count=0`; `scripts/verify-skill-routing.ps1 -Json` → `ok=true`, `blocking=false` with the pre-existing non-blocking `strong_trigger_signal`; `scripts/verify-skills-config.ps1 -Mode enforce` → `valid=true`, `finding_count=0`; `tests/check-generated-sync.ps1 -AllowDirtyWorktree` → passed; both P6 planning verifiers → `pass=true`, `finding_count=0`.
- BOUNDED FRESH CLI PROBE: `scripts/get-codex-app-server-capability-snapshot.ps1 -Mode cli -Cwd D:\CODE\skills-manager -OutputPath <system-temp> -TimeoutSeconds 30` → process `exit_code=0`, `source=cli`, `status=partial`, native probe started and completed. It exposed no selection, full-body injection or execution event, and therefore remains host-evaluation metadata only. No provider call, profile switch or host write occurred.

The provider-backed semantic selection replay was intentionally not executed in this slice because the current task boundary forbids provider calls. The CLI probe above is the safe fresh read-only host observation; it is not `host_loaded` evidence.

## Truth boundary and rollback

This slice is repository-verified only. The comparator proves zero-write shadow behavior, explicit disagreement visibility, partial-trace handling, native authority, metrics and a staged disposition. It does not prove probabilistic native semantic correctness, full `SKILL.md` injection, host invocation, profile/router/cold-load retirement, runtime migration, business acceptance or `live_accepted`.

To roll back this slice, remove the comparator, focused test and this evidence file, then restore `SMV-P6-009` to `pending` in the manifest/plan/todo. Keep P6-001 through P6-008 evidence, generated output, host configuration and unrelated concurrent watch-runtime/import changes unchanged.
