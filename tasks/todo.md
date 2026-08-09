# skills-manager Work Queue Index

**program_id**: `skills-manager-vnext`
**current_phase**: `P6`
**task truth**: `tasks/skills-manager-vnext-phase6.tasks.json`

This file is a stable pointer, not a second checklist. Task IDs, completion boxes, counts, runtime status, and acceptance claims live only in the structured truth source for each track.

## Find the next executable item

1. Open `tasks/plan.md` and choose the relevant track.
2. Read that track's manifest fresh.
3. Select the first non-terminal task whose declared dependencies are terminal.
4. Use the manifest's write set, tests, verification, rollback, and stop conditions as the execution contract.
5. If the manifest has no executable task, report its actual boundary; do not create work from historical prose or copied status.

## Closeout boundary

- Iteration uses affected tests and contracts.
- Repository closeout follows `tasks/plan.md`'s frozen verification ceiling: use focused verification when sufficient, or one candidate/full/receipt path when its risk triggers apply.
- `repo_verified`, `host_loaded`, `host_invocation_observed`, and `live_accepted` remain distinct.
