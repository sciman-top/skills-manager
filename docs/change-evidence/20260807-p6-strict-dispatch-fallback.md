# P6-011 Strict App Server Dispatch Fallback Evidence

**date**: `2026-08-07`
**task**: `SMV-P6-011`
**task_status**: `repo_verified`
**truth_level**: `planning_contract`
**runtime_migration**: `not_started`
**host_loaded**: `not_run`
**live_accepted**: `not_run`
**full_gate**: `not_passed`

## Scope and write-set

This slice adds an independent, opt-in strict dispatch seam. Ordinary requests
remain on the host-native main path. An explicit strict request may expose a
small candidate set, require deterministic eligibility results, require a
fresh `host_ai` adjudication receipt, and construct a supported `type=skill`
App Server injection request. The adapter is fixture/plan-only: it never calls
the provider, mutates the native host, writes a session/config, or dispatches a
live App Server request.

The exact P6-011 write-set is:

- `src/Application/StrictSkillDispatch.ps1`
- `src/Infrastructure/AppServerSkillDispatchAdapter.ps1`
- `tests/Unit/StrictSkillDispatch.Tests.ps1`
- this evidence file

The existing watch-runtime, imports, projection, profile-migration and other
concurrent worktree changes were not reverted or reordered.

## Contract

`Invoke-StrictSkillDispatch` enters the fallback only when
`strict_dispatch=true`, `strict=true`, or an explicit `dispatch_mode` of
`strict`/`strict_fallback` is present. It returns `not_requested` for ordinary
or missing opt-in requests and does not construct an injection.

The strict path:

1. rejects a raw candidate list larger than `MaxCandidates` (default `3`);
2. retains only `kind=skill`, enabled candidates with a valid
   `Test-SkillEligibilityResultContract`, `decision=allow`,
   `decision_owner=deterministic_policy`, and no semantic/profile filtering;
3. requires a fresh, accepted `host_ai` adjudication receipt whose candidate
   set exactly matches the bounded eligible set and whose selected names remain
   inside that set;
4. requires an App Server adapter that explicitly advertises item type
   `skill`; and
5. emits only `items[].type=skill` and a shared `NativeInvocationTrace`.

Missing, denied, stale, mismatched or unadjudicated candidates cannot reach the
injection payload. Unsupported App Server skill injection is
`platform_na`, leaving native-only as the primary path. Planned injection is
reported as `host_evaluation_partial`: `listed`, `selected` and `injected` may
be observed, while `executed` and `invocation_observable` remain false.

## Red-green evidence

The first focused run was intentionally executed before production modules
existed:

```text
pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Unit/StrictSkillDispatch.Tests.ps1'"
```

Result: `0 passed, 10 failed`. Every failure stopped at the expected missing
production command assertion for `Invoke-StrictSkillDispatch` and
`New-AppServerSkillDispatchAdapter`.

The first implementation run exposed a PowerShell parser error in the
`NativeInvocationTrace` event hashtables. Root-cause inspection identified
unparenthesized `-f` format expressions in ordered-hashtable property values;
the four expressions were corrected. A second focused run then exposed the
single-item `supported_item_types` array being returned as a nested value,
which made every supported adapter look `platform_na`. The adapter contract
was corrected to preserve and normalize the array, and its item-contract loop
was corrected to enumerate the returned item array.

Final focused GREEN after those fixes:

```text
pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Unit/StrictSkillDispatch.Tests.ps1'"
```

Result: `10 passed, 0 failed`.

The focused coverage includes:

- ordinary and missing opt-in never entering fallback;
- explicit strict dispatch producing one bounded `type=skill` item only after
  policy allow and host adjudication;
- oversized candidate rejection;
- denied and missing-eligibility candidates never being injected;
- missing/invalid adjudication receipt rejection;
- unsupported App Server `platform_na`;
- shared trace truth (`listed/selected/injected`, no `executed` promotion);
- adapter, injection and dispatch zero-side-effect contracts.

## Verification

The required generated-source check passed:

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
Build success: D:\CODE\skills-manager\skills.ps1
```

After build, the affected focused set passed:

```text
Invoke-Pester -Path tests/Unit/StrictSkillDispatch.Tests.ps1,
  tests/Unit/NativeInvocationTrace.Tests.ps1,
  tests/Unit/SkillEligibilityPolicy.Tests.ps1
```

Result: `16 passed, 0 failed` (`10 + 4 + 2`). The existing App Server
capability adapter contract set also passed: `8 passed, 0 failed`.

The repository contract checks at the pre-status-update boundary returned:

- `verify-host-native-skill-lifecycle-planning.ps1 -Json`: `pass=true`,
  `finding_count=0`;
- `verify-vnext-planning.ps1 -Json`: `pass=true`, `done_count=10`,
  `open_count=2`, `evidence_count=10`, `finding_count=0`;
- strict module hotspot probe: `forbidden_runtime_call_count=0`,
  `provider_calls=0`, `native_mutations=0`, `writes=0`;
- `git diff --check`: no content errors; only the existing repository
  LF/CRLF normalization warnings.

After the reviewed evidence and manifest bookkeeping were synchronized, the
planning checks were rerun and returned `done_count=11`, `open_count=1`,
`evidence_count=11`, and `finding_count=0`; the host-native lifecycle verifier
remained `pass=true` with `finding_count=0`.

No fresh CLI/App Server live probe was run. The bounded App Server evidence is
fixture-only and cannot establish `host_loaded`; no business workflow was
executed, so `live_accepted` remains `not_run`.

## Rollback and boundary

Rollback is limited to deleting the two independent strict-dispatch modules
and their focused test/evidence slice. The native main path, host state,
profile compatibility migration and historical evidence remain untouched.

P6 remains `planning_contract` until P6-012 completes staged legacy removal,
fresh host acceptance and the unique full gate. This slice does not authorize
mandatory pre-turn middleware, a second model, a daemon, provider/auth/model
changes, host/session/profile mutation, `host_loaded`, `live_accepted`, or the
full quality gate.
