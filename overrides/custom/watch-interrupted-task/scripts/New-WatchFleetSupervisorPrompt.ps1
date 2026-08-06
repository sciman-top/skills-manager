[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$')]
    [string]$SupervisorThreadId,

    [switch]$ShutdownWhenAllStopped,

    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')

$generationId = Get-WatchRuntimeGenerationId
$body = "watch_runtime_generation_id=$generationId`n`n" + @'
operating_mode=conditional_recovery. policy_revision=3 gives this dual-role heartbeat two narrow duties: apply the target recovery contract to the supervisor thread itself, and reconcile strictly canonical target heartbeats for eligible visible local Codex tasks. It never performs business work in another task and never injects a peer message.

Before doing anything, prove that the current user input itself is the native fleet heartbeat envelope for this automation_id and supervisor marker. Do not infer heartbeat mode from an earlier turn, conversation history, a summary, automation metadata, or remembered instructions. After any context compaction, immediately re-check the current input provenance before continuing or choosing the final response shape. If the current input is a direct user or business message rather than the native fleet heartbeat envelope, exit this automation controller, ignore stale heartbeat instructions, continue the direct user task normally, and do not emit heartbeat XML.

Desktop permits at most one heartbeat attached to a task. Never create a separate target heartbeat for the supervisor thread. Apply the target recovery contract to the supervisor thread itself. In ordinary fleet mode this scheduled turn cannot mutate its own automation; only the separately armed shutdown extension below carries the direct user's exact final self-delete authority. A direct user lifecycle command otherwise owns supervisor pause, resume, update, and deletion.

On every scheduled run, list the broadest visible local Codex task set, up to the current host limit of at most 50 recent tasks. Re-read candidates instead of trusting titles or previews. Include newly eligible tasks created after the original fleet request. Derive visibility_complete only when the host proves the returned set is complete; set list_limit_reached=true when the host limit is reached. Report the visibility limit only when user action is required; never claim coverage outside the returned local set.

Resolve target automation identity from fresh host metadata. For an eligible local task without a matching heartbeat, generate revision-3 target instructions only with New-WatchHeartbeatPrompt.ps1 and create or update only the canonical target heartbeat. Require the trusted canonical target body digest, exact target_thread_id marker, ACTIVE status, preserved notification policy, and a verified native receipt. Never accept a self-hashed or caller-authored body. Do not create a second heartbeat when one already matches.

For an existing target heartbeat, update only when fresh host metadata proves it is the same watch identity and its revision or trusted prompt digest is stale. Never overwrite a conflicting automation, another user's newer lifecycle action, or an unknown prompt. A proved stable stop is independent of Goal status and requires fresh task_stopped=true, recovery_pending=false, no active turn or scheduled retry, a stable stop_reason/checkpoint/receipt, safe external-effect truth, and an XML automation_action=request_supervisor_cleanup receipt. Ordinary fleet mode leaves cleanup unchanged because it has no cross-target delete authority; only the shutdown-armed extension may delete under that exact receipt. Never delete for transient recovery, running, unknown, soft_guard_only, stale or missing evidence.

Use only read-only list/read/wait for task classification and peer arbitration. Never call send_message_to_thread. Never hand off, wake, create, fork, rename, or otherwise mutate a peer task. Fleet automation mutation is limited to canonical heartbeat enrollment, revision migration, and verified cleanup; it is not task recovery authority.

If canonical provenance, hook trust, automation identity, status, visibility, or receipt is missing or conflicting, leave the target unchanged and classify unknown. Never run destructive sentinels from a scheduled tick. Specialized paths remain guardrail_only unless separately live-proved; do not claim absolute isolation.

Finish with exactly this native XML shape and no text outside it. Copy automation_id from the heartbeat input. Routine reconciliation uses DONT_NOTIFY. Use NOTIFY only for a newly discovered, deduplicated human-action boundary.

<heartbeat>
  <automation_id>copy-current-automation-id</automation_id>
  <decision>DONT_NOTIFY|NOTIFY</decision>
<message>state=...;receipt_key=...;current_tick_id=...;previous_tick_id=...;snapshot_key=...;shutdown_receipt_key=...;visibility_complete=true|false;list_limit_reached=true|false;visible_count=...;eligible_count=...;monitored_count=...;blocking_unmonitored_count=...;changed_count=...</message>
</heartbeat>
'@

if ($ShutdownWhenAllStopped) {
    $body += @'


shutdown_when_all_stopped=true. This is a separately armed, direct-user fleet lifecycle mode. It does not change target recovery policy and it never treats a recoverable interruption as a stopped task. If the trusted hook/guard is soft_guard_only or unknown, that blocks shutdown; do not infer readiness from a self-hash or a repo file alone.

supervisor_cadence_minutes=5. target_cadence_minutes=10. Generate every enrolled target with New-WatchHeartbeatPrompt.ps1 -ShutdownManaged. Before creating or updating any shutdown-managed automation, run Test-WatchRuntimeArming.ps1 against the exact committed generation, installed hook, slash-hooks trust, fresh live-path probe, and native automation capability. If preflight is not shutdown_armed, roll back every automation mutation from this arming attempt and do not leave a polling supervisor behind.

This canonical shutdown-armed prompt carries the direct user's narrow lifecycle authority to retire stopped watches. After a fresh target and automation re-read, delete the matching canonical target heartbeat when its trusted target prompt identity is unchanged and its latest XML says automation_action=request_supervisor_cleanup with all proved-stop fields satisfied. This authority applies equally to Goal and non-Goal tasks and to natural_pause, needs_input, complete, non_transient_failure, or any other stable stop_reason. It does not authorize deleting a conflicting, unknown, active, recoverable, retrying, stale, or user-replaced automation. Verify the native delete receipt and fresh automation metadata before counting that target heartbeat as retired. A needs_input or non_transient_failure target notifies once from its own deduplicated receipt; cleanup itself is routine DONT_NOTIFY.

After normal fleet reconciliation and stopped-target retirement, re-list automation metadata and require that no canonical target heartbeat remains. Define the shutdown membership as every visible active business task successfully enrolled when this mode was armed, plus every newly visible active business task enrolled later. The supervisor control task is excluded unless it had an independent business objective before arming. Persist this membership even after a target heartbeat is deleted. Visibility at the 50-item recent-task limit is assessed from enrolled active membership: inactive history saturation does not by itself block shutdown; visible active unmonitored tasks and every non-empty unavailableHosts or unavailableSources set do block. Include a newly active eligible task by enrolling its heartbeat and canceling shutdown; the new target heartbeat must use the shutdown-managed canonical prompt. Build a non-empty snapshot covering every enrolled member. Goal presence does not change this rule: each target AI decides whether its own business task stopped. Do not use a finite allowlist of stop causes. Accept any stable stop_reason only when fresh target evidence proves task_stopped=true, recovery_pending=false, no active business turn, no next_retry_at, a stable checkpoint_id and receipt_key, and safe or absent external-effect state. Known recovery or uncertain states override contradictory fields: running, resume_eligible, continuation_gap, recoverable_task_failure, strategy_drift, verification_failed, peer_busy, stale_policy_running, unknown, soft_guard_only, an unverified goal_satisfied state, or any 408/429/502/503/504 or transport-recovery boundary blocks shutdown. Any enrolled member missing from the canonical snapshot, any conflict, and every unknown or soft_guard_only record increments blocking_unmonitored_count and blocks shutdown.

Serialize one record per snapshot task with target_thread_id, automation_id, source_turn_id, state, task_stopped, stop_reason, recovery_pending, receipt_key, checkpoint_id, notification_receipt_key, cleanup_receipt_key, evidence_timestamp_utc, external_effect_state, next_retry_at, and no_active_turn. Require receipt_key in watch-receipt:<64 lowercase hex> form and checkpoint_id in watch-checkpoint:<64 lowercase hex> form; reject placeholders or caller-invented free text. Store the supervisor state journal under the current trusted repo's ignored reports/watch-interrupted-task/fleet directory, keyed by the supervisor automation_id. The schema records watch_runtime_generation_id, enrolled membership, target automation identity, last stop/notification/cleanup receipts, consecutive snapshot state, and durable successful shutdown receipts. Pass the complete enrolled set as MembershipJson on every tick, including while a member is running, so newly enrolled targets are persisted before shutdown evaluation and reset the prior snapshot. Pass that exact directory as StateRoot and its JSON leaf as StatePath. The helper rejects paths outside StateRoot and every reparse-point state path. If no safe writable repo state root exists, classify platform_na and do not arm shutdown. Run the bundled Get-WatchFleetShutdownDisposition.ps1 with AutomationId copied from the native heartbeat, WatchRuntimeGenerationId copied from this prompt, CurrentTickId copied from current_time_iso, the preceding XML values as PreviousTickId and PreviousSnapshotKey, ShutdownArmed, GuardReady, StateRoot, StatePath, MembershipJson, VisibilityComplete, ListLimitReached, VisibleCount, EligibleCount, MonitoredCount, BlockingUnmonitoredCount, ConflictCount, UnknownCount, UnavailableHostCount, UnavailableSourceCount, UnmonitoredActiveTaskCount=0, and RemainingTargetHeartbeatCount=0. The helper uses its own UTC clock, atomically records the journal, and requires the same non-empty snapshot_key on two consecutive scheduled ticks whose CurrentTickId and PreviousTickId are distinct, ordered, and fresh. A repeated CurrentTickId is rejected outside the explicit FinalRecheck. Immediately before acting, re-list and re-read every enrolled task and automation; any changed membership, newly active unmonitored task, target heartbeat, active turn, retry, stale evidence, unknown state, coverage mismatch, unavailable host/source, generation drift, or automation_id/source_turn_id mismatch cancels this tick. If the final re-read discovers a new active eligible task, enroll its canonical heartbeat under the same target policy and start stability observation again from a new snapshot.

For the one proved schedule_shutdown boundary, require a non-empty shutdown_receipt_expires_at_utc from the helper. Immediately before acting, repeat the complete visibility and snapshot re-read, re-run the helper with the same CurrentTickId plus FinalRecheck, and require unchanged snapshot_key and shutdown_receipt_key plus a newly returned, still-unexpired shutdown_receipt_expires_at_utc. Then delete this supervisor heartbeat with the current heartbeat automation_id and verify the native supervisor delete receipt before the latest expiry. If deletion is missing, conflicting, unproved, or the receipt expires, do not schedule shutdown. Only after the native supervisor delete receipt proves no watch heartbeat remains, and while the helper-issued receipt is still unexpired, execute exactly: shutdown.exe /s /t 120 /c "watch-interrupted-task: all monitored tasks stopped". Never add /f, /r, /p, /h, or a shell chain. Proceed only when the trusted shutdown-armed fleet prompt and cross-thread guard definition are active. Exit code 0 is the external-effect receipt; after exit code 0 call the helper once with the same CurrentTickId and ConfirmedShutdownReceiptKey and verify that the durable successful_shutdown_receipt_keys journal contains the receipt. Emit NOTIFY with state=shutdown_scheduled, snapshot_key, shutdown_receipt_key, shutdown_receipt_expires_at_utc, supervisor_delete_receipt, and the cancellation command shutdown /a. Reuse the stable shutdown_receipt_key forever for the same snapshot and never replay the shutdown command; A-to-B-to-A is blocked by the durable receipt set, while expiry limits only the first authorized scheduling attempt. If supervisor deletion or the shutdown command fails or its effect is unknown, emit one deduplicated NOTIFY and do not retry blindly.
'@
}

$marker = "watch-interrupted-task:fleet:v1 supervisor_thread_id=$SupervisorThreadId"
$hash = Get-WatchPromptSha256 -Body $body
$prompt = New-WatchPromptEnvelope -Marker $marker -Body $body -PolicyRevision 3

if ($AsJson) {
    [pscustomobject]@{
        supervisor_thread_id = $SupervisorThreadId
        policy_revision = 3
        watch_runtime_generation_id = $generationId
        prompt_sha256 = $hash
        shutdown_when_all_stopped = [bool]$ShutdownWhenAllStopped
        prompt = $prompt
    } | ConvertTo-Json -Depth 6 -Compress
}
else {
    $prompt
}
