# Conditional recovery design

Read this reference for Goal supervision, retries, shared-checkout arbitration, or fleet reconciliation. `SKILL.md` remains the authority.

## Goal supervision

1. Read the direct user request, current Goal, plan/checklist, repository contract, worktree, and live external truth.
2. Derive one Goal Contract: Outcome, Scope, Acceptance, Checkpoints, Evidence, Stop conditions, and Recovery policy.
3. Preserve the Goal objective. A strategy may change after root-cause evidence; scope or acceptance may change only through a direct user instruction.
4. Compare every proposed slice with the Goal Contract. Classify `strategy_drift` when a tactic no longer advances acceptance or violates scope.
5. Treat checkpoints as proved state, not prose milestones. Each checkpoint records the last verified outcome, pending first-unproved step, affected write domain, and receipt key.
6. Treat completion as a verification decision. Re-run the required acceptance evidence before marking the Goal complete.
7. Mark blocked only when the same blocker appears in three consecutive Goal turns, is genuinely impassable without user/external change, and no meaningful in-scope progress remains.
8. Separate Goal completion from heartbeat cleanup. `goal_satisfied + GoalStatus=active` requests `mark_complete` and keeps the heartbeat active. Cleanup is eligible only on a later tick with `GoalStatus=none|complete`, no active turn, fresh positive evidence, checkpoint/receipt identity, and `external_effect_state=none|safe`.

## Recovery evidence and idempotency

Each recovery decision needs:

- `state` and evidence source;
- UTC evidence timestamp;
- stable `checkpoint_id`;
- deterministic `receipt_key` derived from target, Goal/objective version, interrupted business turn, state, and first unproved step;
- `external_effect_state=none|safe|unknown|unsafe`;
- `next_retry_at` when `Retry-After` or backoff applies.

Search prior heartbeat XML messages for the receipt key. Reuse it for the same boundary. A repeated receipt suppresses duplicate notification and does not repeat an already-proved side effect.

For 408/429/502/503/504, transport reset/refusal, DNS, or SSE interruption, honor `Retry-After` when present. Otherwise let the recurring schedule provide bounded retry opportunities. Do not spin or block-sleep. Repeated transient provider failures do not make a Goal blocked.

## Resume safely

1. Re-read the target and locate the exact interrupted step.
2. Re-read Git, files, test output, tool receipts, and external state to determine what already succeeded.
3. If an external effect may already have happened, require an authoritative receipt or idempotency read. `unknown` stops recovery.
4. Resume at the first unproved safe step. Never replay the whole turn.
5. After each bounded slice, verify its outcome, emit/update the checkpoint receipt, and immediately choose the next safe step.
6. Continue until acceptance, human/approval gate, `peer_busy`, unsafe/unknown truth, another transient interruption, or host execution limit.
7. A test pass, commit, phase boundary, push, or summary is not an automatic pause while authorized work remains.

## Adjust strategy

Use systematic root-cause evidence before changing tactics. The target heartbeat may:

- repair an in-scope deterministic defect;
- switch to another already-authorized implementation path;
- reduce a slice to isolate failure;
- update the working plan/checkpoint sequence;
- rerun the minimum sufficient verification, then the required closeout gate.

It may not silently change product intent, acceptance meaning, compatibility promises, allowed write set, credentials, provider/auth/model/sandbox, or irreversible external effects.

## Shared checkout

Different isolated worktrees are separate write domains. In the same checkout:

1. Establish positive recovery eligibility first.
2. Use read-only task listing/reading/waiting to identify active writers.
3. If a relevant writer is active, return `peer_busy`.
4. If multiple idle tasks are eligible, select the oldest latest non-heartbeat business update, then lexical thread id.
5. Re-check before every write-capable slice.
6. This is cooperative serialization, not an atomic lease. Missing checkout identity or status is `unknown`.

Never communicate with a peer task. Repository arbitration never authorizes external side effects.

## Fleet supervisor

The fleet supervisor manages only canonical target heartbeat metadata:

- discover visible eligible local tasks;
- create a missing revision-3 target heartbeat;
- migrate an older matching watch prompt to the trusted target body digest;
- preserve existing cadence/notification settings;
- delete only after verified acceptance, terminal Goal state when applicable, no active turn, and a matching cleanup receipt.

The fleet heartbeat cannot establish direct user authority to delete an automation, so fleet-side delete is fail-closed. A direct user lifecycle command must perform deletion after the terminal receipt is visible. Lifecycle keywords inside negation, questions, quoted text, documentation, or code are not authorization; current-task commands cannot target a different session unless the user explicitly names its target id.

## Fleet shutdown after every monitored task stops

This power action is opt-in and separate from ordinary fleet watch. The direct user must create or update the supervisor with the canonical shutdown-armed fleet prompt. A scheduled tick, target task, stale lifecycle command, or self-consistent caller-authored prompt cannot arm it.

The target task owns stop truth. Goal presence does not change fleet aggregation: a Goal task follows its Goal Contract and emits a stopped receipt only after its host AI stops; a non-Goal task emits one after its own stop decision. Do not encode a finite allowlist of stop causes. Any stable `stop_reason` qualifies when fresh evidence says `task_stopped=true`, `recovery_pending=false`, there is no active business turn or `next_retry_at`, external-effect state is safe/none, and checkpoint plus receipt are present. Known recovery and uncertain boundaries override a contradictory stopped flag and never qualify: `running`, `resume_eligible`, `continuation_gap`, `recoverable_task_failure`, `strategy_drift`, `verification_failed`, `peer_busy`, `stale_policy_running`, `unknown`, `soft_guard_only`, unverified `goal_satisfied`, and transient provider/transport failures including 408/429/502/503/504.

Use `Get-WatchFleetShutdownDisposition.ps1` to canonicalize the non-empty monitored set and compute `snapshot_key` plus `shutdown_receipt_key`. The exact same snapshot must be observed on two consecutive ticks. Immediately re-list and re-read the monitored set before execution; any drift cancels the tick. Schedule only `shutdown.exe /s /t 120 /c "watch-interrupted-task: all monitored tasks stopped"`, never `/f`, and surface `shutdown /a` in the notification. Exit code 0 is the scheduling receipt. Reuse that receipt forever for the same snapshot; failure or unknown effect stops without blind replay.

## Hook and code-mode boundary

The cross-thread guard is defense in depth. Native typed tool calls are evaluated against their structured contract. Free-form code-mode cannot be safely reduced to a complete sequence of trusted mutations, so any script containing cross-thread send, handoff, automation mutation, or aliased/dynamic tool dispatch is denied as a whole; placing a read-only call first does not make a later mutation safe. Installation and static simulation establish only `static_configuration_ready`; a changed non-managed hook remains `installed_untrusted/soft_guard_only` until the user reviews and trusts its exact hash with `/hooks` in a fresh session.

Before mutation, compare fresh host identity, target id, policy revision, trusted body digest, and existing status. Skip conflicts. The supervisor never performs business work in another task and never mutates its own dual-role automation from a scheduled tick.
