# P6-012 Host-Native Skill Lifecycle Closeout Evidence

**date**: `2026-08-08`
**task**: `SMV-P6-012`
**task_status**: `done`
**truth_level**: `repo_verified`
**phase_truth_level**: `repo_verified`
**runtime_migration**: `native_projection_applied_unverified_dirty_tree`
**profile_router_cold_load_retirement**: `native_default_legacy_compatibility_only`
**host_evaluation**: `host_evaluation_partial`
**host_loaded**: `accepted_124_of_124_fresh_inventory`
**live_accepted**: `not_accepted_observability_gap`
**baseline_full_gate**: `passed_1097_of_1097`
**current_tree_full_gate**: `passed_1121_of_1121`

## Scope and boundary

This slice completes the repository-side staged removal and closeout for the
P6 host-native lifecycle reset. The generated default path uses native
snapshot, catalog, eligibility, metadata and projection seams. Legacy routing
is compatibility-only, and `profile_compatibility` is a read-only migration
view with `reachability_authority=none`.

The authorized native projection updated only the repository-owned skill
projection surface; provider, auth, model, sandbox, session, plugin and MCP
state were not changed. Concurrent watch-runtime, import and reference-shelf
changes were not reverted or reordered. Repository verification and fresh
inventory do not prove universal semantic selection, native full-body
injection events or business acceptance.

## Focused red-green evidence

The staged-removal implementation and recovery slices recorded these focused
RED -> GREEN transitions:

- profile compatibility evaluation: `3/6` -> `6/6`;
- maintenance/PS7 admission: `31/33` -> `33/33`;
- capability-routing compatibility: `5/7` -> `7/7`, corpus `30/30`;
- generated-bundle caller-scope pollution: `18/34` -> `34/34`;
- gate runner contract: `25/26` -> `26/26`;
- full-gate single-flight contract: `26/27` -> `27/27`;
- stale profile benchmark and typed-core planning contracts: `4/4` and `7/7` GREEN after P6 compatibility correction;
- hidden-worker incompatibilities were reproduced for
  `SelectionCancellation.Tests.ps1` and `WatchRuntimeArming.Tests.ps1`; both
  pass in the runner's fail-fast in-process lane (`3/3` in 1.66s and `7/7` in
  27.78s).

The integrated focused sets before full also passed `221/221` and `47/47`,
with metadata/config/routing/planning/PS7/Lean/generated-sync contracts at zero
findings.

## Full-gate root cause and runner correction

The previous full path put 94 Unit files into one Pester 4.10.1 process. The
last successful timing profile showed `477516ms` total with approximately
`450402ms` of Unit file time; Git, junction, ZIP, verifier and child-process
tests shared global Pester state. Two recovery attempts then stopped producing
CPU/log progress and had no successful terminal summary.

The final runner keeps the test inventory complete but changes the execution
model:

- ordinary files run in isolated Pester processes, bounded by
  `MaxParallel=4`;
- each worker has a 180-second timeout, stdout/stderr and terminal JSON receipt;
- interactive/Git-heavy hidden-worker incompatibilities run first in the fresh
  parent process;
- completed process objects are explicitly disposed;
- Unit and E2E stages remain ordered and zero discovery fails closed;
- a repository-scoped named mutex and older-process probe enforce single-flight
  full execution; a second gate exits `75` with `quality_gate_peer_busy`.

During recovery, three concurrent full gates were observed. Only this task's
already-doomed gate tree was stopped; other tasks and Codex/Cockpit were not
touched. The single-flight guard prevents recurrence.

## Authoritative final verification

Command:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

Terminal result: exit `0`.

```text
build=159ms
tests=300265ms
Unit/E2E=1097 passed, 0 failed
repo-hygiene=passed
generated-sync=passed
skill-integrity=107 skills
reference-governance=36 repos
override-activation-corpus=40 cases
native-skill-metadata=4 targets / 10 cases / 0 findings
dependency-baseline=passed
skills-config-contract=passed / 0 findings
host-capability-contract=5 hosts / 7 evidence
planning-contract=12 tasks / 11 done / 1 open at gate time / 0 findings
host-native-lifecycle-planning=12 tasks / 0 findings
powershell-runtime-policy=5/5 / 0 findings
agent-workflow-advisory=5/5 / 0 findings
doctor-json-contract=passed
total_elapsed_ms=310211
```

