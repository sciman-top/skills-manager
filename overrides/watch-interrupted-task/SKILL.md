---
name: watch-interrupted-task
description: Fail-closed Desktop continuity after 429/503 or host continuation gaps. Use for 开启/暂停/恢复/关闭/查看守夜或心跳，含全部任务。
---

# Watch Interrupted Task

Use ChatGPT Desktop's native thread heartbeat as a conditional recovery trigger. Treat the heartbeat as a detector and continuous recovery controller, never as blanket authorization beyond the user's existing task scope.

## Preserve the core contract

- Resume only with positive evidence for either a transient provider/transport failure or a host `continuation_gap` as defined below.
- Default to no action when state, scope, or authorization is unclear.
- Never infer permission to continue from inactivity, remaining TODOs, an unfinished branch, or an incomplete goal alone.
- Never override an explicit pause, pending approval, request for user input, user-defined checkpoint, or completed result.
- Never replay a whole turn. Re-read current thread, worktree, verification, and external-effect truth before choosing the next safe action.
- Once positive evidence makes an unfinished task eligible, continue all remaining authorized safe work in the same heartbeat turn. Use bounded, verified slices internally, but do not yield merely because one slice, test, or phase completed.
- Stop continuous recovery only at completion, a real human or approval gate, `peer_busy`, a non-transient or unknown state, an unproved external-effect boundary, another transient interruption, or a host execution limit.
- Treat `natural_pause` only as a pre-existing user handoff or agreed checkpoint discovered before recovery starts. Once continuous recovery starts, an agent-authored phase summary, milestone, test pass, commit, push, or intermediate final answer must not create a new pause while authorized safe work remains.
- Ignore heartbeat turns when identifying the latest business turn. A heartbeat's own final answer must not hide the state that it was created to inspect.
- Keep one heartbeat per target thread. Update an existing matching heartbeat instead of creating a duplicate.
- Use no end time unless the user explicitly requests one.
- Default to a 10-minute cadence for a single task.
- Keep Desktop open, the host awake, and the local project available; report this local-execution dependency.

## Interpret user commands

- `开启守夜：当前任务` or equivalent: create or update one heartbeat for the current local Codex thread.
- `为所有正在执行的任务开启守夜` or equivalent: discover the currently visible eligible local Codex threads and create or update one staggered heartbeat per eligible thread.
- `暂停守夜`: pause the matching heartbeat without deleting it.
- `恢复守夜`: reactivate the matching paused heartbeat; do not create a duplicate.
- `关闭守夜`: delete the matching heartbeat.
- `查看守夜`: inspect and report matching heartbeat state without changing it.
- Apply an explicit user cadence to the requested targets. Otherwise use the defaults in this skill.

Use a deterministic marker in every automation name or prompt:

```text
watch-interrupted-task:v1 target_thread_id=<thread-id>
```

Keep this `v1` marker stable across compatible Skill revisions so existing heartbeats remain discoverable and updatable.

Do not include secrets, API keys, raw provider responses, or sensitive repository content in automation metadata.

## Use the native Desktop surface

1. Use the app's automation-management capability to create, view, update, pause, reactivate, or delete heartbeats.
2. Use a thread heartbeat attached to the existing local thread. Do not substitute a standalone cron automation or create a new task per run.
3. Resolve existing matching automations before creation. Use the deterministic marker, target thread id, and existing automation metadata to prevent duplicates. A repeated enable request must update or report `already_active`; it must never create a second heartbeat.
4. Use the native status values exactly as exposed by the host. The current Desktop automation tool requires uppercase `ACTIVE` and `PAUSED`; never send lowercase variants.
5. Capture and retain the returned automation id when the host exposes one. Include enough deterministic identity in the heartbeat prompt for later self-pause or self-delete.
6. After every mutation, verify the returned receipt or re-read host-managed metadata. Report the actual automation id, target thread id, cadence, status, and `created`, `updated`, `already_active`, `paused`, `resumed`, `deleted`, or `failed` outcome. Include first/next run time only when the host exposes it.
7. Preserve existing notification settings unless the user asks to change them.
8. Immediately before any update, pause, or resume mutation, re-read the current host-managed automation metadata and preserve its latest name, prompt, cadence, target, and notification fields. An in-flight heartbeat must never overwrite a newer durable prompt with the stale prompt embedded in its own tick.
9. Never edit Desktop databases, session JSONL, global state, or automation TOML directly. Reading host-managed automation metadata to resolve an id is allowed when the native tool requires it; mutate only through the native automation capability.
10. Never restart or stop ChatGPT/Codex as part of heartbeat setup.

