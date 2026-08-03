---
name: watch-interrupted-task
description: Fail-closed Desktop heartbeats after 429/503. Use for 开启/暂停/恢复/关闭/查看守夜或心跳，含全部任务。
---

# Watch Interrupted Task

Use ChatGPT Desktop's native thread heartbeat as a conditional recovery trigger. Treat the heartbeat as a detector and recovery controller, never as blanket authorization to keep a task running.

## Preserve the core contract

- Resume only with positive evidence that the most recent interruption was a transient provider or transport failure.
- Default to no action when state, scope, or authorization is unclear.
- Never infer permission to continue from inactivity, remaining TODOs, an unfinished branch, or an incomplete goal alone.
- Never override an explicit pause, pending approval, request for user input, natural phase boundary, or completed result.
- Never replay a whole turn. Re-read current thread, worktree, verification, and external-effect truth before choosing the next safe action.
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
8. Never edit Desktop databases, session JSONL, global state, or automation TOML directly. Reading host-managed automation metadata to resolve an id is allowed when the native tool requires it; mutate only through the native automation capability.
9. Never restart or stop ChatGPT/Codex as part of heartbeat setup.

If the required native automation or thread-management capability is unavailable, report `platform_na` and stop. Do not build an external scheduler workaround unless the user separately authorizes it.

## Classify every heartbeat tick

Read the target thread's recent status and, when relevant, current repository truth. Assign exactly one state before acting:

| State | Required evidence | Action |
|---|---|---|
| `running` | A turn or relevant operation is currently active | Do nothing |
| `resume_eligible` | Explicit transient gateway/transport failure, unfinished authorized goal, and no active turn or human gate | Resume one bounded safe slice |
| `natural_pause` | The task intentionally yielded control, ended a phase, or asked the user what to do next without a transient failure | Pause the heartbeat |
| `needs_input` | Approval, credential, choice, clarification, or other user action is required | Pause the heartbeat and report once |
| `complete` | Completion criteria and required verification are satisfied; no required work remains | Delete the heartbeat |
| `non_transient_failure` | 400/401/403, schema/config error, deterministic test failure, policy denial, or business-logic failure | Pause and report; do not call it gateway recovery |
| `unknown` | Evidence is missing, conflicting, stale, or inaccessible | Pause; never guess |

Treat 408, 429, 502, 503, 504, connection timeout/reset/refusal, DNS failure, and SSE interruption as potentially transient only when the actual failing path is the provider or gateway. Do not classify every 5xx from an application under test as a provider outage.

## Resume safely

For `resume_eligible`:

1. Re-read the recent thread and identify the exact interrupted step.
2. Re-read `git status`, affected files, receipts, test output, or other task-local truth needed to determine what already succeeded.
3. Check for external side effects before retrying. Do not repeat commits, pushes, deployments, messages, payments, paid model calls, database mutations, or publication actions without proof that retry is safe.
4. Honor `Retry-After` or an equivalent provider retry time when visible. Otherwise wait for the next scheduled heartbeat; do not run a tight retry loop or blocking sleep.
5. Continue only one bounded, verifiable slice from the first unproved step.
6. If another transient failure occurs, preserve current truth and yield. Leave the heartbeat active for the next scheduled tick.
7. Do not count repeated transient provider failures as task completion or a business failure. Do not clear the task goal merely because the gateway is unavailable.
8. Respect host-owned goal and approval semantics. If the host marks the task as requiring attention or the goal cannot be resumed automatically, pause and report the boundary.

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
5. Detect two threads with write access to the same working directory. Do not arm both for automatic mutation; pause and report the conflict unless they use isolated worktrees or the user provides a safe ownership decision.
6. Resolve existing matching heartbeats before creating any new one.
7. Use per-thread heartbeats so each task retains its own context. Stagger their first runs across the cadence window when the native tool exposes a first-run or start-time control. If it does not, create targets sequentially, report `platform_na` for verified first-run staggering, and do not claim that staggering was proven.
8. Choose the default fleet cadence as the smallest multiple of 5 minutes that is at least both 10 and the number of selected tasks. This keeps the average scheduled attempt rate at roughly one per minute or less. Honor an explicit user cadence, but still stagger starts.
9. Apply changes per target. Do not silently claim all-or-nothing behavior. Preserve successful updates and report each partial failure.
10. Return a receipt with `created`, `updated`, `already_active`, `skipped`, and `failed` groups, plus any visibility limitation.

## Lifecycle actions

- On `complete`, delete only the matching target heartbeat through the native automation capability.
- On `natural_pause`, `needs_input`, `non_transient_failure`, or `unknown`, pause only the matching heartbeat. Do not delete task history or clear its goal.
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
Use $watch-interrupted-task for this target thread. Classify current state before acting. Resume only when positive evidence shows that the latest interruption was a transient provider or transport failure and the original authorized goal remains unfinished. If work is running, do nothing. If the task naturally paused, needs user input or approval, has a non-transient failure, or state is unclear, pause this heartbeat and do not continue. If the task is complete and verified, delete this heartbeat. Before any retry, re-read current thread, repository, verification, and external-effect truth; never replay already successful or unsafe side effects. On another transient interruption, preserve truth, yield, and leave the heartbeat active for the next scheduled tick.
```
