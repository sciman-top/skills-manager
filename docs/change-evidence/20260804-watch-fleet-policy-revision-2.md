# Watch fleet policy revision 2

## Problem and root cause

Repeated live incidents showed that the previous heartbeat repair still had four coupled failure modes:

1. The skill and each automation carried separate durable-prompt copies. Tests searched the whole skill instead of the prompt actually sent to Desktop, so stale or unsafe prompt text could pass.
2. `natural_pause`, `needs_input`, deterministic failures, and `unknown` changed the automation to `PAUSED`. A normal phase boundary therefore stopped monitoring and required manual reactivation.
3. “Enable watch for all executing tasks” enrolled a one-time snapshot. Newly active tasks had no reconciler, while each target heartbeat could rewrite its own full automation record and race newer metadata.
4. The user hook matched only three direct send tool spellings, referenced a shared checkout path, and had no protection for prompt-bearing handoff, cross-target automation injection, shell/app-server bypass, missing protocol fields, or script drift behind a previously trusted command definition.

The shared-checkout issue has a separate boundary: heartbeat `peer_busy` arbitration runs only inside heartbeat recovery. It cannot serialize ordinary business turns that are already writing the same checkout. Monitoring concurrency and mutation concurrency were incorrectly treated as the same problem.

## Implemented changes

- Added `New-WatchHeartbeatPrompt.ps1` as the single target-prompt source. It emits the stable v1 identity marker plus `policy_revision=2` and a SHA-256 envelope.
- Added an executable disposition table. Monitor-only states keep automation `ACTIVE`; only explicit user pause changes status to `PAUSED`. Verified completion is exposed for supervisor cleanup rather than target self-deletion.
- Added `New-WatchFleetSupervisorPrompt.ps1`. It continuously discovers newly eligible visible local tasks, maintains exactly one heartbeat per task, and is the sole automation writer. Because Desktop accepts only one heartbeat attachment per task, it is dual-role and also applies the generated target contract to its own host task.
- Hardened native mutation receipts: a create receipt without actual status is followed by a host metadata read, and any fail-closed `PAUSED` request persisted as `ACTIVE` is corrected and reverified through a full-field native update.
- Removed the direct-user cross-task messaging escape hatch from both the skill and generated target prompt.
- Excluded heartbeat turns from peer activity and retained eligibility-first, deterministic shared-checkout arbitration for recovery work.
- Made isolated worktrees the default contract for new write-capable tasks. Ordinary same-checkout turns remain unsafe until a separately implemented atomic host lease is live-proved.
- Expanded the `PreToolUse` guard to deny direct send tools, prompt-bearing handoffs, noncanonical cross-target automation prompts, and explicit shell/app-server send bypasses. Malformed input, missing `tool_name`, and installed-script hash drift fail closed.
- Added an installer that preserves unrelated hooks, writes the guard to a stable host-local path, and includes the content hash in the reviewed command definition. It does not read or write `approval_policy` and does not edit `config.toml`.
- Added a read-only doctor that checks feature/config presence, definition shape, source/host hash parity, and protocol simulation. It intentionally reports `soft_guard_only` until `/hooks` exact-definition trust and a fresh-session live-path probe are independently established.

## Official behavior used

- Non-managed command hooks must be reviewed and trusted for the current definition; changed definitions are skipped until trusted: <https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks>.
- `PreToolUse` covers shell, unified exec, `apply_patch`, MCP, and most local function tools, but specialized paths may opt out. Hooks are therefore a guardrail, not a complete enforcement boundary: <https://learn.chatgpt.com/docs/hooks#tool-coverage>.
- Thread heartbeats remain the native continuity surface; automation metadata is mutated only through the Desktop automation API: <https://developers.openai.com/codex/app/automations>.

## Verification plan and current boundary