If the required native automation or thread-management capability is unavailable, report `platform_na` and stop. Do not build an external scheduler workaround unless the user separately authorizes it.

## Classify every heartbeat tick

Read the target thread's recent status and, when relevant, current repository truth. Assign exactly one state before acting:

| State | Required evidence | Action |
|---|---|---|
| `running` | A turn or relevant operation is currently active | Do nothing |
| `resume_eligible` | Explicit transient gateway/transport failure, unfinished authorized goal, and no active turn or human gate | Start a continuous recovery session and finish all remaining authorized safe work unless a terminal boundary is reached |
| `continuation_gap` | The latest non-heartbeat business turn ended with explicit `contextCompaction` or a host continuity/system termination, has no final answer, the previously authorized goal is still unfinished, and the exact first unproved step is identifiable | Start the same continuous recovery session after the side-effect checks used for `resume_eligible` |
| `peer_busy` | Another write-capable thread in the same checkout is active, or deterministically wins shared-checkout arbitration | Do nothing and keep the heartbeat ACTIVE for a later tick |
| `natural_pause` | Before recovery starts, the latest business turn explicitly handed control back to the user or reached a user-defined checkpoint, and no standing continue-to-completion authorization applies | Pause the heartbeat |
| `needs_input` | Approval, credential, choice, clarification, or other user action is required | Pause the heartbeat and report once |
| `complete` | Completion criteria and required verification are satisfied; no required work remains | Delete the heartbeat |
| `non_transient_failure` | 400/401/403, schema/config error, deterministic test failure, policy denial, or business-logic failure | Pause and report; do not call it gateway recovery |
| `unknown` | Evidence is missing, conflicting, stale, or inaccessible | Pause; never guess |

Treat 408, 429, 502, 503, 504, connection timeout/reset/refusal, DNS failure, and SSE interruption as potentially transient only when the actual failing path is the provider or gateway. Do not classify every 5xx from an application under test as a provider outage.

Do not infer `continuation_gap` from idle state, missing TODOs, a dirty worktree, or no final answer alone. Require the explicit host continuity marker plus an unfinished authorized goal, no human gate, and an identifiable next safe step. Before recovery starts, a normal final answer that explicitly hands control back to the user, a user-input request, an approval boundary, or a user-defined checkpoint remains `natural_pause`, `needs_input`, or `complete`. A phase ending by itself is not a natural pause when standing authorization still requires all remaining work to continue.

## Resume safely

For `resume_eligible` or `continuation_gap`:

1. Re-read the recent thread and identify the exact interrupted step.
2. Re-read `git status`, affected files, receipts, test output, or other task-local truth needed to determine what already succeeded.
3. Check for external side effects before retrying. Do not repeat commits, pushes, deployments, messages, payments, paid model calls, database mutations, or publication actions without proof that retry is safe.
4. Honor `Retry-After` or an equivalent provider retry time when visible. Otherwise wait for the next scheduled heartbeat; do not run a tight retry loop or blocking sleep.
5. Continue all remaining authorized safe work in the same heartbeat turn. Implement the session as sequential bounded, verifiable slices: after each slice, re-read current truth, identify the next unproved step, and proceed immediately.
6. Do not yield merely because a slice, test, milestone, phase, commit, push, or intermediate summary completed. Do not emit a final answer as a substitute for executing the next authorized safe step. Yield only at one of the explicit stop conditions in the core contract.
7. Before each write-capable slice, re-check shared-checkout arbitration and external-effect truth. A newly active peer or an unsafe retry boundary ends the current recovery session without erasing progress.
8. If another transient failure occurs, preserve current truth and yield. Leave the heartbeat active for the next scheduled tick.
9. Do not count repeated transient provider failures as task completion or a business failure. Do not clear the task goal merely because the gateway is unavailable.
10. Respect host-owned goal and approval semantics. If the host marks the task as requiring attention or the goal cannot be resumed automatically, pause and report the boundary.

