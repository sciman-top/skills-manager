# P6 Deep-Audit Remediation Evidence

**date**: 2026-08-09  
**track**: `P6 Host-Native Skill Lifecycle Reset` follow-up remediation  
**baseline_revision**: `52279b06aa9d7f4ea2fffd1b79499d71a79629a2`  
**truth_boundary**: repository remediation plus explicit native projection; final full gate is authoritative only through the immutable receipt and pointer produced after this evidence ledger is stabilized

## Scope and stop conditions

The deep audit identified four root contracts that required correction before a
new closeout claim: the residual watch-runtime control channel, an overloaded
host truth ladder, metadata plans presented as projected host metadata, and a
full gate without source-drift or immutable-receipt binding. This evidence is a
single remediation ledger for those dependent slices. The final full gate must
run once after this ledger and the manifest/plan/todo truth are stable; its
immutable receipt and `reports/quality-gates/current.json` pointer are the only
current gate authority. Earlier full results remain point-in-time evidence.

## Slice A: retire the host watch runtime channel

### Root cause

The compatibility skill already declared watch execution retired, but the
active command hook still contained canonical target self-pause, fleet
create/update/delete, receipt-authorized shutdown, prompt-digest provenance,
runtime-generation, automation-root, and fleet-state branches. The installer
projected all of that metadata into `~/.codex/hooks.json`, so the source still
defined a potential recovery control channel even though no legacy automation
was active.

### RED evidence

- `WatchRetirement.Tests.ps1`: the new heartbeat mutation/power contract failed
  `4 passed / 1 failed` because canonical recovery input returned `allow`.
- The installer projection contract then failed `5 passed / 1 failed` because
  the host command still contained all revision-3 prompt/runtime/root fields.
- The active-surface contract failed `6 passed / 1 failed` because the wrapper
  still exposed the retired parameters and state readers.
- The legacy-doctor migration contract failed `6 passed / 1 failed` because the
  installer recognized only an exact source hash rather than the managed
  legacy markers needed after source removal.

### Implementation

- Reduced `CrossThreadGuardPolicy.ps1` to the cross-task guard plus the retired
  watch policy: read-only `view` is allowed; heartbeat automation mutation and
  heartbeat power are denied; code-mode automation mutation is denied; only an
  explicit ordinary-turn `delete` for
  `watch-interrupted-task-v1-target-thread-id-<current-session>` is allowed.
- Removed prompt hashes, runtime generation, automation/fleet state readers and
  every fleet/target recovery function from the active wrapper and policy.
- Changed the installer to revision 4 with only script/policy hash binding.
  It removes the known managed legacy doctor only when both unique legacy
  markers are present and restores every original byte on transaction failure.
- Deleted `Test-WatchGuardRuntime.ps1` and its revision-3 runtime test file.
- Moved decision tests in-process against the pure policy core while retaining
  subprocess smoke tests for malformed input, hash drift and wrong hook event.

