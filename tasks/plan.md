# skills-manager Execution Index

**program_id**: `skills-manager-vnext`
**current_phase**: `P6`
**task_truth**: `tasks/skills-manager-vnext-phase6.tasks.json`

## Truth policy

- Structured manifests own task IDs, dependencies, write sets, mutable status, counts, evidence, stop conditions, and next milestones.
- This file is navigation only. It intentionally does not copy task rows, checkboxes, counts, runtime status, or acceptance claims.
- Resolve repository verification, host loading, invocation, and live acceptance from their separate evidence fields; never infer a higher truth level from a lower one.

## Active truth sources

| Scope | Authoritative source |
| --- | --- |
| Current P6 lifecycle | `tasks/skills-manager-vnext-phase6.tasks.json` |
| Lean delivery maintenance | `tasks/skills-manager-vnext-maintenance-design.tasks.json` |
| Lean delivery pilot (collecting) | `tasks/skills-manager-vnext-lean-delivery-pilot.json` |
| PowerShell 7 migration | `tasks/skills-manager-vnext-powershell7-migration.tasks.json` |
| Native-first routing correction | `tasks/skills-manager-vnext-capability-routing-correction.tasks.json` |
| Capability discovery redesign | `tasks/skills-manager-vnext-capability-discovery-redesign.tasks.json` |

## Historical records

| Scope | Record |
| --- | --- |
| Retired Agent workflow advisory | `tasks/skills-manager-vnext-agent-workflow-advisory.tasks.json` |
| Retired typed-core shadow pilot | `tasks/skills-manager-vnext-typed-core-pilot.tasks.json` |
| Retired profile reconciliation advisor | `tasks/skills-manager-vnext-profile-reconciliation.tasks.json` |
| Retired profile optimization canary | `tasks/skills-manager-vnext-profile-optimization.tasks.json` |

## Execution order

1. Read the target manifest fresh and select its first task whose status is not terminal and whose dependencies are satisfied; a simple direct task may use an equivalent progress update without creating a manifest or evidence file.
2. Freeze `user_outcome`, `admission_scope`, `exact_write_set`, `reuse_decision`, `verification ceiling`, and `stop_condition`; translate applicable PP-001 through PP-013 into the slice's default and prohibited actions.
3. Run the shortest real main chain and only the affected build, tests, or contracts required by the frozen verification ceiling.
4. `scope expansion requires re-admission`: expanding direction, authority, write set, verification ceiling, external effects, files, abstractions, governance, worktrees, or agents requires evidence of an independent current-task failure; otherwise skip, defer, or route it separately.
5. Close out through one proportional path: focused verification for non-runtime rules/docs/tests/verifiers/scripts/config, or the receipt-aware full gate for runtime, security, data/migration, public-contract, dependency/package, release, or discovered cross-surface risk.
6. `minimal user closure -> stop`: once the frozen stop condition and minimum verification are met, stop; do not continue merely because adjacent work exists.
7. A full-gate receipt, when required, is repository evidence only; host and live acceptance remain separate.

## Failure routing

- Unknown dependency, write-set overlap, source drift, failed gate, or missing evidence blocks closeout.
- `out-of-scope remote divergence` is not merged into the current task; retain the slice/branch and use an authorized task branch/PR or report `integration_blocker`.
- Roll back only the current manifest slice. Do not overwrite unrelated imports, reports, host state, or concurrent worktree changes.
