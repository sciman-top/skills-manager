# Inactive recovery design

This reference preserves the prior write-capable recovery design for review. It is not an instruction to current scheduled heartbeats. `operating_mode=supervisor_monitor_only` in `SKILL.md` and the generated prompts remains authoritative.

## Resume safely

For a future policy that explicitly authorizes `resume_eligible` or `continuation_gap` recovery:

1. Re-read the recent thread and identify the exact interrupted step.
2. Re-read `git status`, affected files, receipts, test output, or other task-local truth needed to determine what already succeeded.
3. Check for external side effects before retrying. Do not repeat commits, pushes, deployments, messages, payments, paid model calls, database mutations, or publication actions without proof that retry is safe.
4. Honor `Retry-After` or an equivalent provider retry time when visible. Otherwise wait for the next scheduled heartbeat; do not run a tight retry loop or blocking sleep.
5. Continue all remaining authorized safe work in the same heartbeat turn. Implement the session as sequential bounded, verifiable slices: after each slice, re-read current truth, identify the next unproved step, and proceed immediately.
6. Do not yield merely because a slice, test, milestone, phase, commit, push, or intermediate summary completed. Do not emit a final answer as a substitute for executing the next authorized safe step. Yield only at one of the explicit stop conditions in the core contract.
7. Before each write-capable slice, re-check shared-checkout arbitration and external-effect truth. A newly active peer or an unsafe retry boundary ends the current recovery session without erasing progress.
8. If another transient failure occurs, preserve current truth and yield. Leave the heartbeat active for the next scheduled tick.
9. Do not count repeated transient provider failures as task completion or a business failure. Do not clear the task goal merely because the gateway is unavailable.
10. Respect host-owned goal and approval semantics. If the host marks the task as requiring attention or the goal cannot be resumed automatically, observe only, report the boundary once when possible, and keep monitoring ACTIVE.

## Coordinate multiple tasks safely

Use one heartbeat per target thread even when several tasks belong to the same project. Separate monitoring concurrency from mutation concurrency:

1. Treat different local checkout paths, including isolated worktrees, as separate workspace write domains. They may recover in parallel unless they share an external side-effect domain.
2. Tasks with positive read-only evidence may recover in parallel in the same checkout. Do not infer read-only status from a title; confirm it from the authorized request and recent actions.
3. Arm every eligible thread in a shared checkout. Do not require the user to choose a permanent sole owner merely because `cwd` matches.
4. Only after the target is positively `resume_eligible` or a `continuation_gap`, use read-only thread listing, reading, or waiting to inspect other visible local Codex threads with the same normalized checkout path. If another relevant turn is active, apply the secondary `peer_busy` gate.
5. If two or more idle shared-checkout threads are otherwise eligible, choose one deterministic winner by the oldest latest non-heartbeat business-turn `updatedAt`, then lexical thread id as the tie-breaker. Every heartbeat must use the same ordering. Non-winners classify as `peer_busy` and keep the heartbeat ACTIVE.
6. Let the deterministic winner continue across sequential bounded slices until it completes or reaches an explicit stop condition; do not rotate ownership merely because one slice ended.
7. Re-evaluate arbitration before every write-capable slice and on every tick. When the winner finishes, pauses, needs input, or moves to an isolated worktree, the next eligible thread becomes the winner without user intervention.
8. This is cooperative serialization, not an atomic filesystem lock. If thread listing, checkout identity, timestamps, or peer status are unavailable or conflicting, classify `unknown`, observe only, and keep monitoring ACTIVE; never claim race-free parallel writes.
9. Repository arbitration never authorizes external side effects. Deployments, service restarts, messages, payments, paid calls, database mutations, and publication remain separately fail-closed and must never replay without proof that retry is safe.
10. Keep `peer_busy` passive and invisible to peers. Never call `send_message_to_thread`, handoff, create/fork, or another peer-waking/mutating thread capability; never inject file lists, ownership claims, completion notices, checkout-release notices, or incident-containment instructions into another task. Do not answer a peer's coordination message. Use only read-only list/read/wait state and a local `DONT_NOTIFY` heartbeat result unless the current user must act.
11. Treat a currently running turn that started before the latest isolation rule or hook activation as `stale_policy_running`: observe only, keep its heartbeat ACTIVE after fleet rearming, and do not contact or recover it until it ends. A fresh-session hook probe, not source-file equality alone, is the closeout authority for the default hook path; specialized-path limitations remain explicit.
12. Heartbeat arbitration does not cover ordinary business turns. Default every new write-capable task to an isolated worktree. Until an atomic host-side checkout lease is separately implemented and live-proved, concurrent ordinary writers in one checkout remain unsafe and the system must not claim race-free mutation.

There is no retry-count terminal condition for transient gateway failures. A task may survive minutes or hours of repeated 429/503 interruptions. The recurring schedule, not an inner retry loop, supplies later attempts.

If the gateway is unavailable before a heartbeat turn can start, the skill cannot inspect or mutate state during that run. A later scheduled occurrence is the next recovery opportunity.