## Coordinate multiple tasks safely

Use one heartbeat per target thread even when several tasks belong to the same project. Separate monitoring concurrency from mutation concurrency:

1. Treat different local checkout paths, including isolated worktrees, as separate workspace write domains. They may recover in parallel unless they share an external side-effect domain.
2. Tasks with positive read-only evidence may recover in parallel in the same checkout. Do not infer read-only status from a title; confirm it from the authorized request and recent actions.
3. Arm every eligible thread in a shared checkout. Do not require the user to choose a permanent sole owner merely because `cwd` matches.
4. Before resuming a write-capable thread, list and inspect the other visible local Codex threads with the same normalized checkout path. If another relevant turn is active, classify the target as `peer_busy`.
5. If two or more idle shared-checkout threads are otherwise eligible, choose one deterministic winner by the oldest latest non-heartbeat business-turn `updatedAt`, then lexical thread id as the tie-breaker. Every heartbeat must use the same ordering. Non-winners classify as `peer_busy` and keep the heartbeat ACTIVE.
6. Let the deterministic winner continue across sequential bounded slices until it completes or reaches an explicit stop condition; do not rotate ownership merely because one slice ended.
7. Re-evaluate arbitration before every write-capable slice and on every tick. When the winner finishes, pauses, needs input, or moves to an isolated worktree, the next eligible thread becomes the winner without user intervention.
8. This is cooperative serialization, not an atomic filesystem lock. If thread listing, checkout identity, timestamps, or peer status are unavailable or conflicting, classify `unknown` and pause; never claim race-free parallel writes.
9. Repository arbitration never authorizes external side effects. Deployments, service restarts, messages, payments, paid calls, database mutations, and publication remain separately fail-closed and must never replay without proof that retry is safe.

There is no retry-count terminal condition for transient gateway failures. A task may survive minutes or hours of repeated 429/503 interruptions. The recurring schedule, not an inner retry loop, supplies later attempts.

If the gateway is unavailable before a heartbeat turn can start, the skill cannot inspect or mutate state during that run. A later scheduled occurrence is the next recovery opportunity.

## Create a heartbeat for the current task

1. Confirm the current backing kind is a local Codex thread and obtain its thread id.
2. Inspect recent status. It is valid to add protection while the task is currently running; later ticks must classify `running` and no-op.
3. Resolve an existing heartbeat with the deterministic marker.
4. Create or update the thread heartbeat with a 10-minute cadence unless the user specifies another cadence.
5. Put this skill's classification and safe-resume contract into the durable heartbeat prompt. Explicitly invoke `$watch-interrupted-task` in that prompt when supported.
6. Report the target, cadence, current automation state, and whether it was created or updated.

## Create heartbeats for all executing tasks

Treat `all` as all eligible tasks visible through the current app/host tools, not as proof of every task on every machine or cloud surface. Honor the current listing limit; the present Desktop `list_threads` surface returns at most 50 recent tasks per call. Report the returned count, unavailable hosts or sources, and this visibility boundary.

