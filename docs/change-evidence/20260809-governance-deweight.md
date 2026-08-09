# Governance Deweight Evidence

**Date**: 2026-08-09
**Scope**: engineering constitution, planning truth, receipt-aware quality-gate composition, agent-workflow advisory verification
**Maximum claim**: repository governance reduction verified by focused tests; host loading, invocation, business acceptance, and final full-gate status remain independently authoritative.

## Decision

The audit found real local over-governance, not a reason to delete the repository's protection model. The accepted change removes repeated proof while retaining the boundaries that have caught real failures.

The follow-up locks the same direction into existing `PP-000`/`PP-009` and the existing planning verifier: at an unchanged authority, external-effect, and risk baseline, only representative real-task evidence can trigger lower governance weight; a model name, version upgrade, one success, or model self-assessment is insufficient. A retained or new gate/audit must cover an independent failure mode and keep positive net value. This reuses the existing verifier and test surface; it adds no principle number, schema, verifier, quality-gate stage, registry, or telemetry system.

Removed:

- task ID, checkbox, count, and mutable status mirrors from `tasks/plan.md`/`tasks/todo.md`, plus spec/plan/todo mirrors as enforced audit surfaces in five planning verifiers;
- the completed P6-specific verifier from every default quick/full run;
- agent-workflow checks that mirrored private function names, internal error codes, test descriptions, fixture literals, and dynamic status prose already covered by behavior tests or manifests.

Retained:

- manifest identity, task DAG, required execution fields, write-set safety, evidence existence, model anchors, and truth ladders;
- exact-source fingerprints, immutable receipts, hash-bound current pointer, repository-scoped mutex, generated sync, workspace-lock parity, dependency/config/reference integrity, and rollback contracts;
- public CLI/build wiring, host decision ownership, zero-side-effect output, pure domain/application layers, forbidden runtime/provider/native mutation scans, active Radar decision-path rejection, and JSON parsing;
- `repo_verified`, `host_loaded`, `host_invocation_observed`, and `live_accepted` as distinct claims.

The P6 verifier remains available as an explicit historical/migration diagnostic. It is no longer a default closeout stage because the general planning verifier and behavior suites already cover the active contract.

## Quantified reduction

Measured against the slice baseline `7e765d8f` and the pre-advisory commit `9acb3f41`:

| Surface | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| `tasks/plan.md` | 216 lines | 40 lines | 176 lines |
| `tasks/todo.md` | 140 lines | 22 lines | 118 lines |
| advisory verifier | 283 lines | 219 lines | 64 lines |
| advisory exact literal checks | 79 | 18 | 61 checks |
| default full gate stages | 17 | 16 | 1 completed duplicate stage |

The current project `AGENTS.md` is 8,503 bytes, 83.0% of its 10 KiB project budget, below the 85% warning threshold. It states that manifests own dynamic truth, plan/todo are indexes, and the P6 verifier is explicit historical/migration diagnostics.

## TDD evidence

Planning truth:

- RED: 71 discovered, `66 passed / 5 failed`; the five new failures were exactly the P6, maintenance, typed-core, and PS7 task/status mirror requirements.
- GREEN: `71/71` passed after removing only spec/plan/todo mirrors; manifest DAG, evidence, truth, and runtime-policy assertions remained active.
- Slice build: `build.ps1` completed successfully and regenerated `skills.ps1` without tracked drift.

Default gate composition:

- RED: `33 passed / 1 failed`; the new test observed `host-native-lifecycle-planning` in the default chain.
- GREEN: `34/34` passed after removing that one invocation while retaining `planning-contract` and the explicit P6 verifier file.

Agent-workflow advisory:

- RED: `9 passed / 2 failed`; current plan/todo indexes and internal error-code renames were rejected by the literal mirror.
- GREEN: planning verifier plus real behavior contracts passed `45/45` after reducing the literal list from 79 to 18.
- Behavior coverage continues to exercise delivery admission, completion receipts, dependency closure, risk admission, Radar validation, model proposals, host availability, failure correction, zero side effects, CLI envelopes, and truth ownership.

Fresh combined verification after the rule-text follow-up passed all eight affected test files at `150/150`. The vNext, explicit P6 historical, maintenance, typed-core, PowerShell runtime, and agent-workflow verifiers all returned pass with zero findings; `build.ps1` also completed without tracked generated drift.

Governance-decrease reinforcement reused those same surfaces: `build.ps1` exited 0, `ProductPlanning.Tests.ps1` passed `20/20`, and `verify-vnext-planning.ps1 -Json` returned `pass=true` with zero findings. The existing planning verifier now rejects removal of the stable same-risk governance-decrease clause; no additional test file, verifier, schema, receipt type, or full-gate stage was created.

Receipt-aware closeout then removed another repeated cost without weakening source truth: `-ReuseCurrentReceipt` accepts only an exact-current `full/passed` immutable receipt with the same dirty-worktree policy, falls through to a fresh full run on any mismatch, and remains mutually exclusive with explicit `-ForceFresh`. The test runner keeps its production default timeout at 180 seconds while allowing a one-second synthetic timeout and condition-based mutex handshake, replacing fixed waits and nondeterministic completion-order assertions.

The inactive M1 registry also moved from `collecting (0/10)` to `deferred (0/10)` because it has neither an active owner nor a real-task collection task; both are required to resume it. `HostNativeSkillLifecyclePlanning.Tests.ps1` and `LeanAiDeliveryPlanning.Tests.ps1` remain explicit historical/migration diagnostics but no longer run in every default full suite. Stable focused verification passed `119/119` across product planning, lean-delivery planning, host-native lifecycle planning, typed-core shadow, active PowerShell runtime policy, explicit PowerShell migration history, agent-workflow advisory, receipt integrity, and quality-gate scripts. `build.ps1` and all four explicit planning verifiers passed with zero findings.

An isolated-worktree quick run passed build, repo hygiene, and generated sync, then stopped at workspace-lock parity because ignored `vendor/agent-skills` was not materialized in that temporary worktree. This is setup evidence, not a passed quick receipt and not a source failure; final authority is deferred to the integrated primary workspace, which retains the repository's vendor/lock materialization.

## Closeout truth

Focused results above are point-in-time repository evidence. The final full-gate claim is never copied into this tracked file because doing so after the gate would invalidate its source binding. Resolve closeout only from the immutable receipt referenced by `reports/quality-gates/current.json`, then verify it with `scripts/quality/verify-current-quality-gate.ps1` against the exact candidate source.

No provider call, host mutation, active-profile switch, MCP/plugin change, live probe, or business acceptance was performed by this slice.

## Rollback

Revert the governance-deweight logical-slice commits in reverse chronological order. Do not revert the primary worktree's independent `tests/run.ps1`, `QualityGateScripts.Tests.ps1`, or P6 deep-audit evidence changes unless they are explicitly included in a later reviewed integration commit.
