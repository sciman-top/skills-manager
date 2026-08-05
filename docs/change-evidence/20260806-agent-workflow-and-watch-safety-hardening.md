# Agent workflow and watch safety hardening

**date**: 2026-08-06
**slice**: completion truth, parallel admission, Radar v2, model proposal boundary, cross-thread/watch lifecycle safety
**rollback**: revert only the files listed below, rebuild `skills.ps1`, reinstall the prior reviewed host hook definition if applicable, then rerun the affected tests and full gate

## Problem and root cause

The earlier advisory contracts could accept claimed completed dependencies without verification receipts, compare write paths without canonical ancestor checks, mix serial and parallel groups in one wave, and allow high-risk/high-ambiguity work into ordinary parallel admission. Radar freshness described snapshot capture time but did not prove upstream data freshness, an empty local-outcome object could weaken fallback, and model proposals were easy to misread as an automatic selector. Corrected retries also lacked an explicit parallel re-admission boundary.

The watch guard had a separate trust-boundary defect: keyword-oriented lifecycle recognition could mistake negation/questions for authority; fleet cleanup could request delete without a direct user command; Goal satisfaction and terminal cleanup were collapsed; and free-form code-mode could hide a later cross-thread/automation mutation behind an earlier read-only call or alias. These are contract/root-boundary defects, not model-quality defects.

## Changes

- `src/Domain/AgentWorkflow.ps1`: Windows-safe canonical repo-relative write paths including ADS rejection; RadarSnapshot v2 with `source_updated_at`, non-empty entries, 36-hour upstream freshness and forbidden `policy_overrides`; bounded FailurePacket counts and correction evidence.
- `src/Application/ModelAndAgentPolicy.ps1`: one-to-one completed/receipt truth; selected/completed disjointness; high-risk/high-ambiguity rejection; one executable group per barrier wave; legal serial-only request; comparable local outcome requires valid evaluation time; `host_proposal_validation_only`; corrected retry requires parallel re-admission and repeated non-capacity failures reach supervisor takeover.
- `tests/Unit/AgentWorkflowContracts.Tests.ps1` and fixtures: adversarial coverage for the above contracts.
- `scripts/hooks/block-cross-thread-send.ps1`: unconditional handoff denial, target-bound direct lifecycle intent, and fail-closed code-mode high-risk/dynamic dispatch.
- `scripts/hooks/Install-CrossThreadGuard.ps1` and `scripts/hooks/Test-CrossThreadGuard.ps1`: independent rollback attempts, current generator digest comparison, canonical revision-3 simulation and `static_configuration_ready` reporting.
- watch disposition, skill/reference and focused tests: terminal Goal cleanup matrix, no-active-turn requirement and fleet-delete direct-user boundary.
- PRD/architecture/roadmap/spec/manifest/verifier: exactly three active soft tiers, RadarSnapshot v2, host proposal ownership and current host revalidation truth.

## Development verification receipts

The regression tests were added against the pre-fix code before the implementation change:

| Surface | RED | GREEN |
| --- | --- | --- |
| Agent workflow focused contract | 20 total; 9 passed; 11 failed | 20 passed; 0 failed |
| Post-audit receipt/path/time/retry adversarial pass | 20 total; 16 passed; 4 failed | 20 passed; 0 failed |
| Cross-thread/watch adversarial groups | 34 total; 27 passed; 7 failed | 34 passed; 0 failed |
| Five watch focused files | n/a aggregate | 49 passed; 0 failed |

These are development receipts, not the final closeout gate. The final section is updated only from a fresh build/verifier/full run after all tracked files stop changing.

## Host and live truth

