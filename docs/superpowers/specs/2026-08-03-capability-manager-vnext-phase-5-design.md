# skills-manager vNext Phase 5: Adaptive Capability Fabric

**program_id**: `skills-manager-vnext`
**current_phase**: `P5`
**status**: repo_verified

## 1. Problem

P4 unified reachability and activation planning, but a real architecture query still produced keyword-driven false positives. The missing layer is task understanding and composition, not another profile or a larger metadata budget.

## 2. Goal

Build a local-first decision plane that understands the task, retrieves and adjudicates installed capabilities, composes a minimal DAG, reuses compatible session state, and consumes stable read-only host snapshots. Host-native skills, MCP, apps/connectors, plugins and tools remain the execution plane.

## 3. Phase boundary

In scope: router schema v3, v2-compatible fields, structured task model, hybrid metadata/policy retrieval, minimal capability DAG, session hysteresis, recommendation-only profile preheat, Codex App Server read-only snapshot adapter, deterministic corpus/tests, docs and closeout evidence.

Out of scope: provider calls per route, embeddings/database/daemon, plugin install, OAuth, MCP start/reload, host config writes, profile mutation, thread creation/resume, automatic approvals, ChatGPT web access to local state, or universal natural-language accuracy claims.

## 4. Architecture

`request -> task model -> retrieval -> policy adjudication -> capability DAG -> host-native execution -> verification feedback`

The deterministic script owns retrieval, freshness and safety artifacts. The already-running ChatGPT/Codex model performs semantic adjudication from the full request and may only narrow or abstain; it cannot relax deterministic availability/auth/approval/side-effect gates. Stable App Server methods (`skills/list`, `app/installed`, `app/list`, `mcpServerStatus/list`) supply current read-only facts. Under-development plugin methods and experimental dynamic tools are not required dependencies.

## 5. Schema v3

Add `task_model`, `retrieval`, `capability_graph`, `host_snapshot`, `session_plan`, and `preheat_recommendation`. Preserve `intents`, `selected`, `excluded`, `activation_plan`, `abstained`, and `writes_performed` for v2 consumers.

Snapshots require source, capture time, availability and evidence. Stale snapshots fail closed. Partial source failures remain observable and do not erase valid results from other sources.

## 6. Safety

- Auto-use only already-available read-only/external-read capabilities.
- Unknown, write, destructive, inaccessible, disabled, unauthenticated and not-callable capabilities stay behind activation or approval plans.
- `session_plan` and `preheat_recommendation` are returned data; selector writes no session/profile/config state.
- The App Server adapter sends read-only RPCs and records bounded, redacted source errors.

## 7. Compatibility

P4 fields remain present. `-CapabilitySnapshotPath` remains an alias for `-HostSnapshotPath`. Existing skill/MCP profile configuration and generated projection contracts remain unchanged.

## 8. Acceptance scenarios

1. Capability-architecture assessment is classified correctly and does not select Windows or MCP construction tools.
2. Inspect/implement/verify work yields an ordered minimal DAG.
3. A matching loaded capability is reused without profile mutation.
4. A stale host snapshot is excluded; unavailable/auth-required capabilities are never auto-used.
5. A live App Server probe returns skill/app/MCP facts or a truthful partial result without writes.

## 9. Evidence levels

Unit/golden proves deterministic routing contracts. Fresh process and App Server probes prove current host discovery only. Neither proves ChatGPT web projection, authenticated business actions, or `live_accepted`.

## 10. Task design

- `SMV-P5-001`: establish P5 product/spec/task truth.
- `SMV-P5-002`: implement task understanding, schema v3 and capability DAG.
- `SMV-P5-003`: implement session/preheat planning and read-only host snapshot adapter.
- `SMV-P5-004`: expand resident skill, corpus, compatibility and product docs.
- `SMV-P5-005`: run ordered repository and live read-only acceptance closeout.

## 11. Failure routing

Parser/schema failures block routing. Individual host source errors yield `partial`; initialization or `skills/list` failure blocks the live adapter. Any side-effect auto-allow finding blocks closeout. Full gate failure keeps P5 in progress.

## 12. Ordered verification

1. `build.ps1`
2. affected Pester tests during iteration; do not invoke the full suite separately at closeout
3. `quick_validate.py overrides/capability-router`
4. routing/planning/doctor/dependency/host contracts
5. fresh router replay and App Server read-only snapshot probe
6. full local quality gate once for closeout; it is the single full Unit/E2E invocation

## 13. Rollback

Revert only P5 source/tests/docs and rebuild generated output. Do not revert P4, user imports, audit artifacts, host config or unrelated worktree changes.

## 14. Done definition

All five tasks are done; schema v3 compatibility, golden cases, live read-only snapshot, fresh process, ordered gates and full quality pass; zero unexpected writes and zero side-effect violations; repo/host/live boundaries are explicit.