1. List the broadest currently visible thread set supported by the app.
2. Keep local Codex threads on the current host that are currently running, have an active unfinished goal, or most recently stopped because of an evidenced transient provider failure.
3. Read enough recent status per candidate to classify it. Never select by title or preview alone.
4. Exclude completed, archived, projectless idle, ChatGPT chat, cloud, inaccessible remote-host, natural-pause, needs-input, approval-blocked, and non-transient-failure threads unless the user explicitly broadens scope and the host supports them.
5. Group candidates by normalized checkout path and classify their execution domain. Arm every eligible thread; isolated worktrees and evidenced read-only tasks may run in parallel, while write-capable tasks in one checkout use the deterministic `peer_busy` arbitration above.
6. Resolve existing matching heartbeats before creating any new one.
7. Use per-thread heartbeats so each task retains its own context. Stagger their first runs across the cadence window when the native tool exposes a first-run or start-time control. If it does not, create targets sequentially, report `platform_na` for verified first-run staggering, and do not claim that staggering was proven.
8. Choose the default fleet cadence as the smallest multiple of 5 minutes that is at least both 10 and the number of selected tasks. This keeps the average scheduled attempt rate at roughly one per minute or less. Honor an explicit user cadence, but still stagger starts.
9. Apply changes per target. Do not silently claim all-or-nothing behavior. Preserve successful updates and report each partial failure.
10. Return a receipt with `created`, `updated`, `already_active`, `skipped`, and `failed` groups, plus any visibility limitation.

## Lifecycle actions

- On `complete`, delete only the matching target heartbeat through the native automation capability.
- On `peer_busy`, leave the matching heartbeat ACTIVE and take no task action.
- On `natural_pause`, `needs_input`, `non_transient_failure`, or `unknown`, re-read the latest automation metadata, preserve every current field other than status, and pause only the matching heartbeat. Do not reconstruct its prompt from the current tick, delete task history, or clear its goal.
- When the user resumes task work, reactivate the heartbeat only after an explicit `恢复守夜`, `开启守夜`, or equivalent request. Do not treat an ordinary task message as implicit heartbeat reactivation.
- When the user says `关闭所有守夜`, enumerate automations by the deterministic marker and delete only those created under this skill.
- If self-pause or self-delete fails, report the exact automation identity and leave the remaining state truthful.

## Keep setup and reporting safe

- Scheduled tasks may run unattended with non-interactive approval behavior. Pause whenever a new approval or material user decision is required.
- Do not use paid inference requests merely as health probes. A successful heartbeat turn is already evidence that one provider request completed; task-specific live acceptance remains separate.
- Keep gateway health, task resumption, repository verification, external effects, and live acceptance as separate states.
- Do not change provider, auth, model, sandbox, plugin, MCP, or Desktop process state while managing heartbeats.
- Use the minimum access necessary and preserve unrelated automations.
- Report current facts and limitations; never claim coverage for threads the app did not expose.

## Use this durable heartbeat instruction

When creating or updating a heartbeat, preserve these semantics in its prompt:

```text
Use $watch-interrupted-task for this target thread. Ignore heartbeat turns and classify the latest non-heartbeat business state before acting. Treat natural_pause only as a pre-existing explicit user handoff or user-defined checkpoint; standing instructions to continue autonomously through completion override an agent-authored phase boundary. When positive evidence shows either (a) a transient provider/transport interruption, or (b) a continuation_gap with explicit contextCompaction or host continuity termination, no final answer, an unfinished previously authorized goal, no human gate, and an identifiable first unproved step, start a continuous recovery session. Re-read thread, repository, verification, and external-effect truth, then continue all remaining authorized safe work as sequential bounded, verified slices in the same heartbeat turn. After each slice, immediately identify and execute the next unproved safe step; do not yield or emit a final answer merely because one slice, test, milestone, phase, commit, push, or intermediate summary completed. Once recovery starts, stop only at completion, a real human or approval gate, peer_busy, a non-transient or unknown state, an unproved external-effect boundary, another transient interruption, or a host execution limit. For shared checkouts, arm every eligible task but serialize write-capable recovery: before every write slice, if a peer is active or wins the deterministic oldest-updatedAt-then-thread-id ordering, classify peer_busy, do nothing, and keep this heartbeat ACTIVE. Let the winner continue until a stop condition instead of rotating after each slice. Isolated worktrees and evidenced read-only tasks may recover in parallel. If work is already running, do nothing. If complete and verified, delete this heartbeat. Before self-pausing or resuming, re-read host automation metadata and preserve any newer prompt; never overwrite it with this tick's embedded prompt. Never replay already successful or unsafe external side effects. On another eligible interruption, preserve truth and leave the heartbeat active for the next tick.
```
