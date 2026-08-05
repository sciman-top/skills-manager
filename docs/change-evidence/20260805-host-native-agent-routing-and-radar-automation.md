# Host-native agent routing and Radar automation

## Goal and boundary

This slice validates the host-owned part of the existing `agent_workflow_advisory_runtime` without introducing a repository scheduler, provider gateway, daemon, queue, database, or second agent runtime. The user owns goals, value/cost preferences, irreversible authorization, and vetoes. Codex owns semantic TaskGraph construction, dependency waves, native spawn/wait/steer/stop, per-agent model and reasoning effort, integration, and final verification. `skills-manager` remains a deterministic advisory and evidence layer.

The current user override is authoritative: `gpt-5.6-terra + high` is the balanced default. Radar may contribute auditable observations but cannot silently promote `Terra max` or mutate host configuration.

## Official basis and adoption decision

- Current Codex manual: `https://learn.chatgpt.com/docs/agent-configuration/subagents`. Local Codex can delegate when asked directly or when applicable `AGENTS.md` or skill instructions request it. The main thread owns orchestration, and explicit spawn model/effort overrides the `[agents]` default.
- Current Scheduled tasks manual: `https://learn.chatgpt.com/docs/automations`. Stable recurring workflows belong in a host Scheduled task; local mode is required when the durable output is an ignored file in the saved project.
- Current model guidance in the Codex manual: Sol is the demanding-agent default, Terra favors speed/efficiency for supporting work, and Luna favors clear, repeatable, high-volume work. Actual availability must still be checked on the current host/surface.
- Codex Radar is a user-selected community observation source. Its public JSON has a schema but no discovered formal API contract or reusable-data license. The automation is therefore low-frequency, read-only, fail-closed, and treats unknown fields as compatible input while rejecting missing critical fields.

Adopted: native host orchestration, one global conditional-delegation rule, explicit per-spawn model/effort, a Terra-high default for unspecified child agents, an expiring Radar snapshot, and one host Scheduled automation. Rejected: a repository model router/provider call, a second scheduler, automatic active-session switching, static total-score ranking, or Radar-driven configuration writes.

## Host changes and receipts

### Global rule and configuration

- `C:\Users\sciman\.codex\AGENTS.md` adds a Codex-platform rule for conditional native delegation only when at least two independently verifiable subtasks have disjoint exact write sets and parallelism materially improves quality or latency. Dependency/shared-seam/external-state overlap remains serial. FailurePacket, one corrected retry, re-slicing, and capacity-only escalation remain mandatory.
- `C:\Users\sciman\.codex\config.toml` now sets `agents.default_subagent_model = "gpt-5.6-terra"` and `agents.default_subagent_reasoning_effort = "high"`. Explicit spawn values continue to select Sol or another available profile for demanding work.
- Exact pre-change backups: `C:\Users\sciman\.codex\AGENTS.md.bak-20260805-agent-routing` and `C:\Users\sciman\.codex\config.toml.bak-20260805-agent-routing`. Source and backup hashes matched before edits.
- `codex debug models` parsed the configuration and listed Sol, Terra, and Luna with the expected efforts. A fresh `codex debug prompt-input` contained the new FailurePacket delegation rule, the PS7-first rule, and the project `AGENTS.md`. The already-running desktop task is not evidence of hot reload; a new task is the reliable app boundary. No Codex process was restarted.

### Native subagent observation

The current host ran three independent read-only workers and the primary thread independently checked their results:

| Work | Native model/effort | Observed result |
| --- | --- | --- |
| architecture and product-boundary review | `gpt-5.6-sol + xhigh` | completed |
| roadmap/admission and incomplete-work audit | `gpt-5.6-sol + medium` | completed |
| Radar schema/cost/latency and Terra comparison | `gpt-5.6-terra + high` | completed |

A `gpt-5.6-luna` collaboration-spawn attempt returned `Unknown model` even though `codex debug models` listed Luna. The exact boundary is `current collaboration spawn surface unavailable`; it is not evidence that all Codex surfaces or the account lack Luna.

### Radar manual snapshot and automation

The manually downloaded source was `https://codexradar.com/data/intelligence-efficiency.json`:

- source schema/type: `2 / distributed_intelligence_efficiency`
- source updated: `2026-08-05T20:18:30+08:00`
- 21 model-effort points, 74 history points, 743,986 exact bytes
- exact raw SHA-256: `707ac48848dc09bb66b59cefcb1f3ae7796fd9050d2a4093c98193494b27aec7`
- projected ignored snapshot: `reports/agent-workflow/radar/current.json`
- focused contract: `Test-RadarSnapshotContract` returned `pass=true`, zero findings

Relevant current observations:

| Profile | IQ | Average USD | Average minutes | Valid tasks |
| --- | ---: | ---: | ---: | ---: |
| Sol xhigh | 108.4821 | 6.426214 | 25.6550 | 112 |
| Sol medium | 89.7321 | 3.689068 | 17.1965 | 112 |
| Terra high | 83.0357 | 1.085159 | 12.9504 | 112 |
| Terra max | 89.7321 | 3.968141 | 31.6203 | 112 |
| Luna max | 95.0893 | 0.460029 | 31.1907 | 112 |

