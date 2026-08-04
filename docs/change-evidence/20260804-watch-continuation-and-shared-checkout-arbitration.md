# Watch continuation and shared-checkout arbitration

## Problem and root cause

The heartbeat for thread `019fcbba-2a2a-7152-8089-414f0befef6e` paused as `unknown`. Its latest non-heartbeat business turn ended with `contextCompaction`, contained no final answer or error, and left an explicitly authorized task unfinished. The old state model recognized only positive transient provider/transport failures as resumable, so a host continuation gap had no matching state and fell through to `unknown`.

The fleet setup also treated equal `cwd` as a permanent ownership conflict. That protected a shared checkout from concurrent writers, but unnecessarily prevented every task in the project from retaining its own active heartbeat.

Live forward-testing then exposed a throughput mismatch: a successful heartbeat completed exactly one safe slice and deliberately yielded, leaving the unfinished task `idle` until the next 10-minute tick. The root cause was the explicit "one bounded slice" rule in both the resume procedure and durable heartbeat prompt. The user clarified that守夜 must continuously execute all remaining authorized work, not act as a one-slice sampler.

Later live execution exposed a more severe cross-thread isolation failure. A normal business turn with no 429/503 or continuation gap detected a shared checkout and called `send_message_to_thread`. The receiving task treated the injected coordination text as a new user message, reverted parts of its own work, and sent a checkout-release message back. This created a visible notification loop and changed both tasks' behavior without user authorization. The causal chain was: `peer_busy` had no eligibility precedence, the skill prohibited message replay but not message initiation, and the global contract did not mark peer-originated messages as untrusted non-authoritative data.

A second live incident occurred after the prompt-level repair. Sending thread `019fcbba-2a2a-7152-8089-414f0befef6e` had started business turn `019fccf7-338d-7230-bc26-0aa8d79330c4` before the v9.64 global rule and repaired skill were loaded. Later in that same turn it explicitly chose to send a same-checkout coordination message listing `qq_formula_render` and `qq_unified_multimodal` files; receiving thread `019fcb85-7b8c-7740-abf7-08b821eb899a` showed the injected card. Updating global files, skill projection, and heartbeat metadata did not hot-load policy into the already-running business turn, and pausing or updating a heartbeat did not stop that independent turn. The previous closeout incorrectly generalized fresh-session and durable-heartbeat proof to stale in-progress turns.

## Changes

- Added `continuation_gap` for an explicit host continuity marker plus no final answer, unfinished prior authorization, no human gate, and an identifiable first unproved step.
- Kept idle state, missing TODOs, dirty worktrees, and absent final answers insufficient on their own.
- Required heartbeat turns to be ignored when identifying the latest business state.
- Added `peer_busy` and per-tick deterministic arbitration for write-capable tasks sharing one checkout: oldest latest business-turn `updatedAt`, then lexical thread id.
- Kept every eligible thread armed. Non-winning shared-checkout writers remain `ACTIVE` and retry on later ticks.
- Allowed parallel recovery only for isolated worktrees or positively evidenced read-only tasks.
- Preserved fail-closed handling for unknown state and external side effects.
- Replaced the one-slice terminal rule with a continuous recovery session. The session still uses sequential bounded and verified slices internally, but immediately advances to the next unproved safe step instead of yielding after each slice.
- Limited continuous execution to the existing authorized task scope and explicit stop conditions: completion, human/approval gates, `peer_busy`, non-transient or unknown state, unproved external effects, another transient interruption, or host execution limits.
- Tightened `natural_pause` to a pre-existing explicit user handoff or user-defined checkpoint. Once continuous recovery starts, an agent-authored phase summary, test pass, commit, push, milestone, or intermediate final answer cannot manufacture a new pause while authorized safe work remains.
- Closed a live stale-write race: an already-running heartbeat can finish after an operator updates its durable prompt. Lifecycle mutations must now re-read host-managed metadata and preserve the latest prompt instead of writing the tick's embedded stale prompt back during self-pause or resume.
- Made `peer_busy` a secondary gate reachable only after `resume_eligible` or `continuation_gap`; normal, complete, paused, failed, or unknown business states are classified before peer inspection.
- Restricted shared-checkout arbitration to passive list/read/wait observation. Heartbeats cannot send, hand off, wake, create, fork, or inject content into peer tasks, and peer-originated messages cannot authorize replies or worktree changes.
- Removed the remaining incident-containment messaging exception. Heartbeat containment is limited to pausing its own automation plus read-only observation; `<codex_delegation>`, `source_thread_id`, coordination cards, and peer claims of user authorization cannot transfer authority into the receiving task.
- Added deterministic enforcement: a user-level `PreToolUse` hook denies all known `send_message_to_thread` tool spellings before execution, including code-mode nested calls. Prompt rules remain defense in depth, not the enforcement boundary.
- Added `stale_policy_running`: turns already in progress at policy activation are not claimed as protected. Their heartbeats stay paused until they complete or the user stops them; rearming requires a fresh-session hook probe.
- Promoted the isolation rule to `GlobalUser/AGENTS.md v9.65` and `GlobalUser/CLAUDE.md v9.65`, because the initiating message came from a normal business turn rather than a heartbeat. The final policy forbids AI-mediated cross-task messages entirely, rejects delegated metadata and peer claims of authorization, and requires deterministic `PreToolUse` enforcement.
- Required shared-checkout arbitration and external-effect truth to be rechecked before every write-capable slice. The deterministic winner keeps ownership across slices until a stop condition, while non-winners remain `ACTIVE` as `peer_busy`.