The test stage decreased from the last successful `477516ms` timing baseline
to `298327ms` suite elapsed time, approximately 37.5% faster, while retaining
all 1097 tests. Runtime receipts are under ignored
`reports/test-shards/20260808-102831-563ca7c7/` and
`reports/test-timings/current.json`.

After this successful gate, the only truth-file changes are the P6 task status
and closeout documentation. Their affected planning/closeout verifiers are run
again separately; they do not replace or broaden the successful full result.

## Fresh host truth

The bounded fresh CLI probe remained read-only and provider-free:

```text
mode=cli
exit_code=0
status=partial
coverage.prompt_input=true
selection_observable=false
invocation_observable=false
body_injection_observable=false
provider_calls=0
native_mutations=0
writes=0
```

Therefore selection truth remains `host_evaluation_partial`. The P6 manifest
can be 12/12 `done` and the repository phase can be `repo_verified` while
runtime projection, host inventory and live semantic acceptance remain
independent evidence levels.

## 2026-08-08 fresh App Server and invocation follow-up

The first real App Server replay exposed two adapter defects rather than a host
failure. The probe closed stdin before waiting for JSON-RPC responses, and the
adapter assumed the pre-0.146 flat `skills/list.data[]` shape. Focused RED
evidence was the real four-response miss plus `7/8` and `8/9` adapter tests.
The bounded transport now keeps stdin open until response ids `1..4` arrive,
and the adapter flattens the Codex 0.146 `data[].skills[]` envelope while RPC
errors no longer count as coverage. Focused GREEN is `9/9`.

Fresh read-only App Server evidence on `codex-cli 0.146.1`:

```text
native_probe.exit_code=0
native_probe.timed_out=false
coverage.config_read/model_list/model_provider_capabilities_read/skills_list=true
model=gpt-5.6-sol
context_window=272000
skills_inventory.freshness=fresh
skills_inventory.count=124
errors=0
```

The inventory includes `capability-router`, `test-driven-development`,
`verification-before-completion`, and the formerly unreachable
`grill-with-docs`. Four parallel fresh ephemeral selection probes then
observed:

- direct TDD: `capability-router + test-driven-development`, with the target
  `SKILL.md` read in full;
- indirect design interrogation: `grill-with-docs`, with its body read;
- explicit TDD exclusion: TDD absent while a read-only `codebase-design`
  workflow was selected;
- arithmetic: empty selection and zero command executions.

A separate natural-language execution probe read `grill-with-docs` and
produced exactly one architecture question, matching its workflow contract.
However, Codex exec JSONL exposed only `command_execution` and
`agent_message`; it emitted no native `skill_selected`, `skill_injected`, or
`skill_executed` event. This proves fresh inventory plus representative
selection/body-read/behavior, not the universal claim that every skill always
matches correctly. Formal selection truth therefore remains
`host_evaluation_partial`; only fresh inventory can promote `host_loaded`, and
`live_accepted` is not promoted.

The fresh inventory is sufficient to promote only `host_loaded`: snapshot
`hcs-2003353adbc51a2f` captured 124 enabled skills out of 124 with fresh
inventory, zero errors, zero provider calls and zero writes. The snapshot's
overall `partial` status is caused solely by the host not exposing
`metadata_budget`; it does not make the skills inventory stale. `live_accepted`
remains not accepted because native `skill_selected`, `skill_injected` and
`skill_executed` events are still unavailable.

## 2026-08-08 P6-native corpus and representative replay

The P5 corpus still encoded eight router-first cold-load expectations after
all projected skills became host-visible. Focused RED was `5/7`: the corpus
still planned 32 selection plus 8 cold-load calls. The P6 corpus now contains
33 host-native selection cases, zero cold-load probes, direct expectations for
the eight formerly cold skills, and one explicit `$capability-router` fallback
case. Focused GREEN is `8/8`.

Seven fresh ephemeral representative cases covered direct, indirect,
negative, ambiguous, multi-intent, no-skill and explicit-fallback behavior.
The first replay passed 5/7 and exposed two evaluation defects: a legitimate
`draft-tickets` equivalent was excluded by an exact-name expectation, and an
explicit router invocation was incorrectly wrapped as implicit catalog
selection while `allow_implicit_invocation=false`. After adding the semantic
equivalence group and a named explicit-invocation prompt, the two failed cases
passed 2/2. The combined representative result is 7/7, with zero profile
mutations and zero command executions. Reports:

