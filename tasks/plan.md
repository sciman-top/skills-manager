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
| Lean delivery pilot (deferred) | `tasks/skills-manager-vnext-lean-delivery-pilot.json` |
| Agent workflow advisory | `tasks/skills-manager-vnext-agent-workflow-advisory.tasks.json` |
| Typed-core shadow pilot | `tasks/skills-manager-vnext-typed-core-pilot.tasks.json` |
| PowerShell 7 migration | `tasks/skills-manager-vnext-powershell7-migration.tasks.json` |
| Native-first routing correction | `tasks/skills-manager-vnext-capability-routing-correction.tasks.json` |
| Capability discovery redesign | `tasks/skills-manager-vnext-capability-discovery-redesign.tasks.json` |
| Profile reconciliation | `tasks/skills-manager-vnext-profile-reconciliation.tasks.json` |
| Profile optimization canary | `tasks/skills-manager-vnext-profile-optimization.tasks.json` |

## Execution order

1. Read the target manifest fresh and select its first task whose status is not terminal and whose dependencies are satisfied.
2. Freeze the declared write set and stop conditions before editing.
3. Run affected build, tests, and contracts during iteration.
4. Create a candidate commit, then enter the receipt-aware full quality gate once; it reuses only an exact-current passed receipt and otherwise runs fresh.
5. Treat the immutable current receipt as repository evidence only; host and live acceptance remain separate.

## Failure routing

- Unknown dependency, write-set overlap, source drift, failed gate, or missing evidence blocks closeout.
- Roll back only the current manifest slice. Do not overwrite unrelated imports, reports, host state, or concurrent worktree changes.
