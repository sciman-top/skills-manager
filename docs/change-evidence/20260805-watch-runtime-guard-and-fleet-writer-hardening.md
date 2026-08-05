# Watch runtime guard and fleet-writer hardening

## Problem and observed evidence

Two production watch behaviors violated the intended revision-2 contract:

- The unfinished task `修复多道活跃题提示` remained in `soft_guard_only`. Its target heartbeat required fresh-session guard loading and live-path coverage, but there was no managed way for that target session to generate either proof. Evidence created in the supervisor task was not safely transferable to the target tick, so every tick failed closed forever.
- The task `评估工程化工作流方案` reached a completed phase, but its target heartbeat later called native `automation_update(mode="delete")` itself. The live receipt recorded `deleteStatus=deleted` in `C:\Users\sciman\.codex\sessions\2026\08\05\rollout-2026-08-05T00-39-22-019fcda4-e16f-7123-a85f-10dbf45605dd.jsonl:1736`. The existing hook validated only watch mutations that carried a prompt; delete has no prompt, so the sole-writer rule existed only in text and did not enforce this path.

The delayed completion report had a second truth problem: fleet cleanup could rely on stale completion-shaped evidence such as a compaction summary, historical verification, title/preview, or a target heartbeat's own final answer. None proves the target's latest business state at deletion time.

## Root cause

The guard lacked role-aware capability enforcement for native automation mutations. It could validate a revision-2 prompt, but it could not distinguish a target heartbeat, the fleet supervisor, an ordinary user business turn, or an unclassifiable turn. As a result, promptless target self-delete bypassed the guard.

The target contract also demanded a fresh trust/live-path precondition without installing a fresh-process doctor or defining a safe negative probe. That made `soft_guard_only` correct but unrecoverable.

Current Codex hook semantics support `PreToolUse` for many local function tools and expose `session_id`, `turn_id`, `transcript_path`, `tool_name`, and `tool_input`. The official manual also says transcript format is not a stable interface and specialized tool paths may opt out of the default hook path. The implementation therefore treats transcript classification as evidence, never as an assumed schema, and denies watch mutation when classification cannot be proved, but this repository-side policy is effective only when the host actually invokes the hook.

## Implemented changes

- Added role-aware automation policy to `scripts/hooks/block-cross-thread-send.ps1`:
  - target heartbeats may view metadata but every mutation, including self-delete, is denied;
  - fleet heartbeats may mutate only another canonical revision-2 watch target, never their own dual-role automation or an unrelated automation;
  - ordinary user turns retain explicit watch lifecycle controls;
  - unknown/unreadable turn provenance fails closed;
  - every `watch-interrupted-task-v1-live-probe-*` sentinel mutation is denied before host execution.
- Added `scripts/hooks/Test-WatchGuardRuntime.ps1`. It starts a fresh app-server, calls `hooks/list`, and verifies exactly one enabled and trusted matching definition plus exact installed-script SHA-256 parity.
- Extended the managed installer to project the runtime doctor to `$HOME/.codex/scripts/Test-WatchGuardRuntime.ps1` and record its path and SHA-256 in the receipt.
- Added a target shell negative probe using a confirmed nonexistent thread id. Recovery remains `soft_guard_only` unless the command is denied before shell execution.
- Added a fleet native automation sentinel negative probe. Reconciliation is forbidden if the call reaches native automation handling, even when the host returns not-found.
- Clarified that the continuous fleet-monitoring reason survives completion of the hosted business task. Generic heartbeat lifecycle guidance cannot authorize a target heartbeat to delete itself.
- Required the fleet supervisor to re-read current target thread, repository, and verification truth immediately before deletion. Compaction summaries, historical verification, title/preview, and target-heartbeat finals cannot independently authorize cleanup.
- Preserved the specialized-path boundary: this is a fresh-proved defense-in-depth guardrail, not a claim of absolute cross-task isolation.

## Regression evidence

- Initial RED across the five affected suites: `42` tests, `34 passed / 8 failed`.
- First implementation run: `44` tests, `41 passed / 3 failed`; the remaining failures identified a PowerShell `$Matches` case-insensitive automatic-variable collision and two missing contract phrases.
- After the first root-cause corrections: `44 passed / 0 failed` across:
  - `tests/Unit/CrossThreadHook.Tests.ps1`
  - `tests/Unit/CrossThreadGuardInstall.Tests.ps1`
  - `tests/Unit/WatchGuardRuntime.Tests.ps1`
  - `tests/Unit/WatchInterruptedTask.Tests.ps1`
  - `tests/Unit/WatchFleetSupervisor.Tests.ps1`