### GREEN evidence

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` -> exit 0.
- Focused hook/install/retirement tests -> `41/41` passed, `0` failed in
  `17.47s`. The pre-remediation four-file run was `35/44` in `83.28s`; the old
  revision-3 runtime file and four obsolete tests were removed.
- Repository installer/doctor focused test alone -> `7/7` in `1.97s` after the
  doctor stopped generating prompts or reading runtime state.

### Host projection and live boundary

Before projection, no automation whose TOML contained `watch-interrupted-task`
was found. The pre-change host files were copied to:

`C:\Users\sciman\.codex\backups\cross-thread-guard-20260809-020248`

The governed installer then reported:

- `policy_revision=4`;
- `watch_runtime_status=retired_fail_closed`;
- hook SHA-256 `8e218672079fedcdd78bb7d1aa90b89948858de964a53f93ce186ed03fb30aa7`;
- policy SHA-256 `937fb4fcb1bdaea74200b7558449b59d94db6677ec086971863f2fe4f7c2e988`;
- source/host parity for both files;
- `legacy_doctor_removed=true`.

Fresh child-process invocation of the installed wrapper produced:

| Probe | Decision |
|---|---|
| heartbeat create | `deny` |
| heartbeat update/resume | `deny` |
| heartbeat power | `deny` |
| exact current legacy delete | `allow` |
| negated delete | `deny` |
| read-only view | `allow` |

The file-level doctor reports `static_configuration_ready=true`, all seven
policy simulations true, and `overall=soft_guard_only`. No retired metadata is
present in the installed hook command and the legacy runtime doctor is absent.

A real native automation sentinel delete for the nonexistent id
`watch-interrupted-task-v1-live-probe-retirement-20260809` reached the native
automation implementation and returned `deleteStatus=not_found` instead of a
hook denial. This confirms the already documented host boundary: specialized
native tool paths can bypass the non-managed command hook. No real automation
was created, updated or deleted. Therefore the valid claim is retired runtime
and command-hook defense in depth, not absolute host enforcement or live
acceptance.

## Slice B: split inventory, evaluation, invocation and live truth

### Root cause and RED

`NativeInvocationTrace` used `host_loaded` for fresh injected plus executed
events, while the P6 manifest used the same label for a fresh 124-skill App
Server inventory. The first focused trace run was `3/5`: listed-only returned
`host_evaluation_partial` instead of `host_inventory_loaded`, and executed
returned `host_loaded` instead of `host_invocation_observed`. The planning RED
then rejected the old current manifest expectation and showed that the verifier
had no separate invocation field and still accepted `live_accepted=failed`.

### Implementation and GREEN

- Trace truth levels are now `unknown`, `host_inventory_loaded`,
  `host_evaluation_partial`, and `host_invocation_observed`.
- Only fresh injected plus executed evidence marks the invocation receipt
  complete. Listed-only inventory remains non-invocation evidence.
- The current P6 manifest is schema v2 with
  `host_inventory_loaded=observed`,
  `host_evaluation=host_evaluation_partial`,
  `host_invocation_observed=not_observed`, and
  `live_accepted=not_accepted`.
- At this historical checkpoint, because the remediation changed
  executable/config/test inputs, the manifest temporarily recorded
  `full_gate=stale` until the single final full run. The later
  receipt-authority contract superseded that transient field: the current
  tracked manifest delegates full status to the exact-current-source receipt
  and its `reports/quality-gates/current.json` pointer.
- The generic planning verifier rejects inventory-to-invocation promotion and
  rejects `failed` as a substitute for missing live observability.

Focused GREEN:

- `NativeInvocationTrace.Tests.ps1` -> `5/5`.
- `ProductPlanning.Tests.ps1` -> `15/15` including the new over-promotion and
  invalid-live-state negative fixture.
- `tasks/plan.md` and `tasks/todo.md` now point to the schema-v2 manifest truth;
  the older P6 closeout evidence retains its point-in-time data and contains an
  explicit terminology correction rather than silently rewriting history.

## Remaining ordered remediation

1. Split inventory/evaluation/invocation/live truth states.
2. Replace metadata-materialization claims with plan-only measurement and real
   host-inventory cost reporting.
3. Bind the final full gate to source fingerprints and an immutable receipt.
4. Converge dynamic truth documents, expand high-risk pairwise routing corpus,
   run the single final full gate, and promote a clean verified projection.

## Slice C: separate advisory metadata plans from observed host inventory

### Root cause and RED

`Plan-NativeMetadata` compacted descriptions for an advisory budget, but the
native projection plan copied that field into a generic `metadata.description`
property. The apply path only creates a junction to the source package and
never writes a compacted `SKILL.md`, so that property falsely implied host
materialization. The old verifier inspected only four repository files and
could not prove that the expected 106 managed skills were visible in a fresh
host inventory. It also had no safe representation for an unknown host
metadata budget.

Focused RED was observed before implementation: the new contract suite reported
`8/14` passed and `6` expected failures for missing `projection_effect`, missing
source/planned description separation, missing host-inventory coverage, and
missing unknown-budget semantics.

### Implementation

- `NativeMetadataPlanner` now emits `projection_effect=plan_only` and
  `pass_scope=advisory_planning_contract`; retained items use
  `planned_description`, never a generic materialized `description`.
- Unknown host metadata budgets expose `host_budget_status=unknown` and
  `host_budget_pass=null`; the planner never promotes a character/token
  estimate into host acceptance.
- Native projection rows now separate `planned_description` from
  `observed_source_description`, declare
  `materialization=source_package_junction`, and keep the junction action
  explicitly plan-only. The source `SKILL.md` remains the only materialized
  description.
- `verify-native-skill-metadata.ps1` reports representative repository samples
  separately from an optional fresh host snapshot. When supplied with a host
  inventory and the native projection receipt, it resolves expected semantic
  names from each projected `SKILL.md` frontmatter (falling back to fixture
  directory leaves), checks every expected skill, and reports actual totals,
  maximum, average, and advisory-limit counts. Missing host budget remains
  `host_budget_pass=null`.
- The verifier is schema v2. Without explicit host inputs it reports
  `observed_inventory.status=not_provided` and only evaluates the repository
  corpus; this is not host-loaded or live acceptance.

### GREEN and real host inventory evidence

- Focused planner/projection/metadata tests -> `14/14` passed, `0` failed.
- Affected regression set (metadata, projection, catalog, eligibility, host
  snapshot/adapter and invocation trace) -> `37/37` passed, `0` failed.
- Build -> exit 0; generated-sync, config contract, routing contract and both
  planning verifiers -> exit 0 with `0` findings.
- Repository-only metadata verifier -> `pass=true`, `samples=4`, `cases=10`,
  `observed_inventory=not_provided`, `host_budget_pass=null`.
- Fresh App Server snapshot `hcs-2003353adbc51a2f` plus native projection
  receipt -> `pass=true`, `observed=124`, `expected=106`, `matched=106`,
  `missing=0`; expected managed-skill description totals are `33,392`
  characters, maximum `1,005`, average `315.02`, and `23` over the 384
  advisory limit. Host metadata budget remains unknown and
  `host_budget_pass=null`.

This evidence proves a corrected repository contract and fresh inventory
visibility only. It does not prove host selection, full body injection,
execution, business acceptance or a current full quality gate.

## Slice D: bind quality-gate results to stable source and immutable receipts

### Root cause and RED

The canonical gate serialized concurrent gate processes but did not bind a run
to source identity. `-AllowDirtyWorktree` allowed a pre-existing dirty tree, yet
there was no start/end HEAD, index or tracked-worktree comparison, so a file
could change during a long full run without invalidating its final success
message. Runtime output also had no immutable per-run receipt; a mutable latest
file could not prove which source state a historical result covered.

The focused RED was `28/29`: the new behavioral test failed because
`QualityGateIntegrity.ps1` did not exist. The test creates an isolated Git
repository, fingerprints it, changes a tracked file, and requires
`quality_gate_source_drift`; it also requires a write-once run receipt plus a
hash-bound `current.json` pointer.

### Implementation and GREEN

- A minimal `QualityGateIntegrity.ps1` helper captures `HEAD`, the Git index
  tree, and a SHA-256 of the tracked `git diff HEAD` state. Untracked/ignored
  reports are not source identity.
- The comparison returns `quality_gate_source_drift` when any of the three
  fields changes. A dirty starting tree is valid only when the existing gate
  invocation allows it; `-AllowDirtyWorktree` does not relax the end-to-start
  comparison.
- Each run writes a unique `reports/quality-gates/qgr-*.json` receipt with
  `immutable=true`, profile, status, dirty-start policy, source start/end,
  comparison and per-gate timings. Existing run IDs cannot be overwritten.
- `reports/quality-gates/current.json` is only a latest pointer containing the
  immutable path and its SHA-256. Reports remain ignored runtime data.
- The gate emits a pass message only after end fingerprint comparison and
  receipt creation. Drift exits `78`; absent terminal fingerprint/receipt is
  `terminal_evidence_unavailable`, never pass.

Focused `QualityGateScripts.Tests.ps1` is GREEN at `29/29`. A real quick gate
with a pre-existing dirty tree passed all 16 build/contracts in `16,840ms` and
wrote immutable receipt `qgr-20260808-184256-6545f2e3`. Its start/end values
were identical:

- HEAD `52279b06aa9d7f4ea2fffd1b79499d71a79629a2`;
- index tree `0e914764d757c5731ca5090b5fdbc2731f2721c0`;
- tracked worktree SHA-256
  `c2d1f05dc01e2212fe0847124921de28bc8c93b541726ae6846833cd05538e1b`.

The pointer hash matches the immutable receipt, `source_comparison.pass=true`,
and all 16 gate rows are present. This quick receipt validates integration but
does not replace the final full gate. At that historical point the manifest
still used the temporary `full_gate=stale` hold; the current manifest instead
uses `full_gate=receipt_authoritative` and delegates status to the exact-current
source receipt.

## Slice E: pairwise activation risks and dynamic product truth

### Pairwise corpus boundary

The earlier activation corpus covered ten generic direct, indirect, negative,
ambiguous and no-skill prompts around four representative skills. It did not
exercise the high-risk collisions between primary artifact plugins, portable
fallback skills, live-session control and browser/test-authoring workflows.
That corpus could verify deterministic input structure, but it could not
support a broad claim that every visible skill would be selected correctly for
every task.

The corpus now adds 15 competing targets in five groups and 16 pairwise cases:

- Word, PDF, spreadsheet and presentation artifact create/read paths compare
  primary artifact plugins with portable fallbacks.
- Spreadsheet cases separate standalone workbook creation, an existing live
  Excel add-in session and portable fallback.
- Browser cases separate signed-in Chrome, the in-app Browser, terminal
  Playwright automation, local webapp testing, Playwright test authoring,
  cloud `agent-browser` use and an explicit no-browser/no-side-effect request.
- Nine declared dimensions cover `artifact_create`, `artifact_read`,
  `portable_fallback`, `signed_in_session`, `live_control`, `local_testing`,
  `test_authoring`, `no_browser` and `side_effect_boundary`.

`verify-native-skill-metadata.ps1` now fails closed on missing dimensions,
uncovered dimensions, duplicate/unknown targets, invalid groups and pairwise
case/count drift. The negative fixture removes `side_effect_boundary`; its
first execution exposed a test-root containment error because the mutated
corpus lived under Pester `$TestDrive` while the verifier still used the real
repository root. After binding the fixture root correctly, focused metadata
tests passed `4/4`, and the repository metadata verifier reported
`targets=15`, `groups=5`, `pairwise_cases=16`, all nine dimensions covered and
zero findings. Build, config, routing and both planning contracts also exited
zero.

This is a deterministic corpus contract, not a probabilistic or mathematical
proof that 124 visible skills will correctly match every possible natural-
language task. The current host truth remains `host_evaluation_partial` until
real host selection, full body injection and execution are observable; live
acceptance remains separate.

### Dynamic product truth

The product index and roadmap duplicated an obsolete point-in-time closeout:
they still described P6 as pending or `planning_contract`, copied
`runtime_migration=not_started`, `host_loaded=not_run`, and
`full_gate=passed`, and labelled the current plan as Phase 5. This contradicted
the schema-v2 manifest and could turn an older full receipt into current truth.

The planning verifier now requires both current product documents to declare
`CURRENT_PHASE_TRUTH_SOURCE: tasks/skills-manager-vnext-phase6.tasks.json`.
The focused RED was `15/16`: the old verifier accepted documents with no valid
truth-source marker. After the docs delegated task counts, truth ladder, full
gate and `latest_evidence` to the manifest, the focused suite passed `16/16`.
Admission-time and older full results remain explicitly labelled historical;
they were not rewritten as current acceptance.

## Slice F: remove inactive PowerShell scans and success-output noise

### Measured hotspot and RED

The last timing report showed the complete test suite at `321,561ms`, while
the quick receipt showed `powershell-runtime-policy=7,905ms`; the test suite is
still the dominant full-gate cost. The PS7 verifier recursively traversed the
entire repository and treated ignored `.txn/build-*/agent.backup/*.ps1` files
as active source. It also parsed the 1.5 MB generated `skills.ps1` bundle into
an AST after already checking that bundle's version floor, encoding and legacy
runtime literals.

Two focused REDs made the boundary executable:

- a `.txn` backup containing `powershell.exe` was incorrectly reported as
  `legacy_runtime_invocation_detected`;
- `Start-Process powershell.exe` in the generated bundle was caught only by
  the duplicate estate scan, not by the dedicated generated policy.

The focused suite was `9/11`, with exactly those two failures.

### Minimal optimization and GREEN

- In a real Git worktree the verifier now enumerates tracked plus untracked,
  non-ignored `*.ps1` paths through Git; hermetic non-Git fixtures retain the
  recursive fallback.
- `.txn/`, generated/cache/import/report roots and test fixtures are not part
  of the active source estate.
- `skills.ps1` is removed only from the duplicate AST estate scan. Its
  dedicated fail-closed check now covers direct invocation, `Get-Command` and
  `Start-Process` forms in addition to the retired environment switch; build
  and generated-sync remain independent mandatory gates.
- The canonical quality runner invokes native metadata verification in its
  concise summary mode. `-Json` remains available for evidence and debugging,
  but a successful full run no longer prints all 26 corpus cases.

Focused GREEN is `PowerShellRuntimePolicy.Tests.ps1=11/11` and
`QualityGateScripts.Tests.ps1=30/30`. In the focused run the current-repository
positive PS7 check dropped from `12.26s` before the change to `6.53s` after it;
a separate fresh-process measurement completed in `7,480ms`, scanned 214
active files and returned zero findings. These measurements are local samples,
not a promise that the final full wall time will improve by the same ratio.
No test, generated-sync, dependency, planning, integrity or source-binding gate
was removed.

## Slice G: include untracked source in gate identity

The first final-candidate full run exited zero in `274,218ms`: all 17 gates
passed, Unit/E2E totaled `1143/1143`, tests took `264,898ms`, the immutable
receipt SHA-256 matched its pointer, and HEAD/index/tracked-worktree start/end
values were identical. The test-suite wall time was `262,897ms`, about 18%
lower than the previous `321,561ms` timing sample.

Fresh `git status` then exposed an integrity gap. A non-ignored untracked
`docs/research/` file was present after the run although it was absent from the
task's earlier status snapshots. Its content belongs to a concurrent research
slice and is preserved untouched. The quality fingerprint intentionally
excluded ignored runtime receipts, but it also accidentally excluded every
non-ignored untracked file, so the full receipt could prove only tracked-source
stability. That run remains a valid tracked-source test result, but it is not
accepted as the final source-complete receipt.

The focused RED was `29/30`: adding `new-source.ps1` to an isolated repository
did not change the fingerprint. The integrity helper now hashes the sorted path
and SHA-256 of every `git ls-files --others --exclude-standard` file, records an
untracked file count, and compares that fingerprint at start/end. A committed
`reports/` ignore fixture proves ignored runtime receipts still do not create
source drift. Focused GREEN is `30/30`.

Because this changed the gate implementation after the first candidate run, a
replacement full run was required. The first candidate remains superseded by
the source-complete receipt selected by the current pointer.

## Slice H: explicit native projection and fresh host revalidation

The repository-owned native skill root was backed up before the explicit
projection apply:

```text
backup=D:\CODE\skills-manager\reports\skill-projection\host-backups\20260809-1022-pre-apply\skills
backup_items=108; backup_junctions=107; backup_physical=.system
```

The explicit `构建生效 -AllowUnverifiedHostProjection` plan/apply then
produced:

```text
receipt_id=nsr-ec3c06d30412c9fc
plan_id=nsp-79afff2fc147affa
status=applied
enabled_total=106; kept_total=106; omitted_total=0; truncated=false
before=106; after=106; changed=0; hash_drift=0
writes=0; native_mutations=0; notification=skills/changed plan_only not_sent
promotion_mode=unverified_override; source_worktree_dirty=true
```

The fresh App Server probe used `skills/list(forceReload=true)` twice in
separate bounded processes. The two snapshots were
`hcs-5d98480adead6aa2` and `hcs-fb864aa228c8eafe`; both had
`status=partial` solely because `metadata_budget` is not exposed,
`skills_inventory.freshness=fresh`, `count=122`, `errors=0`,
`provider_calls=0`, `writes=0`, and `native_mutations=0`. The metadata verifier
paired the first fresh snapshot with the receipt and returned
`pass=true`, `observed=122`, `expected=106`, `matched=106`, `missing=0`,
`unexpected=16`, and `finding_count=0`. The 16 unexpected entries are host
system/plugin skills; the two skills present in the earlier 124-item snapshot
but absent from both current probes were `sites:sites-building` and
`sites:sites-hosting`. No repo or host plugin configuration was changed to
hide or manufacture this external drift.

The hook retirement revalidation returned source/host hash parity, policy hash
parity, `static_configuration_ready=true`, 7/7 policy simulations, and 6/6
fresh child-process wrapper probes. It remains `overall=soft_guard_only` with
`trust_status=unverified_requires_slash_hooks`,
`live_path_status=unverified_requires_fresh_session_probe`, and
`specialized_path_boundary=guardrail_only`; no restart, stop, or kill of the
existing Codex App/runtime was performed.

The current full-gate authority is deliberately delegated to the immutable
receipt selected by `reports/quality-gates/current.json` after this evidence
and the manifest truth are stable. That receipt must independently prove
17/17 gates passed, source start/end parity (including non-ignored untracked
files), and pointer hash parity. This ledger does not promote inventory to
selection, full body injection, invocation, or live business acceptance.

## Slice I: final deep-audit convergence and current gate boundary

The final review of the accumulated P6 changes found two consistency defects
outside the runtime path: the closeout rule ordered the full gate before the
candidate commit even though the receipt binds to exact current source, and
this ledger repeated the obsolete `full_gate=stale` snapshot as if it were
current. Both were repaired with a focused contract test and a documentation
update.

The same review rechecked the high-risk implementation seams:

- the retired watch runtime has no active recovery helper, mutation path or
  runtime generation surface; the remaining hook is a bounded cross-thread
  guard and is documented as defense-in-depth only;
- native trace and host adapter states keep inventory, evaluation, invocation
  and live acceptance separate, and any trace error blocks truth promotion;
- native skill projection keeps aggregate rollback and provenance together;
- quality receipts use schema v2, immutable per-run files, exact source
  binding, gate-row semantics and timing-report binding;
- ordinary parallel test workers use measured longest-processing-time ordering
  from `reports/test-timings/current.json`, with stable filename fallback and
  unchanged serial barriers/max parallelism.

Focused evidence for the corrected seams is:

- `ProductPlanning.Tests.ps1`: RED `17 passed / 1 failed`, then GREEN `18/18`;
- `QualityGateIntegrity.Tests.ps1`: `6/6`;
- `QualityGateScripts.Tests.ps1`: `32/32`;
- `HostNativeSkillLifecycleCloseout.Tests.ps1`: `4/4`;
- `NativeInvocationTrace.Tests.ps1`: `9/9`;
- modified PowerShell parser sweep: `23/23`, and `git diff --check`: exit `0`.

That legacy schema-v1 pointer was subsequently superseded by the schema-v2
candidate receipt described in Slice J. The replacement pointer is structurally
current but records `status=source_drift`, so it is not a passing full-gate
authority. Current truth remains
`host_inventory_loaded=observed`, `host_evaluation=host_evaluation_partial`,
`host_invocation_observed=not_observed`, and `live_accepted=not_accepted`.

## Slice J: exclude Git conversion warnings from tracked-source identity

The first full run on candidate `7d56c212dab69b3ef63e43a4897c3a92642bd099`
produced schema-v2 receipt `qgr-20260809-081512-277f307f`. All 17 gate rows
reported `passed=true`; Unit/E2E totaled `1093/1093`, the isolated suite took
`241,447ms`, the gate-row elapsed sum was `255,041ms`, and historical LPT
matched 90 test files. The terminal receipt nevertheless recorded
`status=source_drift`, with only `tracked_worktree_fingerprint` changed.
Therefore this run is not reported as a passing full gate.

The source itself had not changed: start/end HEAD and index tree were identical,
the tracked worktree was content-clean after the run, and the worktree/index
blob for the generated `skills.ps1` was the same Git object. The false drift
originated in `Get-QualityGateSourceFingerprint`: its generic Git wrapper
merged stderr into stdout, so Git's `LF will be replaced by CRLF` conversion
warning became part of the tracked-diff SHA-256 even when `git diff` contained
no content change.

The focused regression creates an isolated `core.autocrlf=true` repository,
keeps the tracked Git blob unchanged while changing only its worktree line
ending, and requires stable source comparison. It failed before the fix at
`6 passed / 1 failed`. The minimal implementation now hashes only `git diff`
stdout at this call site, suppresses stderr from the hash input, and still
checks the native Git exit code so a real diff failure remains fail-closed.
Focused GREEN is `QualityGateIntegrity.Tests.ps1=7/7` and
`QualityGateScripts.Tests.ps1=32/32`.

A new candidate commit and one replacement full run are still required after
this evidence update. Only a schema-v2 `profile=full`, `status=passed` receipt
whose 17 gate rows, timing binding and exact-current source binding all verify
may close the repository full-gate boundary.

## Slice K: stop wasted gates and remove the duplicate global lock

The exact-source baseline receipt `qgr-20260809-084855-89752648` passed all
17 gates at HEAD `5ff0a30562de9f293108ea06fffe703cad5f1ba1`; its test suite was
`1103/1103` in `281,349ms` with `max_parallel=4`. A controlled
`max_parallel=8` experiment completed in `272,439ms`, only about 3% faster,
and exposed one cross-repository gate-collision failure. The experiment was
rejected: the default remains 4 and no batching or new worker abstraction was
added.

Two smaller changes remove measured waste without weakening the gate set:

- `Invoke-QualityGate` now compares the current source with the run start after
  every successful gate. The behavioral RED continued into `repo-hygiene`
  after build drift (`32/33`); GREEN stops with exit 78, a one-row receipt and
  no next-gate output (`33/33`). This does not cancel a gate already running,
  but it prevents every later gate from consuming time after drift.
- The runner already used a mutex whose name is derived from the repository
  root, yet it also scanned every host `run-local-quality-gates.ps1` process.
  That duplicate global scan blocked independent fixture repositories and was
  the max-8 collision root cause. A real two-repository RED proved the false
  exit 75; the scan was deleted while the repo-scoped mutex remained. GREEN
  proves same-repository serialization and different-repository independence,
  with the focused file at `33/33`.

An overlapping full run while this slice was being edited ended as
`qgr-20260809-090022-0019b3bf`, `status=source_drift`, after build and tests;
it did not run the remaining 15 contracts. It is not acceptance evidence. A
fresh exact-source full receipt is still required after the Slice K candidate
is committed.

## Rollback

Repository rollback is limited to the files in this remediation slice. Host
rollback restores the four backed-up files from the timestamped backup above;
it must not touch unrelated hooks or automations. No Codex process was restarted
or stopped.
