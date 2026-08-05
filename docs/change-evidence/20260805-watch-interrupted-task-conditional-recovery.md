# watch-interrupted-task conditional recovery

## Goal

Restore meaningful automatic recovery after provider 408/429/502/503/504 and explicit host continuation gaps, and add Goal-aware supervision for acceptance, checkpoints, evidence, strategy drift, recoverable failures, and stopping.

## Authority and boundaries

- Direct user policy decision: monitor-only is insufficient; restore automatic autonomous continuation.
- Recovery stays inside the target task. Cross-task messaging remains prohibited.
- Goal creation/replacement requires explicit Goal-mode opt-in. An existing Goal objective is not silently rewritten.
- External effects require current receipt or idempotency proof before retry.
- The fleet supervisor may manage only trusted canonical heartbeat metadata; it never executes another task's business work.
- The live-acceptance heartbeat was created only after a direct lifecycle command and was deleted after its scheduled receipt. No matching target heartbeat remains after closeout.

## Design basis

- Current Codex manual: Goal mode persists an outcome and automatic continuation, remains under existing sandbox/approval boundaries, and should define outcome, constraints, and verification.
- Current Codex manual: a scheduled task inside an existing chat returns to that chat with existing context and can continue an ongoing review/triage loop.
- Current host truth: heartbeat input/output uses the XML envelope with `automation_id`, `current_time_iso`, `instructions`, `decision`, and `message`.

## Changes

- Policy revision 3 changes the authoritative mode to `conditional_recovery`.
- Added structured recovery disposition for checkpointed resume, root-cause replan, strategy reconciliation, acceptance verification, Goal completion, and three-turn blocked gating.
- Added Goal Contract semantics: Outcome, Scope, Acceptance, Checkpoints, Evidence, Stop conditions, and Recovery policy.
- Added deterministic receipt keys, retry boundaries, external-effect proof, and native heartbeat XML output.
- Changed both `-AsJson` generators to emit real JSON across process boundaries.
- Replaced self-hash authorization with installer-pinned target/fleet canonical body digests.
- Tightened heartbeat provenance, ordinary lifecycle authorization, code-mode dynamic-route denial, and read-only shell false-positive handling.
- Made the hook installer validate first, stage writes, and roll back partial host updates.
- Made the runtime doctor validate PreToolUse event, matcher, command handler, `commandWindows`, script hash, and prompt digests; it launches app-server through PS7/direct executable with one pending read task.

## Verification

- `build.ps1`: passed.
- Focused Pester for recovery, fleet, hook, installer, and runtime contracts: 46 passed / 0 failed.
- Skill quick validation: passed with `python -X utf8`; default Windows GBK mode cannot decode the UTF-8 skill file.
- Generated source/projection comparison: 7 files checked / 0 mismatches; fresh `codex debug prompt-input '查看守夜'` resolved the generated skill.
- Final full quality gate: passed with exit 0; unit 861 passed / 0 failed, E2E 18 passed / 0 failed; all build, hygiene, generated-sync, integrity, routing, dependency, config, host-capability, planning, PS7, advisory, and doctor contracts passed (`total_elapsed_ms=245299`).
- The exact installed hook definition was reviewed through `/hooks`. A fresh app-server runtime doctor on closeout reports one enabled hook, `trust_status=trusted`, `configuration_ready=true`, `shape_matches=true`, `definition_matches=true`, target prompt SHA-256 `0b84e54cdb271fac139cf49013fde3d9fa3b5a97897d9e0a08bef5f7227287f8`, and `overall=trusted_requires_live_probes`.
- The direct no-side-effect guard doctor passed all 13/13 simulations, including native/code-mode cross-task send denial, heartbeat self-mutation denial, sentinel automation denial, read-only allowance, and direct-user lifecycle allowance. These simulations prove the installed script behavior when invoked; they do not prove that every specialized Desktop path invokes it.

## Live host acceptance

- Target task: `019fd1f1-0242-7a83-96dd-ced34ccf541f`; canonical heartbeat identity: `watch-interrupted-task-v1-target-thread-id-019fd1f1-0242-7a83-96dd-ced34ccf541f`; canonical prompt digest: `0b84e54cdb271fac139cf49013fde3d9fa3b5a97897d9e0a08bef5f7227287f8`.
- The native lifecycle was exercised through create, view, `ACTIVE -> PAUSED -> ACTIVE`, and delete. The target, prompt, `FREQ=MINUTELY;INTERVAL=1` cadence, and `failed_runs_only` notification policy remained stable across pause/resume. The final native delete receipt at `2026-08-05T15:41:17.716Z` reports `deleteStatus=deleted` for the canonical identity.
- A first temporary create with the Chinese display name produced the generic host id `automation`. It was deleted before any scheduled run. Recreating with the canonical ASCII name produced the intended stable automation id; callers must therefore use the canonical identity, not rely on display-name slugging.
- One real scheduled heartbeat returned to the original task at `2026-08-05T15:39:09.655Z` as turn `019fd294-1b36-7de1-8bd7-0a1c33bf11c4`. Its assistant response used the required native XML envelope and carried `state=needs_input`, receipt key `watch-live-acceptance:019fd1f1-0242-7a83-96dd-ced34ccf541f:scheduled-tick-1:cleanup`, checkpoint `live-acceptance-scheduled-tick-1`, and `next_retry_at=none`. This accepts same-task scheduling, canonical prompt delivery, and the XML receipt/checkpoint contract.
- Fresh closeout reads report `watch_match_count=0`, `specific_automation_dir_exists=false`, and `Goal=null`. The unrelated `codex-radar` automation was left unchanged. No heartbeat, supervisor, or Goal was created during closeout.
- A real outer code-mode sentinel delete for `watch-interrupted-task-v1-live-probe-019fd1f1-0242-7a83-96dd-ced34ccf541f` reached the native automation implementation and returned `deleteStatus=not_found` instead of being denied by `PreToolUse`. The trusted non-managed hook is therefore defense in depth only on this host: `specialized_path_boundary=guardrail_only`; absolute cross-task or automation isolation is not live accepted.
- No deliberate provider 429/503 was generated, so transient-recovery behavior remains repository/state-machine verified without a real provider-failure receipt. This task had no active Goal, so Goal Contract continuation, drift correction, and completion are not live accepted here.

Closeout status:

```text
live_heartbeat_accepted
enforcement_guardrail_only
goal_live_not_run
real_provider_429_not_run
```

## Rollback

Revert only the watch override, four hook scripts, five focused test files, and this evidence file. Re-run `build.ps1` and the repository's supported agent projection command. Host installer rollback preserves prior hook bytes and `hooks.json` when a staged update fails; an already installed revision must be replaced through the same installer and re-reviewed in `/hooks`.