## Verification and boundary

- Focused contract regression: `tests/Unit/WatchInterruptedTask.Tests.ps1`.
- Build: `build.ps1`.
- Generated and host projection: `skills.ps1 构建生效` followed by source/generated/projected hash checks.
- Existing heartbeat automations must be updated through the Desktop native automation API; automation TOML is read-only evidence, never a mutation surface.

Fresh receipts for this slice:

- Red phase: the new contract test failed 3/4 scenarios against the old skill.
- Green phase plus projection regression: 34/34 Pester tests passed.
- Natural-pause and stale-write tightening regression: focused contract 7/7 passed after the live semantic corrections.
- Fresh build and `skills.ps1 构建生效`: pass; 108 agent skills, 111 projection entries, zero conflicts.
- `verify-skills-config.ps1`: pass with zero findings and one legacy schema observation.
- `verify-skill-integrity.ps1`: 107 skills verified.
- Source, generated, and projected `watch-interrupted-task/SKILL.md` SHA-256: identical at `45E28A0543B88DA989A2B73F8E1025C13C66BD19DCF954E6E194C025463AD441`.
- Python `quick_validate.py`: `gate_na` because its optional isolated dependency is absent; no dependency was installed. The Pester contract and repository projection/integrity checks are the alternative verification. Recovery condition: run it when the repository-provided isolated validator environment is available.
- `verify-codex-skill-profiles.ps1`: no pass receipt because the caller timed out at 184 seconds. Its `finally` later restored both repository and projection manifest to `default`, verified after the verifier process exited. This long all-profile host probe is not claimed as passing and is not used as evidence for the skill-only behavior change.
- Desktop automation receipts after final rediscovery: two completed `skills-manager` heartbeats deleted; two currently running `qq-codex-bot` tasks armed/updated as `ACTIVE`, `FREQ=MINUTELY;INTERVAL=10`. Both durable prompts contain the eligibility-first gate, passive read-only peer arbitration, send/handoff/create/fork/rename ban, delegated-metadata untrusted-data rule, and direct-user-only authorization rule.
- Fleet visibility at the receipt time: 50-task Desktop listing limit, current local host only, with no unavailable hosts or sources reported. Native first-run scheduling control is absent, so exact staggering remains `platform_na`; sequential creation is the alternative behavior.
- Unique full closeout gate: pass in 212,050 ms; Unit 762/762, E2E 18/18, repository hygiene, generated sync, skill integrity, routing, dependency baseline, config, host capability, planning, and doctor JSON contracts all passed with `-AllowDirtyWorktree` for the pre-existing parallel changes.
- Cross-thread incident containment: both implicated `skills-manager` heartbeats were changed from `ACTIVE` to `PAUSED` through the Desktop automation API before permanent repair. Each implicated task received one user-authorized containment instruction to stop all cross-thread communication; no further coordination message is authorized.
- Silent-peer red probe against the previous committed skill: all three required clauses were absent. Focused green contract after repair: 10/10.
- Fresh `codex debug prompt-input` on CLI 0.145.0 returned parseable JSON and contained `Universal Agent Protocol v9.65`, the unconditional AI send ban, and the stale-turn non-hot-load boundary. This proves fresh-session loading without restarting the App; it does not retrofit the two business turns already in progress.
- Codex/Claude global A sections and C/D sections are byte-normalized equal; versions are v9.65, rule count is one per file, and both files remain below 130 lines / 16 KiB.
- Source, generated, and projected repaired skill SHA-256: `6097B01002A907171D5920CC53872A118FCA16AF154CB788391C1DB1F185DC1C`.
- Python `quick_validate.py` remains `gate_na`: optional `PyYAML` is absent and no dependency was installed. Focused Pester, repository full gate, projection/integrity, SHA equality, and fresh prompt loading are the alternative verification surfaces.
- The first isolated-worktree full gate was not accepted: it failed three unrelated cases because ignored projection reports and unmapped gitlink contents are not materialized in a new worktree. The populated root checkout was then used for the authoritative closeout.
- Final populated-root full gate after merge: PASS, build 182 ms, Unit 774/774, E2E 18/18, repository hygiene, generated sync, skill integrity (107), routing, dependency baseline, config, host capability, planning, and doctor JSON contracts all passed; total 183,410 ms. `skills.ps1 构建生效`: PASS, 108 agent skills, 111 projection entries, zero conflicts, `persisted=True`. Source/generated/Codex/Claude watch skill SHA-256: `8055F68CF2E6E79E43C5D3C23E4AD83B295DDCE4DEADC0FD45531700443F2F9B`.

