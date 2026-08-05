# watch-interrupted-task conditional recovery

## Goal

Restore meaningful automatic recovery after provider 408/429/502/503/504 and explicit host continuation gaps, and add Goal-aware supervision for acceptance, checkpoints, evidence, strategy drift, recoverable failures, and stopping.

## Authority and boundaries

- Direct user policy decision: monitor-only is insufficient; restore automatic autonomous continuation.
- Recovery stays inside the target task. Cross-task messaging remains prohibited.
- Goal creation/replacement requires explicit Goal-mode opt-in. An existing Goal objective is not silently rewritten.
- External effects require current receipt or idempotency proof before retry.
- The fleet supervisor may manage only trusted canonical heartbeat metadata; it never executes another task's business work.
- The user separately closed all live watch automations during implementation. This change does not recreate or activate one without a new lifecycle command.

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
- Host installer: `installed_untrusted`; installed/source script SHA-256 match, and target/fleet canonical prompt digests are pinned in the one discovered hook definition.
- Fresh app-server runtime doctor: one enabled hook; runtime/source shape and script/prompt digests match; `trust_status=modified`, `overall=soft_guard_only`. Current `hooks/list` does not echo `commandWindows`, so the doctor verifies normalized runtime fields from app-server and verifies `commandWindows == command` from the source `hooks.json`.
- Direct no-side-effect guard doctor: 13/13 simulations passed, including native/code-mode cross-task send denial, heartbeat self-mutation denial, sentinel automation denial, read-only allowance, and direct-user lifecycle allowance.
- Current host state: active Goal is absent and watch automation metadata matches 0. The prior direct user closure remains authoritative; no Goal or heartbeat was created.
- Live host-path acceptance remains open: the exact current non-managed hook definition requires review/trust through `/hooks`, followed by fresh-session live probes. Until then, specialized paths remain `guardrail_only` and automatic recovery is not claimed live-ready.

## Rollback

Revert only the watch override, four hook scripts, five focused test files, and this evidence file. Re-run `build.ps1` and the repository's supported agent projection command. Host installer rollback preserves prior hook bytes and `hooks.json` when a staged update fails; an already installed revision must be replaced through the same installer and re-reviewed in `/hooks`.
