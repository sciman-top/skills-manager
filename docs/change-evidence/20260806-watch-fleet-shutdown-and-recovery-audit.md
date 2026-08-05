# Watch fleet shutdown and recovery audit

## Goal and scope

This slice closes the repository-side findings from the watch-interrupted-task deep audit:

- keep revision-3 evidence-gated recovery and Goal supervision intact;
- allow the fleet supervisor to schedule shutdown only after every currently visible eligible local task has proved a stable stopped boundary;
- treat a task with a pending recovery boundary, including 408/429/502/503/504 and transport interruption, as not stopped;
- make shutdown qualification complete-set, fail-closed, durable, and idempotent;
- honor `Retry-After` and bounded evidence freshness in target recovery;
- harden CI tool acquisition and reference-repository provenance;
- remove a local-cache dependency from the skill-projection unit contract.

The write set is limited to the watch helper/prompt generators, their tests, the CI workflow and contract test, reference refresh and its safety test, the skill-projection test, and this evidence file. No Desktop automation, Goal, hook trust, host configuration, provider/auth/model/sandbox setting, or power state is changed.

## Implemented changes

### Fleet-wide stopped-state and shutdown proof

- `Get-WatchFleetShutdownDisposition.ps1` now requires complete visibility and count reconciliation across visible, eligible, monitored, conflicting, unknown, and blocking-unmonitored tasks.
- An empty task set, the 50-task host-list limit, incomplete visibility, an unmonitored eligible task, a conflict, `unknown`, or `soft_guard_only` fails closed.
- Goal presence does not create a second fleet stop rule. Each target AI remains responsible for proving its own stopped boundary against its Goal Contract; the fleet requires `task_stopped=true`, no active turn, no pending recovery or retry, fresh canonical evidence, and safe external-effect truth.
- The supervisor prompt uses no finite allowlist of ordinary stop causes. Any proved stopped reason is acceptable, while recovery-shaped states and transient-provider/transport boundaries override contradictory stopped fields and block shutdown.
- A state journal under an explicit trusted `StateRoot` atomically records tick identity, consecutive snapshot proof, observation time, and durable successful shutdown receipt keys. Repeated ticks, A-to-B-to-A replay, invalid legacy receipts, paths outside the root, and reparse paths are rejected.
- The only authorized power command in the generated contract is `shutdown.exe /s /t 120 /c "watch-interrupted-task: all eligible tasks stopped"`; `/f`, restart, immediate power-off, shell chaining, and blind replay are forbidden. This command was not executed during implementation or verification.

### Recovery timing and evidence

- `Get-WatchHeartbeatDisposition.ps1` accepts `NowUtc`, `NextRetryAtUtc`, and `EvidenceFreshnessMinutes`.
- A future retry boundary returns `observe_only/retry_not_due`; malformed retry time fails closed; recovery becomes eligible only after the boundary.
- Fresh evidence defaults to 15 minutes and is explicitly bounded to 1 through 1440 minutes. The target prompt requires these values and forbids early retry.

### Supply-chain and provenance hardening

- GitHub Actions checkout v7.0.1 is pinned to commit `3d3c42e5aac5ba805825da76410c181273ba90b1` and uses the official Node 24 action runtime. The job has a 20-minute timeout, and Pester 4.10.1 is downloaded from its exact package URL, verified against SHA-256 `898210e1a30c52cd46ba317c2278a9324345214213aa2f7d6b7dfa7b98f37ac9`, and imported from a runner-temporary module root. `-SkipPublisherCheck` is not used.
- Reference refresh now compares the actual normalized `origin` with the manifest `upstream_url` before fetch or pull. Mismatch records redacted provenance with `status=origin-mismatch` and performs no remote update.

### Hermetic test correction

- `SkillProjection.Tests.ps1` no longer requires ignored `imports/` working copies for three manual engineering skills. It verifies their stable `skills.json.imports` declarations and explicit routing-policy activation instead.
- The isolated red reproduction was `34 passed / 1 failed`; the corrected file passed `35 / 35`.
- The first hosted CI run exposed a second non-hermetic acceptance test: `Phase1Acceptance.Tests.ps1` required three host-specific `D:\...` repositories. The clean Windows runner failed `895 passed / 1 failed` even though E2E passed `18 / 18`. The test now exercises the same three-repository, zero-write, and performance contract against the repository's `simple`, `nested`, and `conflict` fixtures; the focused file passes `4 / 4` locally.

## Verification evidence

- Focused repository tests from the reviewed slices:
  - watch fleet supervisor: `16 passed / 0 failed`;
  - target recovery disposition: `14 passed / 0 failed`;
  - combined watch/cross-thread coverage: `62 passed / 0 failed`;
  - reference refresh safety: `2 passed / 0 failed`;
  - CI workflow contract: `1 passed / 0 failed`;
  - skill projection: `35 passed / 0 failed`.
- The isolated worktree initially lacked ignored runtime source and generated-agent caches. The failure sequence was diagnostic rather than waived:
  - the projection test exposed its dependency on manual import caches and was corrected at the contract source;
  - the required parent runtime sources were accepted only after clean Git status, exact `origin`, and exact `skills.lock.json` commit parity;
  - the parent generated `agent` snapshot first passed the repository integrity verifier at `107 skills`; copied files were hash-compared, and the branch watch directory was projected from this branch's override source;
  - all eight vendor caches passed origin/HEAD/clean preflight before routing verification.
- Standalone post-failure contracts passed in fixed order: skill integrity `107`, skill routing `findings=0`, dependency baseline, skills config enforce, host capability matrix, planning contract, PS7-only policy, Agent workflow advisory, and doctor JSON contract.
- Final closeout command:

  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full
  ```

  exited `0` after the hosted-CI hermeticity fix. The timing receipt records Pester `4.10.1`, `896` Unit plus `18` E2E cases (`914 / 914` passed), and `suite_elapsed_ms=239394`. The full runner also passed build, repository hygiene, generated sync, 107-skill integrity, reference governance `29/7/3`, the 32-case non-watch activation corpus, routing, dependency/config/host/planning/PS7/Agent/doctor contracts, with `total_elapsed_ms=244179`.

## Truth boundary and remaining live acceptance

- Repository implementation and local gates are complete for this slice.
- No real shutdown was scheduled, cancelled, or executed. The 120-second shutdown path therefore remains intentionally untested as an external effect.
- No watch automation was created, updated, paused, resumed, or deleted; no Goal was created, replaced, cleared, or completed.
- No live hook was installed or re-trusted. The host may remain `soft_guard_only`, and specialized tool paths are not claimed to be absolutely isolated.
- The first GitHub-hosted run, `31043635015`, proved the pinned Pester install step and then correctly failed the host-specific Phase1 test. A clean new-commit hosted workflow receipt remains required after the hermeticity fix and again after main integration.
- The isolated runtime caches are ignored verification inputs and are not part of the commit.

## Rollback

Revert only the commits/files in this slice, rebuild, and run the full gate again. Do not edit Desktop databases, automation metadata, Goal state, hook trust, provider/auth/model/sandbox configuration, or power state as part of rollback. Do not replay a shutdown command or any other external side effect without an authoritative current receipt.
