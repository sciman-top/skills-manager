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
- Added `New-WatchFleetSupervisorPrompt.ps1`. It continuously discovers newly eligible visible local tasks, maintains exactly one target heartbeat per task, and is the sole automation writer.
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
- Green focused evidence: 29/29 watch, fleet, hook, installer, and doctor Pester cases passed after the final false-positive regression. Skill-integrity script tests also passed 11/11.
- The broader `SkillProjection.Tests.ps1` run passed 42/43 cases in the isolated worktree. Its sole failure searches for gitlink-backed imported skill contents that Git does not materialize in a new worktree; the populated root checkout contains all three required skills. This is not accepted as a full gate and must be recovered by the unique populated-root closeout gate after merge.
- Host projection is not live acceptance. Until `/hooks` review/trust and a fresh Desktop session prove the actual supported tool path without delivering a peer message, fleet automations remain `PAUSED` and the state is `soft_guard_only`.
- Official specialized-path limitations remain explicit even after a supported-path probe passes; the system never claims absolute cross-task isolation.
- `approval_policy = "never"` is an explicit preserved user setting and is outside this change set.

## Rollback

Rollback only this revision's override scripts, hook scripts, tests, metadata, and evidence. Rebuild the repository, restore the prior host hook definition through the reviewed installer path, and restore automation prompts/status only through the Desktop native automation capability. Do not edit automation TOML, stop Codex, overwrite unrelated hooks, or change approval policy.
