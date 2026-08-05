# Watch runtime guard and fleet-writer hardening

## Problem and observed evidence

Two production watch behaviors violated the intended revision-2 contract:

- The unfinished task `修复多道活跃题提示` remained in `soft_guard_only`. Its target heartbeat required fresh-session guard loading and live-path coverage, but there was no managed way for that target session to generate either proof. Evidence created in the supervisor task was not safely transferable to the target tick, so every tick failed closed forever.
- The task `评估工程化工作流方案` reached a completed phase, but its target heartbeat later called native `automation_update(mode="delete")` itself. The live receipt recorded `deleteStatus=deleted` in `C:\Users\sciman\.codex\sessions\2026\08\05\rollout-2026-08-05T00-39-22-019fcda4-e16f-7123-a85f-10dbf45605dd.jsonl:1736`. The existing hook validated only watch mutations that carried a prompt; delete has no prompt, so the sole-writer rule existed only in text and did not enforce this path.

The delayed completion report had a second truth problem: fleet cleanup could rely on stale completion-shaped evidence such as a compaction summary, historical verification, title/preview, or a target heartbeat's own final answer. None proves the target's latest business state at deletion time.

## Root cause

The guard lacked role-aware capability enforcement for native automation mutations. It could validate a revision-2 prompt, but it could not distinguish a target heartbeat, the fleet supervisor, an ordinary user business turn, or an unclassifiable turn. As a result, promptless target self-delete bypassed the guard.

The target contract also demanded a fresh trust/live-path precondition without installing a fresh-process doctor or defining a safe negative probe. That made `soft_guard_only` correct but unrecoverable.

Current Codex hook semantics support `PreToolUse` for local function tools, including native automation management, and expose `session_id`, `turn_id`, `transcript_path`, `tool_name`, and `tool_input`. The official manual also says transcript format is not a stable interface. The implementation therefore treats transcript classification as evidence, never as an assumed schema, and denies watch mutation when classification cannot be proved.

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
- After root-cause corrections: `44 passed / 0 failed` across:
  - `tests/Unit/CrossThreadHook.Tests.ps1`
  - `tests/Unit/CrossThreadGuardInstall.Tests.ps1`
  - `tests/Unit/WatchGuardRuntime.Tests.ps1`
  - `tests/Unit/WatchInterruptedTask.Tests.ps1`
  - `tests/Unit/WatchFleetSupervisor.Tests.ps1`
- Coverage includes target self-delete, cross-target mutation, fleet self-mutation, unrelated automation mutation, direct-user lifecycle access, unreadable provenance, fresh runtime doctor trusted/modified/disabled states, shell negative probe semantics, native sentinel semantics, and stale completion evidence.
- The isolated worktree initially lacked its tracked `mattpocock/skills` gitlink checkout and generated/vendor runtime baseline. This produced unrelated `SkillProjection`, `skill-integrity`, and `skill-routing` failures. After hydrating the exact pinned gitlink (`2ab958093e83e0ec752e6c1c5932da465bf23e0c`) and the current canonical generated/vendor baseline without changing test assertions, the affected projection test passed `32/32`.
- Final full gate: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` exited `0`. Build, complete Unit/E2E, repository hygiene, generated sync, skill integrity (`107 skills`), skill routing, dependency baseline, skills config, host capability, planning, and doctor JSON stages all passed in `171548 ms`.
- Final repository hook SHA-256 is `e425ceb2afb505c2ea271bc45c109682c74269c9e1b38d2090dde08a0158b4a8`; `git ls-files --eol` reports `i/lf w/lf attr/text eol=lf`. The runtime doctor SHA-256 is `650b26cefb5202455d41f3d5add42805af625047ce85f7f7343b464da198bcb8`.
- Fresh generated policy-revision-2 prompt hashes are `a6bb7b28516027e7895206d96e933f4e45cf7c68abadc533b4a031f1ae5109b4` for target prompts and `43671532d2fdb2863119768987d2fba7a61045193b24dfee4c30411c2b6a1705` for the fleet supervisor prompt. These replace the earlier target/fleet hashes and must be projected through the generators, never reconstructed manually.

## Live acceptance boundary

Repository tests prove the policy and generated contracts, not that the new host definition is already loaded and trusted. Installing these changed bytes creates a new hook definition hash and intentionally returns `installed_untrusted`. Live acceptance requires all of the following after merge:

1. Run the managed installer from the merged canonical checkout.
2. Review and trust the new exact definition in `/hooks` from a fresh Codex session.
3. Run the installed runtime doctor and require `configuration_ready=true`.
4. Prove the shell sender negative path is denied before shell execution using a nonexistent thread id.
5. Prove the native automation sentinel is denied before the host automation call using a nonexistent sentinel id.
6. Only then project fresh generated target and fleet prompts through native automation management and re-read every receipt.

Until those steps pass, the correct state remains `soft_guard_only`; do not claim the two live automations are repaired merely because repository gates pass.

## Rollback

Revert only the hook policy, runtime doctor, managed installer/doctor, target and fleet prompt generators, affected tests, skill contract, and this evidence file. Re-run the managed installer from the reverted canonical checkout and review/trust that exact definition again. Do not edit Desktop databases, automation TOML, session JSONL, `approval_policy`, provider/auth/model/sandbox settings, or restart/stop Codex. Do not send content to another task during rollback.
