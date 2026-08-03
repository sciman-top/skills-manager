# Test / gate / governance weight remediation

## Problem and root cause

The Phase 5 closeout task listed `tests/run.ps1` and the `full` quality gate together even though the gate already invokes `tests/run.ps1`. Several fixture-heavy verifiers started a new PowerShell process for every case, unit tests touched persistent User-scope environment variables, audit fixtures repeatedly scanned the live 108-skill projection, and the Doctor JSON contract performed live network probes in a second PowerShell process. Audit commands also wrote every runtime receipt into the curated `docs/change-evidence/` ledger despite repository guidance saying those files must not be committed.

## Remediation

- `scripts/verify-capability-routing.ps1` now invokes the pure read-only router in-process for each golden case.
- `scripts/verify-vnext-planning.ps1` fails closed on a task that separately invokes the full suite and the full quality gate.
- Phase 5 closeout declares the full suite exactly once, through the full quality gate.
- The full gate now executes `build -> test -> contract/invariant` in the declared order and prints per-gate plus total elapsed milliseconds.
- The suite runner prints only failures plus summaries and reports Unit, E2E and total elapsed milliseconds.
- Unit tests use mockable User-scope environment and audit live-state seams; they no longer touch persistent host credentials or scan the current 108-skill projection for run-id/fingerprint fixtures.
- Planning, config, integrity, capability-router, and routing fixture checks reuse composable in-process seams while each relevant CLI retains a real external-process smoke test.
- The Doctor JSON structure contract uses an explicit non-mutating `--offline-contract` mode, rejects combinations with strict/fix modes, and reuses Doctor in the existing gate process. Real `doctor --strict` continues to probe GitHub.
- The routing gate uses metadata-only inventory and no longer computes audit-only hashes for all installed skills.
- Audit runtime receipts now stay beside the ignored report bundle as `runtime-evidence-*.md`; reviewed logical-slice evidence remains in `docs/change-evidence/`. The 115 tracked legacy runtime receipts are preserved as historical truth and are not bulk-deleted.
- The 115 tracked legacy runtime receipts were moved without content changes to `docs/archive/change-evidence/audit-runtime-receipts/`; repository hygiene now rejects new runtime receipts in the active reviewed-evidence ledger.
- Phase 4's entry lifecycle is explicitly `completed`, and the planning verifier rejects a later current phase while a historical phase lifecycle remains open.
- Phase 6 admission is held: no P6 manifest may be created until at least three independent real failures across two domains prove that the P5 seam cannot be repaired directly, P5 fields have real consumers, current governance debt is closed, and the user explicitly authorizes expansion.
- `tests/run.ps1` emits slow-file and slow-case rankings and writes the ignored timing profile `reports/test-timings/current.json`, so future optimization starts from measured hotspots rather than speculative abstraction.
- Regression coverage asserts all of these isolation, composability, CLI, planning, evidence-destination, and gate-order contracts.

## Boundary

This is repo-side test/gate/governance optimization. It does not alter provider, auth, host, plugin, MCP installation, or live acceptance behavior. Existing user-owned dirty files remain outside this slice.

## Verification

Fresh targeted and quick-gate results after the source changes:

- build: exit 0, 912 ms on the first post-change run.
- User-scope isolation red/green: the new static contract failed before the seam repair, then `Core.Tests.ps1` passed 188/188 in 13,339 ms and the isolation contract passed.
- `AuditTargets.Tests.ps1`: 89/89 passed; 44,002 ms -> 18,350 ms after replacing live projection scans with deterministic fixtures (an intermediate run was 22,533 ms).
- fixture verifier groups: ProductPlanning 15,214 -> 5,451 ms; SkillIntegrity 11,613 -> 1,726 ms; ConfigSchema 6,247 -> 1,688 ms; CapabilityRouter 10,220 -> 3,551 ms.
- Doctor CLI 6/6 passed in 10,670 ms; Doctor enhancements plus quality contracts 28/28 passed in 4,640 ms.
- routing golden contract: 11/11 passed, zero findings, zero side-effect violations, zero writes, 5,144 ms.
- planning contract: P5 5/5 done, zero findings, 661 ms.
- quick quality gate: exit 0; summed gate time 7,447 -> 5,510 ms (26.0% lower). Doctor JSON 3,483 -> 1,505 ms (56.8% lower); routing 2,372 -> 2,126 ms after removing unused hashes.

Pre-remediation full baseline: Unit 695/695 in 186,376 ms; E2E 18/18 in 28,140 ms; suite 713/713 in 214,518 ms; summed full gate 222,156 ms.

Fresh post-remediation closeout: exit 0; all Unit and E2E tests passed; E2E 18/18 in 28,142 ms; total test suite 156,129 ms; every subsequent full-gate contract passed; summed full gate 160,474 ms. This is 61,682 ms / 27.8% lower than the pre-remediation full baseline. The separate real-network `doctor --strict --threshold-ms 8000` and Phase 4 entry gate also passed.

Governance-weight follow-through diagnostics on 2026-08-03:

- red phase: six new regression cases failed for the previously open P4 lifecycle, missing completed-task enforcement, duplicate full-suite declarations in the spec, missing historical-phase closure enforcement, unguarded P6 creation while admission is held, and the absent timing profiler.
- targeted green phase: `Phase4EntryGate.Tests.ps1`, `ProductPlanning.Tests.ps1`, and `QualityGateScripts.Tests.ps1` passed 32/32.
- diagnostic profiling run: Unit 702/702, E2E 18/18, total 720/720 in 199,730 ms; timing report schema 1 mapped all 61 Unit files and 2 E2E files with zero unmapped cases.
- measured hotspots: `AuditTargetsHardening.Tests.ps1` 21.3 s, `AuditTargets.Tests.ps1` 20.5 s, `RuleEstateMutation.Tests.ps1` 14.3 s, and E2E `Workflow.Tests.ps1` 29.7 s. The slowest individual cases were rule-audit E2E 12.07 s, target-drift preflight 5.73 s, and routing golden verification 5.60 s.
- P5 planning remained 5/5 done with zero findings; the P4 lifecycle verifier reported `completed` with zero findings; repository hygiene passed.
- this diagnostic suite run established the timing baseline. It is superseded for completion claims by the final ordered closeout below.

Final ordered closeout on 2026-08-03:

- A post-closeout audit exposed a staging-dependent hygiene result: the gate passed while the 115 moves were staged, then failed after the same moves were safely unstaged because `git ls-files` still exposed the HEAD/index paths deleted in the worktree. A new regression test reproduced that failure before the fix.
- The hygiene gate now subtracts only Git-reported unstaged deletions from its tracked-path check; it does not use filesystem existence as a shortcut, preserving sparse-checkout semantics. The regression and related quality-gate tests passed 17/17, and the quick gate passed with an empty index in 11,740 ms.
- After that shared gate seam changed, the full gate was rerun on the final files: `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` exited 0; Unit 707/707, E2E 18/18, total 725/725; test suite 224,381 ms; all build, hygiene, generated-sync, skill-integrity, skill-routing, dependency-baseline, config, host-capability, planning, and Doctor JSON contracts passed; summed gate time 232,697 ms.
- `skills.ps1 doctor --strict --threshold-ms 8000`: exit 0, including live GitHub TCP probe.
- `scripts/verify-vnext-phase4-entry-gate.ps1`: exit 0; `status=completed`, all required criteria met.
- `scripts/verify-capability-routing.ps1`: exit 0; 11 cases, zero findings.
- archive proof: zero tracked runtime receipts remain in active `docs/change-evidence/`, 115 exist under the archive, and Git detects all 115 as exact `R100` renames.

## Rollback

Revert only this remediation's Doctor, audit receipt, routing, verifier, gate-runner, manifest, tests, README, and evidence edits. Do not reset unrelated P4/P5 worktree changes or delete historical evidence.

## Over-design follow-through

The second audit removed governance and code weight that no longer proved distinct risk:

- `AGENTS.md` now has one closeout entry: the full quality gate owns build, complete tests, and repository contracts. Standalone repetitions before or after full are forbidden; the real-network strict Doctor remains an optional post-full live probe.
- The planning verifier no longer enforces README backlinks, AGENTS self-registration, fixed Markdown headings, or one evidence file per completed task. It retains schema, lifecycle, dependency, reference, write-set, P4 closure, and P6 admission invariants; completed work may share one phase-level logical-slice evidence record.
- 113 reviewed historical slices with no exact current reference were moved unchanged to `docs/archive/change-evidence/reviewed-slices/`. The active ledger retains 40 currently referenced or required records.
- Four repository-wide definition-only functions were deleted: `Get-AuditKnownRunIds`, `单技能安装`, `Get-McpServerNameSet`, and `Merge-McpConfigMaps`.
- `Invoke-AuditRecommendationsApply` was reduced from approximately 486 to 402 lines by extracting `Complete-AuditRecommendationsDryRun` and `Resolve-AuditApplySelections`. Further mechanical splitting was deferred because the remaining preflight, failure-report, and transaction paths share state and lack a lower-risk stable seam.

Regression evidence for this follow-through:

- red phase: four governance/dead-code cases failed before remediation; the helper-separation contract then failed until both helpers were implemented and called by the coordinator.
- targeted green: `QualityGateScripts.Tests.ps1` passed 20/20; `ProductPlanning.Tests.ps1` and the earlier quality/planning combined run passed 32/32; `AuditTargets.Tests.ps1` plus `AuditTargetsHardening.Tests.ps1` passed 99/99 with unchanged dry-run, acknowledgment, selection, apply, stale-snapshot, and evidence behavior.
- archive integrity: active evidence 40, reviewed archive 113, runtime-receipt archive 115; all 113 reviewed archive files have the same Git filtered blob hash as their HEAD source, and no archived exact file name remains referenced by the current source/task/product/operations corpus. All 40 concrete `docs/change-evidence/*.md` references resolve; two `YYYYMMDD-*` strings are documentation templates rather than missing records.
- closeout verification uses the repository's ordered `build -> targeted -> quick -> full -> optional live Doctor` sequence. The authoritative pass/fail result is the command output from the final unchanged working tree, avoiding another evidence-only edit after full.