- Two requested Sol xhigh subagent launches failed at startup with HTTP 429 and produced no files.
- A Luna max collaboration spawn returned `Unknown model gpt-5.6-luna`; the surfaced collaboration models were Sol and Terra. Terra was not used as an undeclared fourth tier.
- A separate real host probe passed with Codex CLI 0.146.0: `codex exec --ephemeral --sandbox read-only --model gpt-5.6-luna -c model_reasoning_effort=max` used `provider=codex_local_access`, returned `LUNA_MAX_HOST_PROBE_OK`, and exited 0. This proves the CLI/provider model pair, not subagent spawn or scheduled automation.
- Availability is therefore surface-specific: configured catalog, CLI provider, collaboration spawn, and scheduled runs require separate receipts.
- The historical Radar scheduled receipt was v1. The v2 host automation and its `automation_revision/executed_model/executed_effort/run_at/snapshot_id` receipt require revalidation.
- A manual v2 contract probe fetched 21 fresh observations, preserved upstream `source_updated_at`, hashed exact raw bytes, and passed the generated `agent-validate` bundle. It is labeled `manual_contract_probe_not_scheduled_receipt` and does not overwrite the historical scheduled `current.json`.
- Installing a changed non-managed hook does not establish execution trust. `/hooks` review of the exact hash in a fresh session and live deny/allow probes remain a separate user-visible acceptance step.

Official Codex guidance supports the ownership split used here: current local Codex can delegate after a direct request or applicable project/skill instruction; the host handles spawn/follow-up/wait/close; read-heavy independent work is the safer default for parallelism; higher reasoning increases time/token cost; Scheduled tasks should have early runs reviewed; and changed non-managed hooks are skipped until their exact definition is trusted.

## Closeout verification

Current stable-source receipts:

- Agent workflow and cross-thread/watch seven-file focused set: 84/84 pass; the nine source/helper hashes were identical before and after the 72-second run.
- The focused set includes 20 Agent workflow contracts, 8 planning-verifier tests, 6 installer/doctor tests, 23 hook tests, 10 fleet tests, 4 runtime-doctor tests and 13 watch lifecycle tests.
- `verify-agent-workflow-advisory.ps1 -Json`: pass, 5/5 tasks, 3 tiers, 0 findings, effect counters 0/0/0.
- `verify-powershell-runtime-policy.ps1`: `ps7_only`, 5/5, 0 findings.
- Hook install: `installed_untrusted`; source/host SHA-256 is `b078f45f6062768b339efc66807d5572df20cd4863c6ac95bca8d8a7548d1f94`; target/fleet/shutdown prompt digests match the current generators; static simulation passes; fresh runtime doctor remains `soft_guard_only` because `/hooks` trust and fresh live probes are open.
- Radar manual contract probe: 21 entries, v2 validator pass; scheduled Luna receipt remains pending.
- A concurrent integration full gate returned exit 0 with Unit 886/886 and E2E 18/18, but a peer-owned watch source changed while it was running. It is retained only as a diagnostic signal and is not the final closeout receipt.
- Final stable-snapshot full gate: exit 0; Unit 886/886, E2E 18/18, generated sync, 107-skill integrity, reference governance 29/7/3, override activation 32 cases, routing, dependency/config/host/planning/PS7/Agent/doctor contracts all passed; 67 dirty/untracked paths were hashed before and after and concurrent write drift was empty.
- Generated bundle probes: `agent-validate` and `agent-plan` both exited 0 with `pass=true`, `decision_owner=host_ai`, `executor=host_native_runtime`, and effect counters 0/0/0. The valid plan produced `discover` serial, `implement + document` isolated-parallel, and `integrate` serial waves.

The post-gate edit to this evidence file is `gate_na`: reason=`receipt-only documentation`; alternative verification=`git diff --check` plus exact staged-diff review; expires_at=`this closeout`; recovery_condition=`any executable, contract, fixture or generated file changes`, which requires rerunning the full gate.

Maximum claim: `repo_verified / repo_advisory_only`; host state remains `host_evaluation_partial`.

This slice does not prove universal automatic delegation, Luna availability on every spawn surface, model-policy business benefit, hook hard isolation, scheduled Radar reliability, provider authorization, production effects, or `live_accepted`.