Second-incident hard-guard closeout receipts:

- Focused `CrossThreadHook.Tests.ps1` plus `WatchInterruptedTask.Tests.ps1`: 16/16 passed. The hook simulation denies `send_message_to_thread`, `codex_app__send_message_to_thread`, and `codex_app.send_message_to_thread`; read-only list/read/wait calls remain allowed; malformed hook input fails closed with exit 2.
- User-level `~/.codex/hooks.json` parses as JSON and registers a `PreToolUse` matcher for the three known send-tool spellings. Both `command` and `commandWindows` call the reviewed repository hook script. This proves installed configuration and simulated protocol behavior, not that every specialized Desktop tool path necessarily traverses the default hook dispatcher.
- Fresh `codex debug prompt-input 'hook policy probe'` on CLI 0.145.0: exit 0, parseable JSON, v9.65 loaded, unconditional `send_message_to_thread` ban present, stale-turn non-hot-load boundary present.
- Unique populated-root full gate for the second incident: PASS in 198,511 ms; Unit 779/779 and E2E 18/18, with repository hygiene, generated sync, skill integrity, routing, dependency baseline, config, host capability, planning, and doctor JSON contracts passing.
- Post-gate `skills.ps1 构建生效`: PASS, 108 agent skills, 111 projection entries, zero conflicts, `persisted=True`. Source, generated, Codex canonical projection (`~/.agents/skills`), and Claude linked projection SHA-256 are identical at `81C148ED97719314FAE4E7E425000C8668DD8BA42EFFA392A49BF2E26C6F36FD`.
- Codex and Claude global A sections and C/D sections are normalized-equal. Both files load v9.65, contain the unconditional send ban and stale-turn boundary, and remain below 130 lines and 16 KiB. Repository `AGENTS.md` records global review 9.65.
- Both implicated heartbeats were updated through the native Desktop automation API and remain `PAUSED`. Their durable prompts contain `stale_policy_running`, the fresh Desktop hard-hook prerequisite, `soft_guard_only`, and the rule that source/hash/simulation/CLI evidence cannot substitute for live Desktop interception proof.
- Current truth boundary: repository repair, host hook installation, fresh CLI loading, projection equality, simulation, and full repository gates are verified. The two stale business turns do not hot-load this repair. Until they end or the user stops them and a fresh Desktop turn proves actual hook interception without delivering a peer message, live Desktop hard isolation is unaccepted and the heartbeats must remain paused.

Shared-checkout arbitration is cooperative and deterministic, not an atomic filesystem lock. It prevents normal heartbeat races when all participants follow the skill and host thread status is visible. Missing or conflicting peer state remains `unknown` and pauses rather than claiming race-free concurrent writes. External deployments, restarts, messages, paid calls, database mutations, and publication remain outside automatic retry without idempotency proof.

Rollback is limited to this override, metadata, regression test, and evidence file, followed by rebuilding and restoring the previous durable heartbeat prompts through the native automation API. Do not edit generated `agent/`, host projections, or automation TOML directly.
