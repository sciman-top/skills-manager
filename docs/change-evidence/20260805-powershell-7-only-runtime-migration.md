# Change Evidence — PowerShell 7-only Runtime Migration

## Result

- Track: `powershell7_runtime_migration`
- Runtime policy: `ps7_only`
- Minimum: PowerShell `7.0`
- Recommended baseline at review time: PowerShell `7.6 LTS`
- Windows PowerShell 5.1: project-unsupported; historical facts preserved
- Typed-core TC2 / production integration: `not_started`
- P6: `hold`
- Live/downstream acceptance: `not_run`

## Basis and disposition

- Repo truth before migration: PowerShell 7 already owned build, test and full gate; 5.1 remained only as installer/launcher fallback and bounded smoke.
- User outcome: reduce ChatGPT/AI-generated Windows script parser, quoting, encoding and runtime variance across this repo and future projects.
- Official basis: Microsoft PowerShell lifecycle, 5.1-to-7 migration guidance and Windows PowerShell support-channel documentation.
- Decision: `pwsh`/PS7 `adopt`; Windows PowerShell fallback/smoke `retire`; extra shim/module/package `reject`; typed-core TC2 `defer/not_started`.
- Host-global boundary: `~/.codex/AGENTS.md` and `~/.claude/CLAUDE.md` were hash-backed-up before adding the shared PS7 default rule. No `config.toml`, provider, auth, sandbox, profile, session or process was changed; current task is not fresh-load proof.

## Implementation evidence

- Source/build/install/generated entry require PowerShell 7.0+.
- `src/Core.ps1`, `install.ps1`, `skills.cmd` and MCP environment wrapper contain no legacy resolver; missing `pwsh` fails closed.
- GitHub/Azure/GitLab pipelines use `pwsh` only; bounded 5.1 smoke was removed.
- affected subprocess tests now execute through PowerShell 7 and retain their original behavioral assertions.
- current PRD/architecture/roadmap/Lean/plan/todo/runbook/release truth says `ps7_only`; historical Phase manifests still record the compatibility evidence that was true at their completion time.
- custom PowerShell automation guidance defaults to PS7 and permits 5.1 only as an explicit, isolated external legacy constraint.

## Verification contract

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
- focused runtime/compatibility/build/core/package/subprocess/Lean tests: 268 passed, 0 failed after the single assertion-root-cause correction
- `scripts/verify-powershell-runtime-policy.ps1 -Json`
- `scripts/verify-lean-ai-delivery-planning.ps1 -Json`
- `scripts/verify-typed-core-pilot-planning.ps1 -Json`
- unique closeout: `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`
- `git diff --check`, Git status and branch/remote parity

The three focused contract verifiers returned pass with zero findings: PS7 migration 5/5, Lean maintenance 11/11 with `powershell_compatibility_status=ps7_only`, and typed-core 3/3 with TC2 `not_started`. The unique full-gate process output and Git history are the final run receipts; they are intentionally not duplicated as mutable counters in this tracked file. This evidence is valid only when that final write set exits 0 and is committed without further code/contract changes.

## Rollback

Revert only the PS7 migration commit, rebuild `skills.ps1`, and rerun focused/full gates. Restore host-global instruction backups if the global default must be withdrawn, then validate in a fresh task. Do not re-enable `powershell.exe` via a hidden environment flag or wrapper, do not rewrite historical Phase evidence, and do not touch unrelated main-worktree/runtime-truth changes.

## Truth boundary

`repo_verified` means this repository's final source/generated/CI/test/docs/verifier write set passed. It does not prove every scheduled task, shortcut, downstream repository or hosted ChatGPT environment has migrated; it does not claim TC2, P6, host fresh-load or `live_accepted`.
