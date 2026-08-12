# skills-manager vNext Phase 5: Adaptive Capability Fabric

**program_id**: `skills-manager-vnext`
**current_phase**: `P5`
**status**: repo_verified (6/6; host activation and business live acceptance remain separate)

## 1. Problem

P4 unified reachability and activation planning, but a real architecture query still produced keyword-driven false positives. The missing layer is task understanding and composition, not another profile or a larger metadata budget.

## 2. Goal

Build a local-first decision plane that understands the task, retrieves and adjudicates installed capabilities, composes a minimal DAG, reuses compatible session state, and consumes stable read-only host snapshots. Host-native skills, MCP, apps/connectors, plugins and tools remain the execution plane.

## 3. Phase boundary

In scope: router schema v3, v2-compatible fields, structured task model, hybrid metadata/policy retrieval, minimal capability DAG, session hysteresis, recommendation-only profile preheat, Codex App Server read-only snapshot adapter, deterministic corpus/tests, docs and closeout evidence.

Out of scope: provider calls per route, embeddings/database/daemon, plugin install, OAuth, MCP start/reload, host config writes, profile mutation, thread creation/resume, automatic approvals, ChatGPT web access to local state, or universal natural-language accuracy claims.

## 4. Architecture

`request -> task model -> retrieval -> policy adjudication -> capability DAG -> host-native execution -> verification feedback`

The deterministic script owns retrieval, freshness and safety artifacts. The already-running ChatGPT/Codex model performs semantic adjudication from the full request and may only narrow or abstain; it cannot relax deterministic availability/auth/approval/side-effect gates. Proven App Server methods (`skills/list`, `app/installed`, `app/list`, `app/read`, `mcpServerStatus/list`) supply current read-only facts. `app/read(includeTools=true)` is display-only and cannot establish authorization or callability; the current host returns 403, so successful `mcpServerStatus/list` annotations and `codex_apps` namespaces provide the stable equivalent tool-policy input. Under-development plugin methods and dynamic tool mutation are not required dependencies. Repository gates separately report tracked source contracts and generated/runtime materialization so a clean worktree never invents external package presence.

## 5. Schema v3

Add `task_model`, `retrieval`, `capability_graph`, `host_snapshot`, `session_plan`, and `preheat_recommendation`. Preserve `intents`, `selected`, `excluded`, `activation_plan`, `abstained`, and `writes_performed` for v2 consumers.

Snapshots require source, capture time, availability and evidence. Current runtime fields override matching static availability/auth/callability/freshness, while static path/policy/role/group/profile reachability remain intact. Opaque apps carry runtime/display names and aliases. Stale snapshots fail closed; partial source failures remain observable and do not erase valid results from other sources.

## 6. Safety

- Auto-use only already-available read-only/external-read capabilities.
- Unknown, write, destructive, inaccessible, disabled, unauthenticated and not-callable capabilities stay behind activation or approval plans.
- `session_plan` and `preheat_recommendation` are returned data; selector writes no session/profile/config state.
- The App Server adapter sends read-only RPCs and records bounded, redacted source errors.
- Tool-level MCP annotations are hints, not authorization. Missing protocol fields use fail-closed defaults (`readOnlyHint=false`, `destructiveHint=true`, `openWorldHint=true`); explicit `readOnlyHint=false` cannot be reclassified as read-only from a name heuristic. Conservative metadata is display-only fallback; unknown, write and destructive tools cannot be auto-used.
- Compound requests select required read/write/destructive tool steps separately and aggregate the highest risk. A high-scoring read tool cannot hide a requested send/update/delete step.
- Host discovery is not task exposure: an MCP outside the current profile stays activation-required even if App Server lists its server.

## 7. Compatibility

P4 fields remain present. `-CapabilitySnapshotPath` remains an alias for `-HostSnapshotPath`. Existing skill/MCP profile configuration and generated projection contracts remain unchanged.

## 8. Acceptance scenarios

1. Capability-architecture assessment is classified correctly and does not select Windows or MCP construction tools.
2. Inspect/implement/verify work yields an ordered minimal DAG.
3. A matching loaded capability is reused without profile mutation.
4. A stale host snapshot is excluded; unavailable/auth-required capabilities are never auto-used.
5. A live App Server probe returns skill/app/MCP facts or a truthful partial result without writes.
6. Every current snapshot descriptor passes an explicit identity probe, with missing and same-name shadowing reported separately.
7. Gmail read is auto-eligible only for a matched read tool; Gmail search+send selects both tools and requires approval.
8. A clean linked worktree validates source/policy closure while reporting generated agent materialization as not present.

## 9. Evidence levels

Unit/golden proves deterministic routing contracts. Fresh process and App Server probes prove current host discovery only. Neither proves ChatGPT web projection, authenticated business actions, or `live_accepted`.

## 10. Task design

- `SMV-P5-001`: establish P5 product/spec/task truth.
- `SMV-P5-002`: implement task understanding, schema v3 and capability DAG.
- `SMV-P5-003`: implement session/preheat planning and read-only host snapshot adapter.
- `SMV-P5-004`: expand resident skill, corpus, compatibility and product docs.
- `SMV-P5-005`: run ordered repository and live read-only acceptance closeout.
- `SMV-P5-006`: harden field-level runtime truth merge, opaque App retrieval, tool policy and dynamic current-host coverage.

## 11. Failure routing

Parser/schema failures block routing. Individual host source errors yield `partial`; initialization or `skills/list` failure blocks the live adapter. Any side-effect auto-allow, annotation-policy, dynamic missing-selection, source-dependency or routing-closure finding blocks closeout. Full gate failure keeps P5 in progress.

## 12. Ordered verification

1. `build.ps1`
2. affected Pester tests, then `tests/run.ps1`
3. `quick_validate.py overrides/capability-router`
4. routing/planning/doctor/dependency/host plus source/runtime materialization contracts
5. fresh router replay and App Server read-only snapshot probe
6. full local quality gate once for closeout

## 13. Rollback

Revert only P5 source/tests/docs and rebuild generated output. Do not revert P4, user imports, audit artifacts, host config or unrelated worktree changes.

## 14. Done definition

All six tasks are done; schema v3 compatibility, golden cases, live read-only snapshot, dynamic full-inventory/tool/identity audit, read+write compound replay, source/runtime materialization evidence, ordered gates and full quality pass; zero unexpected writes and zero unsafe-tool auto-use; repo/host/live boundaries are explicit.
