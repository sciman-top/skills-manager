# Watch cadence: 12-minute recovery interval

## Decision

The user changed the active watch monitoring cadence from 10 minutes to 12 minutes. This applies atomically to target heartbeats, the fleet supervisor, shutdown-managed target self-pause updates, guard admission, and native automation metadata.

Transient 408/429/502/503/504 and transport interruptions still honor `Retry-After`. Without a later retry boundary, the next recurring heartbeat provides the bounded recovery opportunity; the implementation does not spin or block-sleep.

## Safety boundary

- Historical evidence that records an earlier 10-minute runtime remains unchanged.
- Canonical prompts, guard policy, simulations, and unit tests must agree on `FREQ=MINUTELY;INTERVAL=12` before host projection.
- Host automation updates remain blocked until the final committed runtime generation, exact hook definition trust, fresh live-path probes, and native receipts all agree.
- Notification policy remains `failed_runs_only`; shutdown authorization and stable-stop criteria are unchanged.

## Verification

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`: exit 0.
- Affected Pester set covering hook install/deny, target self-pause, fleet prompt, runtime doctor, target disposition, and arming: 95 passed, 0 failed.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`: exit 0 in 476.3 seconds; build, full tests, generated synchronization, contracts/invariants, and hotspot stages completed.
- Post-full evidence-only edit: `gate_na`; reason=`receipt documentation only`; alternative_verification=`fresh build plus git diff --check and exact diff review`; evidence_link=`this file`; expires_at=`this closeout`; recovery_condition=`any executable, fixture, contract, or generated-file change requires the full gate again`.
- Git closeout and fresh host projection receipts remain pending until the final committed generation is installed and trusted.
