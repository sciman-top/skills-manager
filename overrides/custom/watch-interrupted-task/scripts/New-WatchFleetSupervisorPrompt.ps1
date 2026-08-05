[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$')]
    [string]$SupervisorThreadId,

    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')

$body = @'
Use $watch-interrupted-task as the fleet supervisor.

operating_mode=conditional_recovery. policy_revision=3 gives this dual-role heartbeat two narrow duties: apply the target recovery contract to the supervisor thread itself, and reconcile strictly canonical target heartbeats for eligible visible local Codex tasks. It never performs business work in another task and never injects a peer message.

Desktop permits at most one heartbeat attached to a task. Never create a separate target heartbeat for the supervisor thread. Apply the target recovery contract to the supervisor thread itself, but this scheduled turn cannot mutate its own automation. A direct user lifecycle command owns supervisor pause, resume, update, and deletion.

On every scheduled run, list the broadest visible local Codex task set, up to the current host limit of at most 50 recent tasks. Re-read candidates instead of trusting titles or previews. Include newly eligible tasks created after the original fleet request. Report the visibility limit only when user action is required; never claim coverage outside the returned local set.

Resolve target automation identity from fresh host metadata. For an eligible local task without a matching heartbeat, generate revision-3 target instructions only with New-WatchHeartbeatPrompt.ps1 and create or update only the canonical target heartbeat. Require the trusted canonical target body digest, exact target_thread_id marker, ACTIVE status, preserved notification policy, and a verified native receipt. Never accept a self-hashed or caller-authored body. Do not create a second heartbeat when one already matches.

For an existing target heartbeat, update only when fresh host metadata proves it is the same watch identity and its revision or trusted prompt digest is stale. Never overwrite a conflicting automation, another user's newer lifecycle action, or an unknown prompt. Delete only after verified completion: the target thread has fresh acceptance evidence, no active turn, an XML recovery receipt requesting supervisor cleanup, and any active Goal is terminal complete. Never delete for needs_input, paused Goal, transient failure, natural_pause, unknown, or missing evidence.

Use only read-only list/read/wait for task classification and peer arbitration. Never call send_message_to_thread. Never hand off, wake, create, fork, rename, or otherwise mutate a peer task. Fleet automation mutation is limited to canonical heartbeat enrollment, revision migration, and verified cleanup; it is not task recovery authority.

If canonical provenance, hook trust, automation identity, status, visibility, or receipt is missing or conflicting, leave the target unchanged and classify unknown. Never run destructive sentinels from a scheduled tick. Specialized paths remain guardrail_only unless separately live-proved; do not claim absolute isolation.

Finish with exactly this native XML shape and no text outside it. Copy automation_id from the heartbeat input. Routine reconciliation uses DONT_NOTIFY. Use NOTIFY only for a newly discovered, deduplicated human-action boundary.

<heartbeat>
  <automation_id>copy-current-automation-id</automation_id>
  <decision>DONT_NOTIFY|NOTIFY</decision>
  <message>state=...;receipt_key=...;visible_count=...;changed_count=...</message>
</heartbeat>
'@

$marker = "watch-interrupted-task:fleet:v1 supervisor_thread_id=$SupervisorThreadId"
$hash = Get-WatchPromptSha256 -Body $body
$prompt = New-WatchPromptEnvelope -Marker $marker -Body $body -PolicyRevision 3

if ($AsJson) {
    [pscustomobject]@{
        supervisor_thread_id = $SupervisorThreadId
        policy_revision = 3
        prompt_sha256 = $hash
        prompt = $prompt
    } | ConvertTo-Json -Depth 6 -Compress
}
else {
    $prompt
}
