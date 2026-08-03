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

## Rollback

Revert only this remediation's Doctor, audit receipt, routing, verifier, gate-runner, manifest, tests, README, and evidence edits. Do not reset unrelated P4/P5 worktree changes or delete historical evidence.