- `reports/host-skill-selection-acceptance/20260808-213856-981/report.json`
- `reports/host-skill-selection-acceptance/20260808-215200-520/report.json`

This is multi-scenario sampling, not exhaustive proof over 124 skills or all
possible tasks. The report truth level intentionally remains
`host_evaluation_partial`.

## 2026-08-08 current-tree full attempt

The first current-tree canonical full attempt completed its test inventory in
`334113ms` but failed `RuleEstate.Tests.ps1`: `1111 passed / 5 failed` out of
1116. File timestamps prove the concurrent RuleEstate slice changed
`src/Application/RuleEstate.ps1` at 22:09:41 and
`tests/Unit/RuleEstate.Tests.ps1` at 22:10:32 while the full gate that started
at approximately 22:04 was still running. After those writes settled, the
exact isolated worker passed `16/16` without another code change. The failed
full remains recorded and is not called passed; the stable tree requires one
fresh canonical retry.

The next retry completed the full test inventory in `349026ms` but was also
not accepted: `1109 passed / 8 failed` out of 1117. Unlike the first attempt,
this exposed stale exact-literal verifiers after the project root had already
been compressed to the v9.73 contract. The old checks required a historical
track name, an obsolete PS7 sentence, and four verbose reference-lifecycle
phrases in the root. Reintroducing those strings would violate the new
root-minimization decision, so the verifiers now bind to stable executable
entrypoints and concise semantic guards. Focused RED is the eight full-gate
failures; focused GREEN is 230/230 across AgentWorkflowAdvisoryPlanning,
PowerShellRuntimePolicy and Core, with all three direct verifiers passing.
Neither failed attempt is represented as a passing full gate.

## Authoritative stable-tree full result

After all concurrent writes and focused repairs settled, the canonical full
gate completed with exit `0`:

```text
tests=1121 passed / 0 failed / 0 skipped
test_suite_elapsed_ms=302433
build=160ms
workspace-lock-parity=passed (8 vendors / 44 imports)
skill-integrity=107
reference-governance=36 repos / 7 default / 3 patches
planning-contract=12 done / 0 open
host-native-lifecycle-planning=12 tasks
all remaining contract/invariant gates=passed
total_elapsed_ms=316483
```

Runtime receipts are under
`reports/test-shards/20260808-144053-ee4053a9/` and
`reports/test-timings/current.json`. This passing full supersedes neither of
the recorded failed attempts nor the separate `host_evaluation_partial` /
`live_accepted=failed` boundary.

## 2026-08-08 routing-gate compression follow-up

The latest full timing receipt attributed `56907ms` to
`CapabilityRoutingVerifier.Tests.ps1`. Root cause was rebuilding and
re-evaluating the same catalog-policy compatibility projection for every
discovery and policy call in the 30-case corpus. A caller-owned cache keyed by
the manifest/policy/config/snapshot file stamps now reuses only that pure
compatibility result; query, exclusion, candidate and safety policy evaluation
still run for every case. The cache is process-local, optional, and performs no
writes. Focused RED rejected the new cache contract before router support;
focused GREEN completed `7/7` in `24588ms` wall time (`21940ms` Pester time),
approximately 56.8% below the latest full-file timing while preserving the
complete corpus and fail-closed negatives. Final contract replay passed
`30/30`; 48 of 57 router calls reused the pure compatibility result, with zero
semantic auto-selections, negative-constraint violations, side-effect
violations, or findings.

The next non-watch hotspot was `PowerShellRuntimePolicy.Tests.ps1` at
`47278ms`. Every mutation fixture copied and reparsed the same 1.4 MiB generated
bundle even though the first acceptance case already validates the real bundle.
Mutation fixtures now retain the BOM, PS7 floor and generated-bundle boundary
in a sub-4 KiB focused surrogate; production verification still parses the
real `skills.ps1`. RED was `8/9` with a `1468518`-byte fixture. GREEN is `9/9`
in `22882ms` wall time (`20450ms` Pester time), approximately 51.6% below the
latest full-file timing without reducing production coverage.

## Rollback

Rollback is limited to the P6 source/config/generation, gate-runner and truth
documentation write-set. Restore the previous projection only through recorded
hash/CAS migration receipts. Do not rewrite historical evidence or touch
unrelated import/reference/watch-runtime changes. Rebuild and rerun the affected
runner contracts plus the single full owner before any rollback closeout.