Terra max adds 6.6964 IQ over Terra high but costs about 3.66 times as much and takes about 2.44 times as long. This supports Terra high as the current balanced default while preserving Sol profiles for demanding or critical work and Luna as a host-availability-gated routine candidate.

Desktop Scheduled automation `codex-radar` is ACTIVE, runs daily at 21:00 in the local `skills-manager` project, and uses `gpt-5.6-terra + high`. It fetches only the fixed public JSON, validates schema/freshness/ranges, hashes exact bytes, maps all valid points, preserves the Terra-high user override, and atomically replaces only the ignored current snapshot. On HTTP/parse/schema/stale/contract failure it preserves the last valid snapshot and writes an ignored failure receipt. It cannot modify tracked files, `~/.codex`, active model/profile/config, provider/auth/sandbox/session, start subagents, install dependencies, commit, or push.

The first scheduled run completed at `2026-08-05T21:05:59+08:00`: snapshot id `codexradar-20260805T210559+0800-707ac488`, 21 valid entries, source age about 0.79 hours, the same exact raw SHA-256 as the manual run, validator pass with zero findings, one Terra-high user override, and zero tracked Git status entries under the output path.

## Repository policy correction

The repository soft-anchor contract is now four-tier and remains advisory:

```text
critical / ambiguous / high risk  -> Sol xhigh
demanding implementation/review   -> Sol medium
balanced cost/latency default     -> Terra high (user override)
clear repetitive routine work     -> Luna max (only when current spawn surface accepts it)
```

The evidence priority is `user override -> local comparable outcomes -> current host availability -> fresh Radar -> host default`. Capacity-only escalation is `Luna max -> Terra high -> Sol medium -> Sol xhigh`; task/context/tool/permission/credential/production-authorization failures are handled at their root and cannot be disguised as model-capacity failures. Two upgrades or a high-risk seam returns control to the supervisor.

## Verification

- `AgentWorkflowContracts.Tests.ps1`: 12 passed, 0 failed under PowerShell 7.6.3.
- `AgentWorkflowAdvisoryPlanning.Tests.ps1`: 7 passed, 0 failed under PowerShell 7.6.3.
- Root-cause regression: `LeanAiDeliveryPlanning.Tests.ps1` passed 25/25 after restoring the historical M0.3 status to repository planning truth and keeping host acceptance in the independent AWA receipt.
- Full repository gate: `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` exited 0 in about 208 seconds; unit 862/862, E2E 18/18, build/generated-sync, 107-skill integrity, routing, dependency/config, host capability, planning, PS7-only policy, four-tier agent advisory, and doctor JSON contracts all passed.
- Fresh snapshot contract: pass, zero findings.
- Host config parse/model catalog: pass for Sol, Terra, and Luna catalog entries.
- Fresh prompt-input load: new delegation rule, PS7 rule, and project rule all present.
- Automation receipt: `codex-radar`, ACTIVE, local project, Terra high, failed-runs-only notification; first scheduled run passed.

The first nested `pwsh -Command` verification wrapper also demonstrated why the project remains PS7-first but avoids fragile shell-string orchestration: the outer PowerShell expanded nested `$ErrorActionPreference` and `$_.FailedCount`. The tests themselves passed; the clean rerun invoked Pester directly in PowerShell 7.6.3 and removed the wrapper error.

## Truth boundary and remaining gates

- `repo_verified`: the deterministic four-tier proposal, user-override priority, bounded escalation, fixtures, tests, verifier, documents, and the shared-checkout full gate passed. This repository truth remains distinct from host/runtime acceptance.
- `host_evaluation_partial_pass`: three native model/effort profiles were observed; fresh CLI loaded the host rule/config; the manual Radar snapshot and first real scheduled run passed.
- Not proven: automatic delegation for every future project, Luna on the current collaboration spawn surface, future scheduled-run reliability, general quality/cost improvement, M1 sample benefit, TC2 production integration, P6 admission, external production authorization, or business `live_accepted`.
- M1 remains `collecting (0/10)`. This self-referential governance task is not a valid M1 sample.
- TC2 remains `not_started`; P6 remains `hold` because their independent admission conditions are not met.

The merged `codex/pwsh7-only` worktree remains an independent cleanup blocker. Eight nested partial clones contain only tracked deletions and match their parent gitlinks, but missing promisor blobs prevented three non-force restore strategies. No force removal was attempted; the worktree and branch remain intact for an architecture-level cleanup decision.

## Rollback

- Host rule/config: after a fresh hash review, restore only the two dated backups above. A new task is required to verify rollback load; do not restart the app automatically.
- Scheduled automation: delete automation id `codex-radar` through the Desktop automation API.
- Runtime data: remove only ignored `reports/agent-workflow/radar/current.json` and failure receipts.
- Repository change: revert only this four-tier/user-override slice after checking the active shared checkout and regenerating `skills.ps1`; do not touch unrelated override reorganization or other task changes.
