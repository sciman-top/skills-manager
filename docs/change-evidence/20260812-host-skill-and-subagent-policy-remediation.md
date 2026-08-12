# Host skill and subagent policy remediation

**date**: 2026-08-12

**scope**: resident skill reachability, projection metadata warning, retired advisory truth, host-local subagent defaults

**truth ceiling**: repository candidate verified; host config parsed; fresh-task selection/projection and exact-current full-gate status are recorded below only after their receipts exist

## Direct causes and changes

1. The representative Chinese code-review case required skill `code-review-and-quality`, but its generated package `agent-skills-2-skills-code-review-and-quality` was absent from `skill_projection.managed_link_includes`. The package is now included and a closeout regression requires both the package directory and its internal skill name to remain correct in the bounded USER-scope set.
2. The projection plan reported only pass/fail at 8,000 characters. It now emits a non-blocking warning at 90 percent, retains fail-closed behavior above the limit, persists the warning in the projection manifest, and has focused boundary tests.
3. The Agent workflow advisory source, CLI, tests, and gate are retired, but its historical manifest still said active `repo_verified`. The manifest now says `retired_historical_repo_verified / historical_repo_evidence_only`; the current planning verifier rejects regression to an active truth label.
4. The host-local default subagent pair was `gpt-5.6-luna / xhigh`, which did not match the repository's three-tier policy. After SHA-256-bound backup, it is `gpt-5.6-sol / medium`; `sol_medium_worker` uses `workspace-write`, `sol_low_worker` uses `read-only`, and the existing `sol_xhigh_supervisor` remains `gpt-5.6-sol / xhigh / read-only`. No provider, auth, MCP, parent sandbox, process, or session was changed.
5. Formal host projection previously required a clean commit but persisted `gate_receipt.status=not_provided` even after a full gate. The existing promotion context now consumes the authoritative `verify-current-quality-gate.ps1` result and requires full/passed/exact-current source binding; the explicit unverified override remains separately labeled.

Host backup: `C:\Users\sciman\.codex\backups\subagent-tier-policy-20260812-130932`.

## Evidence

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`: passed; generated `skills.ps1` refreshed from `src/`.
- Focused Pester (`SkillProjection`, `HostNativeSkillLifecycleCloseout`, `ProductPlanning`): 68 passed, 0 failed.
- `scripts/verify-vnext-planning.ps1 -Json`: 15/15 done, zero findings.
- `scripts/verify-skill-integrity.ps1 -Json`: 89 packages, zero errors/warnings.
- `scripts/verify-skill-routing.ps1 -Json`: compatibility-only, non-blocking, no provider call or native mutation.
- `scripts/verify-native-skill-metadata.ps1 -Json`: zero findings, no provider call or native mutation.
- Direct projection-plan probe: `estimated_metadata_chars=7294`, `effective_budget_limit_chars=8000`, `budget_warning_threshold_percent=90`, `budget_warning=true`, `budget_pass=true`, managed links 8, code-review package included.
- `codex doctor --json`: Codex CLI 0.146.1, overall `ok`, `config.toml parse=ok`, active model `gpt-5.6-sol`.
- Fresh `codex debug prompt-input` after controlled projection contains `code-review-and-quality`; the Junction is exact-target, and the projection snapshot records 8 enabled, 8 kept, 0 omitted.
- Representative fresh ephemeral selection report `reports/host-skill-selection-acceptance/20260812-133346-926/report.json`: 5/5 passed. The formerly failing `direct-code-review-zh` selected `code-review-and-quality`; two positive baseline cases still selected their exact skills, and two negative/native cases abstained.
- Official basis: [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [Codex skills](https://learn.chatgpt.com/docs/build-skills). The host owns orchestration/lifecycle; implicit skill routing depends on visible metadata and descriptions; model/effort defaults remain host configuration rather than repository runtime.

## Closeout and truth boundary

The exact-current full quality receipt, controlled host projection receipt, fresh `codex debug prompt-input` visibility, and selection evaluator result must be appended or cited before the corresponding claims are made. A parsed host config does not prove that this already-running Desktop task hot-loaded it. A visible skill does not prove full body injection/execution, and neither result proves business `live_accepted`. The completed-thread slot leak observed in the parent task is a host lifecycle limitation; this slice does not restart/kill Codex or restore the retired scheduler to mask it.

The first controlled projection attempt exposed that `managed_link_includes` consumes generated package directory names rather than internal skill names. Its aggregate transaction rejected `code-review-and-quality` and restored `agent/` plus build cache without projecting the host. The corrected entry is `agent-skills-2-skills-code-review-and-quality`, with a regression binding that directory to internal `name: code-review-and-quality`. A later diagnostic call incorrectly supplied an unsupported `-DryRun` switch directly to `Sync-CodexManagedSkillLinks`; PowerShell ignored the unbound switch and created only that exact Junction. Its reparse target was verified byte-for-path against the generated package and the Junction was immediately removed; the original seven links remained. No completion claim relies on either failed attempt.

Rollback is limited to the files in this slice plus the three host files restored from the named backup. Preserve unrelated host configuration, provider/auth/MCP state, external reference checkouts, reports, and user work.
