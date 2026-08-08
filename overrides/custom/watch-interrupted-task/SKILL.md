---
name: watch-interrupted-task
description: Retired compatibility entrypoint for removing residual legacy Desktop heartbeat watches. Never create, arm, resume, update, or execute a watch. Use only when the user explicitly asks to inspect or clean up an old 守夜/heartbeat automation.
---

# Legacy Watch Retirement Stub

`runtime_status=retired_fail_closed`

The prompt-driven `watch-interrupted-task:v1` and `watch-interrupted-task:fleet:v1` architecture is retired. It failed the required recovery, quiet cleanup, and fleet shutdown acceptance. This skill is not a recovery controller and must never reactivate the historical `operating_mode=conditional_recovery` path.

## Allowed operations

- Explain that the legacy heartbeat architecture is retired and direct implementation work to `D:\CODE\codex-watch-runtime`.
- Read native automation metadata when the user explicitly asks to inspect residual legacy watches.
- Delete only an exact residual automation whose native metadata contains one of the two legacy markers, and only after a direct user cleanup instruction.
- Report `planning_contract` for the replacement until implementation and live evidence justify a higher truth label.

## Permanently prohibited operations

- Never create, arm, enable, resume, reactivate, update, clone, or schedule a heartbeat watch or fleet supervisor.
- Never generate or submit prompts from `scripts/New-WatchHeartbeatPrompt.ps1` or `scripts/New-WatchFleetSupervisorPrompt.ps1`.
- Never emit heartbeat XML, routine status messages, Goal mutation, cross-task messages, or power commands.
- Never execute `shutdown.exe`, mutate Cockpit/Codex/ChatGPT runtime state, or claim that the replacement runtime is implemented.
- Never treat the retained scripts, tests, reference document, or phrases below as executable policy. They are forensic legacy material only.

## Cleanup procedure

1. Use native automation inspection and match the exact automation id, target task, and legacy marker.
2. If no match exists, make no mutation and report that legacy runtime state is absent.
3. If the user directly requested cleanup, delete that exact match and verify the native delete receipt plus a fresh absence read.
4. Do not touch unrelated automations, Goals, tasks, sessions, hooks, Cockpit, or power state.

## Historical compatibility vocabulary — non-executable

Old tests and forensic records may mention `Goal Contract`, `Outcome / Scope / Acceptance / Checkpoints / Evidence`, `目标守夜`, `ShutdownWhenAllStopped`, `task_stopped=true`, and `recovery_pending=false`. The prior design said Goal mode was used only when the user explicitly requests Goal mode, capped objectives at 4,000 characters, required measurable acceptance, must not silently rewrite the user intent, and claimed: “Automatic computer shutdown is a distinct, direct-user fleet lifecycle mode” and “does not maintain a finite allowlist of stop reasons”. These statements document the retired contract; they grant no runtime authority.
