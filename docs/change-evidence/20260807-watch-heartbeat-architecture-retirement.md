# Legacy heartbeat architecture retirement

**Date**: 2026-08-07
**Truth label**: retirement `host_projected`; replacement remains `planning_contract`

## Decision

The prompt/heartbeat/fleet-supervisor architecture is retired. Native automation metadata was inspected before this slice and no automation containing the legacy watch marker remained. The skill is removed from `skill_projection.resident_names` and reduced to a fail-closed compatibility stub that can inspect or delete an exact residual legacy automation only after a direct cleanup request.

## Preserved forensic boundary

Pre-existing dirty changes in the legacy prompt/disposition scripts and their two historical test files are preserved. The retired skill prohibits invoking their generators. They remain unreachable forensic material until a separate clean deletion slice can review and remove the whole legacy subtree without destroying user work.

## Replacement

The new standalone planning contract is `D:\CODE\codex-watch-runtime`. It uses a deterministic local runtime, Cockpit readiness, durable state, typed Codex adapters, stable Retirement and separately armed fleet shutdown. No production runtime exists yet, so this slice does not claim task recovery, host projection, live acceptance or real shutdown.

## Safety evidence

- no ChatGPT, Codex or Cockpit process was restarted or stopped;
- no real power command was executed;
- unrelated automations were not changed;
- the old skill can no longer create, update, resume or arm a heartbeat through its documented interface.
- native automation file inspection found zero legacy markers;
- source, generated and projected retirement stubs share SHA-256 `22899C8D3ABFB51476422F4572710F8F63850740FCE4F1ADA285BECCB568BD90`;
- projected `resident_names` contains only `capability-router`;
- focused Pester result: 103 passed, 0 failed;
- full repository quality gate passed: build, complete unit/E2E tests, repo hygiene, generated sync, skill integrity, reference governance, override activation, routing, dependency baseline, config/host/planning contracts, PS7 policy, workflow advisory and doctor JSON; total gate time `454975ms`;
- projection used the repository's explicit `-AllowUnverifiedHostProjection` receipt path because the working tree contains this planning slice and preserved pre-existing watch changes; no process restart was performed.

## Rollback

Rollback only the resident-set, stub, metadata, README, focused test and this evidence file. Do not roll back or overwrite the pre-existing dirty legacy scripts/tests. Re-enabling the old runtime is not an accepted rollback; it requires a new architecture decision and live evidence.
