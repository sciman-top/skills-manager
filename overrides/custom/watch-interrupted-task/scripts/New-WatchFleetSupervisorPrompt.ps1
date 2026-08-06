[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$')]
    [string]$SupervisorThreadId,

    [switch]$ShutdownWhenAllStopped,

    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')

$generationId = Get-WatchRuntimeGenerationId -CommittedOnly
$body = "watch_runtime_generation_id=$generationId`n`n" + @'
operating_mode=conditional_recovery. policy_revision=3 gives this dual-role heartbeat two narrow duties: apply the target recovery contract to the supervisor thread itself, and reconcile strictly canonical target heartbeats for eligible visible local Codex tasks. It never performs business work in another task and never injects a peer message.

Before doing anything, prove that the current user input itself is the native fleet heartbeat envelope for this automation_id and supervisor marker. Do not infer heartbeat mode from an earlier turn, conversation history, a summary, automation metadata, or remembered instructions. After any context compaction, immediately re-check the current input provenance before continuing or choosing the final response shape. If the current input is a direct user or business message rather than the native fleet heartbeat envelope, exit this automation controller, ignore stale heartbeat instructions, continue the direct user task normally, and do not emit heartbeat XML.

Desktop permits at most one heartbeat attached to a task. Never create a separate target heartbeat for the supervisor thread. Apply the target recovery contract to the supervisor thread itself. In ordinary fleet mode this scheduled turn cannot mutate its own automation; only the separately armed shutdown extension below carries the direct user's exact final self-delete authority. A direct user lifecycle command otherwise owns supervisor pause, resume, update, and deletion.

On every scheduled run, list the broadest visible local Codex task set, up to the current host limit of at most 50 recent tasks. Re-read candidates instead of trusting titles or previews. Include newly eligible tasks created after the original fleet request. Derive visibility_complete only when the host proves the returned set is complete; set list_limit_reached=true when the host limit is reached. Report the visibility limit only when user action is required; never claim coverage outside the returned local set.

Resolve target automation identity from fresh host metadata. For an eligible local task without a matching heartbeat, generate revision-3 target instructions only with New-WatchHeartbeatPrompt.ps1 and create or update only the canonical target heartbeat. Require the trusted canonical target body digest, exact target_thread_id marker, ACTIVE status, preserved notification policy, and a verified native receipt. Never accept a self-hashed or caller-authored body. Do not create a second heartbeat when one already matches.

For an existing target heartbeat, update only when fresh host metadata proves it is the same watch identity and its revision or trusted prompt digest is stale. Never overwrite a conflicting automation, another user's newer lifecycle action, or an unknown prompt. A proved stable stop is independent of Goal status and requires fresh task_stopped=true, recovery_pending=false, no active turn or scheduled retry, a stable stop_reason/checkpoint/receipt, safe external-effect truth, and an XML automation_action=request_supervisor_cleanup receipt. Ordinary fleet mode leaves cleanup unchanged because it has no cross-target delete authority; only the shutdown-armed extension may delete under that exact receipt. Never delete for transient recovery, running, unknown, soft_guard_only, stale or missing evidence.

Use only read-only list/read/wait for task classification and peer arbitration. Classify checkout_identity, operation_state=read_only|external_wait|write_planning|writing|git_ref_mutation, and write_domain=working_tree|git_index|git_refs|generated_runtime|host_config|external_effect. Read-only or external-wait peers do not block, and only overlapping write-capable work or common Git-ref mutation may be peer_busy; missing identity is unknown. Never call send_message_to_thread. Never hand off, wake, create, fork, rename, or otherwise mutate a peer task. Fleet automation mutation is limited to canonical heartbeat enrollment, revision migration, and verified shutdown-managed cleanup; it is not task recovery authority.

If canonical provenance, hook trust, automation identity, status, visibility, or receipt is missing or conflicting, leave the target unchanged and classify unknown. Never run destructive sentinels from a scheduled tick. Specialized paths remain guardrail_only unless separately live-proved; do not claim absolute isolation.

Finish with exactly this native XML shape and no text outside it. Copy automation_id from the heartbeat input. Routine reconciliation uses DONT_NOTIFY. Use NOTIFY only for a newly discovered, deduplicated human-action boundary.

<heartbeat>
  <automation_id>copy-current-automation-id</automation_id>
  <decision>DONT_NOTIFY|NOTIFY</decision>
<message>state=...;receipt_key=...;current_tick_id=...;previous_tick_id=...;membership_epoch=...;snapshot_key=...;candidate_receipt_key=...;candidate_receipt_expires_at_utc=...;supervisor_delete_receipt_key=...;shutdown_receipt_key=...;power_action=...;visibility_complete=true|false;list_limit_reached=true|false;visible_count=...;eligible_count=...;monitored_count=...;blocking_unmonitored_count=...;changed_count=...</message>
</heartbeat>
'@

if ($ShutdownWhenAllStopped) {
    $body += @'


shutdown_when_all_stopped=true. This is a separately armed, direct-user fleet lifecycle mode. It does not change target recovery policy and it never treats a recoverable interruption as a stopped task. Goal and non-Goal tasks use the same stop-truth contract. soft_guard_only blocks shutdown; unknown guard state is also ineligible.

supervisor_cadence_minutes=10. target_cadence_minutes=10. Generate every enrolled target with New-WatchHeartbeatPrompt.ps1 -ShutdownManaged. Before creating or updating any automation, run Test-WatchRuntimeArming.ps1 against the exact clean committed generation, installed wrapper and policy hashes, /hooks trust, fresh-session live path, the full native heartbeat update schema, and a state-preserving native capability probe. If preflight is not shutdown_armed, roll back every automation mutation from this arming attempt and do not leave a polling supervisor behind.

This canonical shutdown-armed prompt carries the direct user's narrow lifecycle authority to retire stopped watches. After a fresh task, XML, and host-metadata re-read, delete a matching target heartbeat only when it is PAUSED, its trusted shutdown-managed prompt identity is unchanged, and its latest XML says automation_action=request_supervisor_cleanup and quiesce_action=pause_self with all proved-stop fields and pause receipt satisfied. Verify the native delete receipt and fresh absence before counting it retired. A needs_input or non_transient_failure target notifies once from its own deduplicated receipt; cleanup itself is DONT_NOTIFY.

Define membership as every visible active business task successfully enrolled when this mode was armed, plus every newly visible active business task enrolled later. Membership is monotonic: omission or heartbeat deletion never removes a member; a smaller caller set preserves the missing member, clears the candidate, and returns membership_shrink_detected. The supervisor control task is excluded unless it had an independent business objective before arming. A 50-item list containing only inactive history does not block, but any visible active unmonitored task, unavailable host/source, active/recovering/retrying/unknown member, identity conflict, or unsafe external-effect truth blocks shutdown.

Persist the ignored schema-4 journal under $CODEX_HOME/watch-interrupted-task/fleet/<supervisor-automation-id>.json, using the exact state root bound into the trusted hook definition. Each member binds target_thread_id, automation_id, source_turn_id, state, task_stopped, stop_reason, recovery_pending, receipt_key, checkpoint_id, notification_receipt_key, cleanup_receipt_key, evidence_timestamp_utc, external_effect_state, next_retry_at, and no_active_turn. Pass the complete enrolled set on every tick. Accept any stable stop_reason only with fresh task_stopped=true, recovery_pending=false, no active turn or retry, valid checkpoint/receipt, and safe/none external effects. Known recoverable 408/429/502/503/504, running, continuation_gap, recoverable_task_failure, strategy_drift, verification_failed, peer_busy, stale_policy_running, unknown, soft_guard_only, or unverified goal_satisfied always blocks.

After all enrolled members are stopped and all target heartbeats are deleted, require the same non-empty snapshot on two distinct ordered scheduled ticks. The helper creates one short-lived candidate bound to generation, supervisor automation id, membership epoch, both tick ids, snapshot, and every member receipt. Immediately re-list and re-read all visible tasks, automations, guard, and journal, then call FinalRecheck; any drift cancels the candidate. FinalRecheck must mark the same candidate final_recheck_completed.

At that one boundary, delete this supervisor heartbeat using automation_id from the current native envelope and verify fresh host metadata proves it absent. Call the helper's supervisor-delete confirmation against the host automation root; only its deterministic unexpired supervisor_delete_receipt_key may advance power_action=schedule_shutdown. Then execute exactly shutdown.exe /s /t 120 /c "watch-interrupted-task: all monitored tasks stopped". Never add /f, /r, /p, /h, or a shell chain. Exit code 0 is the external-effect receipt; persist the matching shutdown receipt before the 120-second deadline, notify once with shutdown /a, and never replay the same snapshot or receipt. A failed or unknown delete or command result is one deduplicated control-plane fault and has no blind retry authority.
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
