# SMV-P6-008 Native Invocation Trace Evidence

**task**: `SMV-P6-008`
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

This slice adds a pure trace normalizer and a bounded host-event adapter:

- `src/Domain/NativeInvocationTrace.ps1`
- `src/Infrastructure/NativeInvocationTraceAdapters.ps1`
- `tests/Unit/NativeInvocationTrace.Tests.ps1`
- `docs/change-evidence/20260807-p6-native-invocation-trace.md`

The versioned trace schema separates `listed`, `selected`, `injected`, `executed` and `abstained`. A listed event alone stays `host_evaluation_partial` with `invocation_observable=false`; injected without executed remains partial; abstention is an explicit outcome; and unknown event types or execution without injection fail closed at `truth_level=unknown`. Only an observed fresh injected+executed pair can reach the schema's `host_loaded` level. This is a contract capability, not fresh host evidence.

The adapter maps bounded host event aliases (`skills/list`, `skill_selected`, `skill_injected`, `skill_executed`/`skill_invoked`, and abstention variants) into the normalized schema. Unknown aliases are preserved as unknown and produce a finding rather than being guessed. The normalizer allowlists event fields, hashes trace/event/correlation identifiers, drops payload/args/headers/token-like fields and applies `Protect-OperationSensitiveString` to reasons. It emits an evaluation receipt with status/truth level and keeps `provider_calls=0`, `native_mutations=0`, `writes=0`.

## Red-green and verification evidence

- RED: `Invoke-Pester tests/Unit/NativeInvocationTrace.Tests.ps1` after the fixture-only test addition reported `4 failed, 0 passed`; after correcting the fixture's missing nullable properties, the failures were the expected missing `New-NativeInvocationTrace`/`ConvertTo-NativeInvocationTrace` feature errors.
- GREEN: `Invoke-Pester tests/Unit/NativeInvocationTrace.Tests.ps1` → `4 passed, 0 failed, 0 skipped`. Cases cover listed-only visibility, injected-without-execution partial truth, explicit abstention, unknown-event fail-closed behavior and secret redaction.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success`.
- DEPENDENCY REGRESSION: `NativeInvocationTrace.Tests.ps1`, `HostCapabilityAdapter.Tests.ps1` and `HostCapabilitySnapshot.Tests.ps1` → `16 passed, 0 failed, 0 skipped`.
- HOTSPOT: domain/adapter source scan passed with no file, network, terminal or clock effects and no non-zero side-effect counters.

Full quality gate was intentionally not run in this slice and is not a pass claim. No native App Server/CLI probe was required or executed for this repository contract slice.

## Truth boundary and rollback

This is repository-verified only. The trace schema does not prove that the current host emits these events, that a real host injected a full `SKILL.md`, or that a business workflow was accepted. `host_loaded` and `live_accepted` remain `not_run`; P6 remains `planning_contract`, runtime migration has not started, and profile/router/cold-load retirement remains open.

To roll back this slice, remove the two trace modules, focused test and evidence file, and restore `SMV-P6-008` to `pending` in the manifest/plan/todo. Keep P6-001 through P6-007 evidence, generated output, host configuration and unrelated concurrent watch-runtime changes unchanged.
