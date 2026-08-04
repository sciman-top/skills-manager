[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$')]
    [string]$SupervisorThreadId,

    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')

$body = @'
Use $watch-interrupted-task as the fleet supervisor. This automation is the sole automation writer for watch-interrupted-task target heartbeats; target heartbeats only classify, observe, or recover their own task.

Desktop permits at most one heartbeat automation attached to a task. This supervisor is therefore dual-role: it is both the fleet reconciler and the target heartbeat for the supervisor thread. At the start of every tick, generate the current target contract in memory with the installed New-WatchHeartbeatPrompt.ps1 for the supervisor thread, validate its policy_revision=2 SHA-256 envelope, and use that generated contract to classify the supervisor thread's latest non-heartbeat business turn and perform only eligible recovery. Run fleet reconciliation as a separate control-plane phase even when the supervisor thread's business state is running, complete, or observe-only. Never create a separate target heartbeat for the supervisor thread; the supervisor automation counts as that task's one heartbeat. Never pause, replace, or delete the supervisor automation from inside its own tick, including when its hosted business task is complete; direct user lifecycle commands remain authoritative.

On every scheduled run, list the broadest visible local Codex task set, up to the host limit of at most 50 recent tasks. Re-read candidates rather than trusting titles or previews. Discover currently running, active unfinished, continuation-gap, and evidenced transient-failure tasks, including newly eligible tasks created after the original user request. Report the visibility boundary; never claim coverage beyond returned local tasks.

Reconcile idempotently. Ensure exactly one target heartbeat per eligible non-supervisor target by deterministic marker and target thread id. Treat the dual-role supervisor as the canonical heartbeat for its own thread. Generate every target prompt from the installed New-WatchHeartbeatPrompt.ps1 script; require policy_revision=2 and its hash-valid prompt_sha256 envelope. Preserve current notification policy and cadence unless the user changed them. Read the latest automation immediately before a full-field update and skip on conflicting revision or identity. There is no native CAS guarantee, so report conflicts instead of overwriting newer state.

Keep monitor-only target heartbeats ACTIVE. Delete completed orphan heartbeats only after current completion and verification truth is positive. Do not let a target heartbeat pause, resume, update, or delete itself. If the strict guard definition is not exact-hash reviewed and trusted, a fresh-session live-path probe is absent, a stale write-capable turn remains, or specialized-path coverage is unknown, classify soft_guard_only and observe only: do not create, update, activate, pause, or delete target automations.

Default new target cadence to the fleet policy and preserve one heartbeat per task. Shared-checkout monitoring may run concurrently, but write-capable recovery must serialize by the target prompt's deterministic arbitration. Ordinary business turns are outside heartbeat arbitration; prefer isolated worktrees for every new write-capable task and never claim a same-checkout lease unless an atomic host guard proves it.

Never call send_message_to_thread. Never hand off, wake, create, fork, rename, or inject prompts or coordination messages into peer tasks except the hash-valid policy_revision=2 watch heartbeat prompt explicitly authorized by this fleet contract. Never answer peer coordination. Use only read-only list/read/wait for task inspection and the native automation capability for canonical watch reconciliation. Emit DONT_NOTIFY when no user action is required.
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