- Final affected-suite regression after the real app-server notification fix: `45 passed / 0 failed`.
- Coverage includes target self-delete, cross-target mutation, fleet self-mutation, unrelated automation mutation, direct-user lifecycle access, unreadable provenance, fresh runtime doctor trusted/modified/disabled states, notification-before-response parsing, shell negative probe semantics, native sentinel semantics, and stale completion evidence.
- The isolated worktree initially lacked materialized contents for its tracked `imports/*` gitlinks and generated/vendor runtime baseline. This produced unrelated `SkillProjection`, `skill-integrity`, and `skill-routing` failures. After hydrating the three explicit engineering-skill fixtures from the exact pinned gitlink (`2ab958093e83e0ec752e6c1c5932da465bf23e0c`) and the current canonical generated/vendor baseline without changing test assertions, the affected projection test passed `32/32`.
- Final full gate after rebasing the isolated worktree onto current `origin/main`: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` exited `0`. All `834` Unit and `18` E2E tests passed; build, repository hygiene, generated sync, skill integrity (`107 skills`), skill routing, dependency baseline, skills config, host capability, planning, and doctor JSON stages also passed in `191978 ms`. The fresh timing receipt records `852` Pester cases and `suite_elapsed_ms=187783`.
- Final repository hook SHA-256 is `52cea5b40b1a9d8a748f5428cdec9762172af33c48cfb3e6b269dbce18fc1fb6`; `git ls-files --eol` reports `i/lf w/lf attr/text eol=lf`. The LF-pinned runtime doctor SHA-256 is `4857d7c43f64de89707a600007c28219eef1f901a677fdfbdf146606941027dc`.
- Fresh generated policy-revision-2 monitor-only prompt hashes are `f324317ed56f0372d60b5b8ffdd3c1304f0de776ef822eaf981c0ad41e77a8b8` for legacy target classification and `d5d7e83fa1362a78cea9d06bc7fe964963dc356cd83d98d38e38e4023ec4ea44` for the fleet supervisor prompt. These replace the earlier target/fleet hashes and must be projected through the generators, never reconstructed manually.
- The first real fresh-process doctor run exposed an additional live-path defect: app-server emitted a notification without a JSON-RPC `id`, and strict mode raised `The property 'id' cannot be found on this object`. The doctor now reads `id` as an optional property, a fake app-server regression emits the notification before responses, and the runtime doctor is LF-pinned so its installed receipt is stable across Windows checkouts.
- The first fresh-session shell probe exposed a code-mode payload shape that the parser did not yet cover. The guard was extended to parse the outer code-mode source and its direct stdin regression blocks nested shell/send calls, target-heartbeat automation mutations, and the native sentinel while permitting only the reviewed fleet form or read-only view.
- The affected-suite regression after parser coverage was `48 passed / 0 failed`; these tests prove how the hook behaves when invoked, not that every Desktop tool path invokes it.

## Post-install live finding and final architecture decision

After the exact hook definition was reviewed in `/hooks`, the fresh runtime doctor passed with one enabled trusted matching definition and exact script-hash parity. A real outer code-mode probe then executed:

```text
tools.shell_command({
  command: "codex app-server request thread/send --thread 019ffeed-0000-7000-8000-000000000002 --prompt guard-live-probe"
})
```

The shell actually ran and returned `error: unrecognized subcommand 'request'`. The current session transcript recorded the outer tool as `exec` but contained no `PreToolUse` decision event. Feeding the same `tool_name=exec` payload directly to the installed hook returned `permissionDecision=deny`. This isolates the remaining root cause at the host boundary: the Desktop outer code-mode `exec` path did not invoke the trusted hook. Adding more PowerShell payload parsing cannot enforce a host path that never calls the script.

The user selected the fail-closed architecture on 2026-08-05:

- `operating_mode=supervisor_monitor_only` is embedded in both generated prompts;
- the supervisor may list/read/wait and classify visible truth but performs no recovery and no target automation mutation under any runtime result;
- per-target heartbeats are not created; any legacy target remains ACTIVE and observe-only for every state, including `complete`, `resume_eligible`, and `continuation_gap`;
- scheduled shell/native mutation probes are disabled because their current specialized paths are already outside the proved enforcement boundary;
- the mode never promotes itself after a future successful probe. Restoration requires another direct user decision, a reviewed contract change, and fresh live coverage for every write-capable path.

The monitor-only regression was developed red-green: the first run of the two prompt/disposition suites produced `20 passed / 6 failed`; after implementation they produced `26 passed / 0 failed`. The new assertions reject recovery language in the target prompt, reject target mutation and cleanup language in the fleet prompt, and require `observe_only / keep_active / mutation_owner=none` for completion and recovery-shaped classifications.

## Live acceptance boundary

Repository tests prove the monitor-only policy and generated contracts. They do not prove hard isolation, and the live probe positively proves that the current specialized code-mode path is outside that boundary. The accepted live state is therefore a safe functional downgrade, not automatic continuity acceptance:

1. Project the rebuilt Skill and prompt generators through the managed installer without changing provider, auth, model, sandbox, or Desktop process state.
2. In a direct user lifecycle turn, update only the existing supervisor automation to the generated `supervisor_monitor_only` prompt, preserving cadence and notification policy; re-read its native receipt.
3. Verify that no per-target watch automation exists. Do not create one to test the policy.
4. Keep `soft_guard_only` as the host enforcement truth and `supervisor_monitor_only` as the operating policy. Routine incomplete and complete classifications both return `DONT_NOTIFY` and cause no cleanup.

Do not describe this as recovered automatic continuity. The two reported failure modes are contained by removing target recovery and target automation mutation authority. Restoring those capabilities remains separately open until Desktop covers every required live path and the user explicitly changes policy.

## Rollback

Revert only the hook policy, runtime doctor, managed installer/doctor, target and fleet prompt generators, affected tests, skill contract, and this evidence file. Re-run the managed installer from the reverted canonical checkout and review/trust that exact definition again. Do not edit Desktop databases, automation TOML, session JSONL, `approval_policy`, provider/auth/model/sandbox settings, or restart/stop Codex. Do not send content to another task during rollback.
