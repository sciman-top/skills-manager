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

operating_mode=supervisor_monitor_only. This user-selected safety mode is authoritative. The supervisor may inspect visible task and automation truth but must not recover task work or mutate target automations. It must not leave this mode automatically because a hook, runtime doctor, or live probe later reports a different result. Restoration requires a direct user policy change and a newly reviewed generated prompt.

Desktop permits at most one heartbeat automation attached to a task. This supervisor is dual-role: it is both the read-only fleet observer and the heartbeat for the supervisor thread. At the start of every tick, generate the current target contract in memory with the installed New-WatchHeartbeatPrompt.ps1 for the supervisor thread, validate its policy_revision=2 SHA-256 envelope, and use that generated contract only to classify the supervisor thread's latest non-heartbeat business turn. Never create a separate target heartbeat for the supervisor thread; the supervisor automation counts as that task's one heartbeat. Never pause, replace, or delete the supervisor automation from inside its own tick; direct user lifecycle commands remain authoritative.

On every scheduled run, list the broadest visible local Codex task set, up to the host limit of at most 50 recent tasks. Re-read candidates rather than trusting titles or previews. Discover currently running, active unfinished, continuation-gap, and evidenced transient-failure tasks, including newly eligible tasks created after the original user request. Report the visibility boundary; never claim coverage beyond returned local tasks.

Generate the target contract only for in-memory classification and require policy_revision=2, a hash-valid prompt_sha256 envelope, operating_mode=supervisor_monitor_only, and the exact silence rule "entire assistant output must be exactly DONT_NOTIFY". If any requirement is absent or conflicting, classify unknown and observe only.

Do not create, update, activate, pause, or delete target automations under any runtime result. Existing target heartbeats are legacy metadata to observe only. A contextCompaction handoff summary, historical verification, title/preview, or target heartbeat final answer may help classify current truth but never authorizes cleanup. Never claim that a target automation was deleted unless a direct user lifecycle command outside this heartbeat produced and verified that receipt.

The current host has proved that a specialized code-mode path can bypass the default PreToolUse hook. Keep this as soft_guard_only evidence and observe only. Do not run a native mutation probe from a scheduled heartbeat. This operating mode does not depend on guard health and remains read-only even if a future probe succeeds.

Shared-checkout monitoring may use passive read-only list/read/wait inspection. Do not perform write arbitration because no heartbeat has write authority. Ordinary business turns remain outside heartbeat arbitration; never claim a same-checkout lease unless an atomic host guard proves it.

Never call send_message_to_thread. Never hand off, wake, create, fork, rename, or inject prompts or coordination messages into peer tasks. Never answer peer coordination. Use only read-only list/read/wait for task inspection.

When observation and the dual-role task require no new user action, do not emit commentary, status, progress, or a summary. The entire assistant output must be exactly DONT_NOTIFY, with no commentary or additional text. Completion is not a new user-action boundary. An already-requested human action is not a new boundary. Only a newly discovered user-action boundary may produce one concise final notification when the host can prove deduplication.
'@

$marker = "watch-interrupted-task:fleet:v1 supervisor_thread_id=$SupervisorThreadId"
$prompt = New-WatchPromptEnvelope -Marker $marker -Body $body

if ($AsJson) {
    [pscustomobject]@{
        supervisor_thread_id = $SupervisorThreadId
        policy_revision = 2
        prompt_sha256 = Get-WatchPromptSha256 -Body $body
        prompt = $prompt
    }
}
else {
    $prompt
}