- Red evidence: the first focused run failed on the missing generators, handoff and Bash bypasses, absent fail-closed field validation, and absent installer/doctor.
- Green focused evidence: the original watch, fleet, hook, installer, and doctor slice passed 29/29, with skill-integrity script tests at 11/11. After live host acceptance exposed two additional contract gaps, the final affected build/test run passed 43/43.
- The broader `SkillProjection.Tests.ps1` run passed 42/43 cases in the isolated worktree. Its sole failure searches for gitlink-backed imported skill contents that Git does not materialize in a new worktree; the populated root checkout contains all three required skills. This is not accepted as a full gate and must be recovered by the unique populated-root closeout gate after merge.
- The final populated-root closeout gate `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full` exited 0 in 170,226 ms after the dual-role and create-receipt fixes. Its build, full Unit suite, E2E 18/18, repository hygiene, generated sync, skill integrity 107, routing, dependency baseline, skills config, host capability, planning, and doctor JSON stages all passed.
- The post-gate runtime projection `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 构建生效` reported 108 agent skills, 111 projection entries, 0 conflicts, and `Persisted=True`.
- The six `watch-interrupted-task` files have identical SHA-256 values across `overrides/`, generated `agent/`, and projected `~/.agents/skills/`: `SKILL.md` `a2e35499bc0c4d18e6f898ffadeec020084daa1a2cfbce403910f425ff65e11c`; `agents/openai.yaml` `1ab44e43922486cdef1e05c56701330966e9702701182afbe6d3a426498ddd70`; disposition `b5c15db7042312315d0766892de4615b95cf0333d2e5691b0f4c3ace5eba739f`; fleet prompt `9000078d47ffa1a572f0bd9d7645622e61d55b8d0879c95231ec40da8e2ae639`; target prompt `30327465d42bb7fe2506e5d19d0ea0afcffadb554641e030794efd761f4f1de2`; common prompt helper `79c2d593b80f2a3323de3da71a288e884656ad6e3abf619b15b32bd5533c63d2`.
- Global user rules were rechecked after the final v9.66 self-reference update: Codex/Claude A, C, and D sections are byte-normalized equal; Codex is 119 lines / 13,150 bytes and Claude is 120 lines / 13,582 bytes. A fresh `codex debug prompt-input` exited 0 and exposed v9.66, the absolute cross-task-send ban, `soft_guard_only`, the specialized-path boundary, and this repository contract.
- The host guard installer currently has source/host SHA-256 parity at `b38177095ed83fcfc9328d712ac0b7a892243d8870873840a90f651703323106`. The doctor reports `configuration_ready=True`, `definition_matches=True`, `simulation_passed=True`, `trust_status=unverified_requires_slash_hooks`, `live_path_status=unverified_requires_fresh_session_probe`, and `overall=soft_guard_only`.
- Host projection is not live acceptance. Until `/hooks` review/trust and a fresh Desktop session prove the actual supported tool path without delivering a peer message, fleet automations remain `PAUSED` and the state is `soft_guard_only`.
- Official specialized-path limitations remain explicit even after a supported-path probe passes; the system never claims absolute cross-task isolation.
- `approval_policy = "never"` remains present in `~/.codex/config.toml` and was not modified; it is an explicit preserved user setting outside this change set.

## Live Desktop fleet acceptance findings

- Creating a separate supervisor heartbeat on a task that already had its target heartbeat was rejected by the native API: `This thread already has an active heartbeat automation. Only one automation can be attached to this thread.` The root cause was a revision-2 architecture assumption that the supervisor and target could be double-attached to one task.
- The supervisor is now dual-role. It reconciles the fleet and applies the target contract generated by `New-WatchHeartbeatPrompt.ps1` to its own host task. The supervisor task receives no second target heartbeat, and its existing automation is updated in place; no extra task or cron workaround is created.
- A native create request that supplied `status=PAUSED` returned only a creation receipt and persisted one target as `ACTIVE`. The mandatory post-mutation metadata read detected the mismatch; a full-field native update restored `PAUSED`. The contract now treats status-less create receipts as insufficient and requires the same corrective read/update/verify sequence.
- A final broad task-list reconciliation discovered newly started active task `019fcda4-e16f-7123-a85f-10dbf45605dd` after the initial three-task snapshot. Because the supervisor must remain paused before hook trust, the user-facing setup flow enrolled it through the same native revision-2 target generator. Its create again persisted `ACTIVE`; the required read/update/verify sequence immediately restored `PAUSED`. This proves manual standing-request reconciliation, not scheduled supervisor execution.
- The final native metadata read shows exactly four unique task targets at a 10-minute cadence, all `PAUSED`, all `policy_revision=2`: targets `019fcb85-7b8c-7740-abf7-08b821eb899a`, `019fcbba-2a2a-7152-8089-414f0befef6e`, and `019fcda4-e16f-7123-a85f-10dbf45605dd`, plus dual-role supervisor `019fcbe5-8111-75d1-abed-c2be479097a6`. The supervisor envelope is `prompt_sha256=01d23f1f661e3743e81d678526d9194f9b74e40ef83da5529ef80d3c89d41989`; target envelopes are `prompt_sha256=426adb86cc5e1e900bb44fe5da3554570728e147d50ccdf5ec0e547eb37d7449`.
- The automation id of the in-place converted supervisor retains its former target-shaped id. Automation ids are host-owned opaque identifiers; the fleet role is established by the current name/prompt marker and revision-2 envelope, not by renaming the id or editing host TOML.
- The native API exposes no first-run/start-time control. Sequential creation was used, but verified staggering remains `platform_na`: `reason=no native first-run field`; `alternative_verification=10-minute cadence plus sequential receipts`; `evidence_link=native automation receipts and metadata read`; `expires_at=when host adds first-run control`; `recovery_condition=reconfigure and verify explicit staggering`.

This final evidence append does not change source, generated output, or runtime projection. Under the repository closeout contract, another full repetition is `gate_na`: `reason=evidence-only append after the final passing code-state full gate`; `alternative_verification=git diff --check plus repository status, automation metadata, and SHA parity`; `evidence_link=this document`; `expires_at=on any source/generated/config change`; `recovery_condition=rerun full before the next code closeout`.

## Rollback

Rollback only this revision's override scripts, hook scripts, tests, metadata, and evidence. Rebuild the repository, restore the prior host hook definition through the reviewed installer path, and restore automation prompts/status only through the Desktop native automation capability. Do not edit automation TOML, stop Codex, overwrite unrelated hooks, or change approval policy.
