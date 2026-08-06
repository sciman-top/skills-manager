# Agent workflow and watch safety hardening

**date**: 2026-08-06
**slice**: clean-CI/adversarial hardening, transaction and archive safety, completion truth, parallel admission, Radar v2, model proposal boundary, cross-thread/watch lifecycle safety
**rollback**: revert only the files listed below, rebuild `skills.ps1`, reinstall the prior reviewed host hook definition if applicable, then rerun the affected tests and full gate

## Problem and root cause

The audit found a recurring class of defects hidden by ordinary happy-path tests: tests depended on host-only absolute paths or ignored imports; zero-discovery stages and stale performance samples could pass; config and generated output lacked fail-closed version/idempotence checks; repository, archive, path and transaction boundaries were validated lexically or before locks but not against clean runners, reparse traversal, canonical collisions, mutable upstream state, concurrent writers or rollback failure. The shared root cause was incomplete provenance and time-of-check/time-of-use modelling at trust boundaries.

The earlier advisory contracts also accepted claimed completed dependencies without verification receipts, compared write paths without canonical ancestor checks, mixed serial and parallel groups in one wave, and allowed high-risk/high-ambiguity work into ordinary parallel admission. Radar freshness described snapshot capture time but did not prove upstream data freshness, an empty local-outcome object could weaken fallback, and model proposals were easy to misread as an automatic selector. Corrected retries lacked an explicit parallel re-admission boundary. A later live probe exposed another boundary defect: `codex debug models` and the user API/CLI provider could see Luna while `collaboration_spawn` rejected it, but an empty `host_available_pairs` list could still be treated as merely absent evidence and fresh Radar/local outcomes could leave Luna selected. The root cause was missing surface identity and a missing `unknown` availability state.

The watch guard had a separate trust-boundary defect: keyword-oriented lifecycle recognition could mistake negation/questions for authority; fleet cleanup could request delete without a direct user command; Goal satisfaction and terminal cleanup were collapsed; and free-form code-mode could hide a later cross-thread/automation mutation behind an earlier read-only call or alias. These are contract/root-boundary defects, not model-quality defects.

## Changes

- clean CI and test gates: remove host absolute-path and ignored-import dependencies; make Unit/E2E zero discovery fail closed; pin Pester 4.10.1 in Azure/GitLab and route both to the authoritative full gate; consume only an explicit current-run `sync_mcp` performance sample and otherwise emit the complete `gate_na` contract.
- PS7/config/generated invariants: dynamically scan active PowerShell for Windows PowerShell 5.1 entry points; add root `skills.json.schema_version=1` with fail-closed root validation while retaining legacy external-fixture observation; run the generator twice and compare SHA-256 so nondeterministic output fails even with a dirty-worktree allowance.
- reference and routing truth: validate manifest upstream against clone origin before any fetch/pull, including normalized local/file/GitHub HTTPS/SCP forms; source skill truth from tracked portable inventory and MCP truth from `skills.json.mcp_servers`; require case-local runtime declarations for plugin/app/connector/native capabilities instead of letting the corpus synthesize its own proof.
- Git/archive integrity: bind stale-lock recovery to the exact Git admin `index.lock`, refuse lock deletion around active Git processes, use `pull --ff-only`, and fail closed on divergence/unrelated history rather than silently resetting. ZIP/GitHub snapshots now enforce immutable ref and blob hashes plus count, size, ratio, depth, traversal, ADS, symlink, reserved-name, trailing-dot/space, Unicode/case collision and post-extraction reparse limits before atomic cache replacement.
- MCP and logging: reject literal credentials in env/header/template/URL/query/stdio arguments; protect managed targets with root locks, post-lock CAS, reparse/containment checks, atomic writes and drift-safe rollback; preserve fail-honest native-side-effect boundaries. The common log sink recursively redacts URL userinfo, credential query parameters, Authorization/Bearer forms and whitespace-separated tokens while preserving `${ENV_VAR}` and `*_env_var` references.
- Rule Estate and audit transactions: require review-bound expiring authorization receipts and exact review-to-plan projections; re-run complete preflight after locking; bind backups by hash/length and verify rollback integrity. Audit apply requires preflight, dry-run and input-stability receipts, restores `skills.json` and independently compensates skill/MCP projections on failure. Rule Estate rejects every control output whose existing ancestor is a junction/reparse point, whose physical path escapes the workspace, or which overlaps a registry/review/authorization/desired/plan/target-rule input before any mutation.
- `src/Domain/AgentWorkflow.ps1`: Windows-safe canonical repo-relative write paths including ADS rejection; RadarSnapshot v2 with `source_updated_at`, non-empty entries, 36-hour upstream freshness and forbidden `policy_overrides`; bounded FailurePacket counts and correction evidence.
- `src/Application/ModelAndAgentPolicy.ps1`: one-to-one structured completion receipts with dependency closure; selected/completed disjointness; high-risk/high-ambiguity rejection; one executable group per barrier wave; legal serial-only request; comparable local outcome requires valid evaluation time; `host_proposal_validation_only`; surface-scoped `confirmed_available/confirmed_unavailable/unknown` availability with unknown fail-closed; corrected retry requires parallel re-admission and repeated non-capacity failures reach supervisor takeover.
- `tests/Unit/AgentWorkflowContracts.Tests.ps1` and fixtures: adversarial coverage for the above contracts.
- `scripts/hooks/block-cross-thread-send.ps1`: unconditional handoff denial, target-bound direct lifecycle intent, and fail-closed code-mode high-risk/dynamic dispatch.
- `scripts/hooks/Install-CrossThreadGuard.ps1` and `scripts/hooks/Test-CrossThreadGuard.ps1`: independent rollback attempts, current generator digest comparison, canonical revision-3 simulation and `static_configuration_ready` reporting.
- watch disposition, skill/reference and focused tests: use internal UTC; bind fleet decisions to supervisor automation, two distinct ordered scheduled ticks, target automation/turn/evidence/external-effect/no-active-turn provenance and structured hash-based checkpoint/receipt IDs; issue short-lived shutdown authorization while retaining stable dedupe receipts; preserve terminal Goal cleanup, final verification and direct-user delete boundaries.
- PRD/architecture/roadmap/spec/manifest/verifiers/README: exactly three active soft tiers, structured completion receipts, planning-only static output, Radar allowlist/freshness, host proposal ownership, output containment, current host revalidation truth and explicit `repo_advisory_only` scope.

## Development verification receipts

The regression tests were added against the pre-fix code before the implementation change:

| Surface | RED | GREEN |
| --- | --- | --- |
| Agent workflow focused contract | 20 total; 9 passed; 11 failed | 20 passed; 0 failed |
| Post-audit receipt/path/time/retry adversarial pass | 20 total; 16 passed; 4 failed | 20 passed; 0 failed |
| Cross-thread/watch adversarial groups | 34 total; 27 passed; 7 failed | 34 passed; 0 failed |
| Five watch focused files | n/a aggregate | 49 passed; 0 failed |
| Rule Estate mutation | targeted adversarial cases failed before implementation | 12 passed; 0 failed |
| Audit apply/rollback | targeted transaction cases failed before implementation | 92 passed; 0 failed, followed by a direct compensation probe for the final source increment |
| Rule Estate control-output overlap | 20 passed; 2 failed | 22 passed; 0 failed |

Before the final control-output overlap increment, the affected suites were split into bounded groups because one aggregate test process exceeded the tool timeout without reporting a test failure. All groups completed with zero failures; the two newly added overlap cases are recorded separately above and require the pending full gate for the new aggregate count:

| Focused group | Result |
| --- | --- |
| clean CI/config/reference/routing/Agent/Phase1/SkillProjection | 132/132 |
| Core/MCP/Git/log | 223/223 |
| Rule Estate/mutation/audit | 113/113 |
| target/fleet watch | 31/31 |
| cross-thread guard install | 7/7 |
| cross-thread hook | 24/24 |
| **Total** | **530/530** |

These are development receipts, not the final closeout gate. The final section is updated only from a fresh build/verifier/full run after all tracked files stop changing.

## Host and live truth

- Two requested Sol xhigh subagent launches failed at startup with HTTP 429 and produced no files.
- A Luna max collaboration spawn returned `Unknown model gpt-5.6-luna`; the surfaced collaboration models were Sol and Terra. Terra was not used as an undeclared fourth tier.
- A separate real host probe passed with Codex CLI 0.146.0: `codex exec --ephemeral --sandbox read-only --model gpt-5.6-luna -c model_reasoning_effort=max` used `provider=codex_local_access`, returned `LUNA_MAX_HOST_PROBE_OK`, and exited 0. This proves the CLI/provider model pair, not subagent spawn or scheduled automation.
- Availability is therefore surface-specific: configured catalog, CLI provider, collaboration spawn, and scheduled runs require separate receipts.
- A fresh 2026-08-06 reproduction confirmed the current metadata/runtime drift: the callable tool schema advertised Luna, but the spawn service returned `Unknown model gpt-5.6-luna. Available models: gpt-5.6-sol, gpt-5.6-terra`. The manifest now records this as `collaboration_spawn=confirmed_unavailable`; this does not negate the separate CLI/provider pass.
- The historical Radar scheduled receipt was v1. The v2 host automation and its `automation_revision/executed_model/executed_effort/run_at/snapshot_id` receipt require revalidation.
- A manual v2 contract probe fetched 21 fresh observations, preserved upstream `source_updated_at`, hashed exact raw bytes, and passed the generated `agent-validate` bundle. It is labeled `manual_contract_probe_not_scheduled_receipt` and does not overwrite the historical scheduled `current.json`.
- Installing a changed non-managed hook does not establish execution trust. `/hooks` review of the exact hash in a fresh session and live deny/allow probes remain a separate user-visible acceptance step.

Official Codex guidance supports the ownership split used here: current local Codex can delegate after a direct request or applicable project/skill instruction; the host handles spawn/follow-up/wait/close; read-heavy independent work is the safer default for parallelism; higher reasoning increases time/token cost; Scheduled tasks should have early runs reviewed; and changed non-managed hooks are skipped until their exact definition is trusted.

## Closeout verification

All full-gate receipts produced before the complete clean-CI, archive/MCP, Rule Estate/audit, routing and watch repair set stabilized are historical diagnostics only. They do not prove the current closeout. Current incremental evidence includes RED `16 passed / 6 failed` before the surface-availability implementation, then GREEN `22 passed / 0 failed` for `AgentWorkflowContracts.Tests.ps1`, plus the focused groups above. The stable executable snapshot was subsequently verified by the single authoritative repository full gate recorded below.

Current stable-source receipts:

- Agent workflow focused suite: 24/24 pass after the structured receipt/planning/Radar/path hardening.
- Combined affected suites: 530/530 pass as itemized above.
- `verify-agent-workflow-advisory.ps1 -Json`: pass, 5/5 tasks, 3 tiers, 0 findings, effect counters 0/0/0.
- `verify-powershell-runtime-policy.ps1`: `ps7_only`, 5/5, 0 findings.
- `verify-capability-routing.ps1`: 30/30 cases, 0 findings; `verify-skills-config.ps1 -Mode enforce`: schema version 1, pass, 0 findings; generated sync: consecutive builds deterministic and source/bundle synchronized.
- Hook install: `installed_untrusted`; source/host SHA-256 is `b078f45f6062768b339efc66807d5572df20cd4863c6ac95bca8d8a7548d1f94`; target/fleet/shutdown prompt digests match the current generators; static simulation passes; fresh runtime doctor remains `soft_guard_only` because `/hooks` trust and fresh live probes are open.
- Radar manual contract probe: 21 entries, v2 validator pass; scheduled Luna receipt remains pending.
- An earlier concurrent integration full gate returned exit 0 with Unit 886/886 and E2E 18/18, but later executable/test changes and a peer-owned watch source change invalidate it for current closeout. It is retained only as a diagnostic signal.
- Generated bundle probes after the final source build: `agent-validate` and `agent-plan` both exited 0 with `pass=true`, `decision_owner=host_ai`, `executor=host_native_runtime`, and effect counters 0/0/0. The valid plan produced `discover` serial, `implement + document` isolated-parallel, and `integrate` serial waves.
- First authoritative full-gate diagnostic: exit 1 after Unit 943/949 and E2E 12/18. Its 12 failures identified stale MCP secret fixtures, missing audit workflow/Rule Estate authorization receipts in E2E, and a clean-workspace MCP root-creation regression. After correcting those exact causes, the affected Core/MCP planning/Skill Audit/Workflow set passed 234/234. This failed run is diagnostic only; it is not a closeout receipt.
- Pre-push authoritative full gate on commit candidate `769a903d`: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` exited 0 in `434767ms`. Pester 4.10.1 passed Unit 951/951 across 76 files and E2E 18/18 across 2 files; the test suite elapsed `424626ms`. This receipt was locally valid but was superseded by the clean-runner defect and follow-up executable change below.
- The same full run passed repository hygiene; two-build generated idempotence/source synchronization; skill integrity for 107 skills; reference governance for 29 repositories, 7 defaults and 3 patches; override corpus for 8 targets and 32 cases; routing with 0 findings; dependency baseline; schema-v1 skills config with 0 findings; host capability matrix 5 hosts/7 evidence; planning 5/5; PS7-only runtime 5/5 with 0 findings; three-tier agent advisory 5/5 with effect counters 0/0/0; and doctor JSON contract.
- GitHub Actions push run [`31053510510`](https://github.com/sciman-top/skills-manager/actions/runs/31053510510) reproduced the remaining clean-runner defect after Unit and E2E passed: `skill-integrity` rejected seven dependency-contract callers because locally materialized ignored/gitlink packages were absent. The verifier had treated only generated `agent/` frontmatter as existence truth even though `skills.json` is the tracked source declaration surface.
- The focused clean-inventory regression was RED 11/12 before source-declaration support, then GREEN 12/12. A second adversarial test proved profile/catalog references must not self-prove existence: it was RED 12/13 against the overly broad draft and GREEN 13/13 after the inventory was narrowed to materialized frontmatter plus `imports.skill` and `mappings.from` leaves. A direct current-tree integrity run passed 107 skills; a clean unmaterialized fixture passed all seven dependency entries with zero errors; a source absent from both materialized and tracked inventories still fails closed.
- First post-CI-fix authoritative full gate: the same full command exited 0 in `446200ms`. Pester 4.10.1 passed Unit 953/953 across 76 files and E2E 18/18 across 2 files; the test suite elapsed `435755ms`. Repository hygiene, generated sync, skill integrity 107, all contract/invariant checks and hotspot reporting passed.
- GitHub Actions push run [`31054968516`](https://github.com/sciman-top/skills-manager/actions/runs/31054968516) proved the integrity repair in a clean checkout (`skill integrity verified: 0 skills`) and then exposed the adjacent routing defect: `skill routing member is not installed: development-flow/brainstorming`. The routing verifier read missing mapping frontmatter as the deployment placeholder `superpowers-skills-brainstorming`, while the tracked policy correctly named the source skill `brainstorming`.
- The routing fix separates materialized metadata/activation from tracked source declarations. Existence accepts only materialized frontmatter names plus `skills.json imports.skill` and `mappings.from` path leaves; a missing-file deployment placeholder is excluded, and policy/profile/catalog consumers cannot self-prove existence. Declared-only members remain inactive and are not scanned for metadata triggers.
- The three routing adversarial regressions were RED at 10/13 and GREEN at 13/13. The combined routing/projection/integrity focused set passed 61/61; the real routing verifier passed 8 groups with 0 findings.
- Pre-rebase post-routing full diagnostic: the same full command exited 0 in `501158ms` with Unit 956/956 and E2E 18/18, but `origin/main` had advanced during the run, so this receipt does not close the integrated snapshot.
- After rebasing the unpushed routing fix onto `2188f45f`, the merged host-capability and clean-unmaterialized focused set passed 64/64. The final integrated authoritative full gate exited 0 in `537945ms`: Pester 4.10.1 passed Unit 968/968 across 78 files and E2E 18/18 across 2 files; the test suite receipt elapsed `523027ms`. Repository hygiene, two-build generated synchronization, skill integrity 107, routing with 0 findings, every remaining contract/invariant and hotspot reporting passed.
- GitHub Actions clean-runner run [`31071967990`](https://github.com/sciman-top/skills-manager/actions/runs/31071967990) on executable snapshot `e3f9d0f2` completed `success`. Locked source reconstruction, the authoritative full gate and the follow-up MCP observation all passed: Unit 968/968, E2E 18/18, test suite `393489ms`, full gate `403253ms`, skill integrity 107 and routing with 0 findings. The missing current-run MCP performance sample emitted the complete non-bypass `gate_na` receipt and did not claim a measured threshold result.

Executable snapshot `e3f9d0f2` is locally and remotely `repo_verified / repo_advisory_only`. Exact diff, AST, staged secret review, push parity and remote clean-CI re-observation completed without an open repository-side repair item from this audit slice.

The post-gate edit to this evidence file is `gate_na`: reason=`receipt-only documentation after executable SHA acceptance`; alternative verification=`git diff --check` plus exact staged-diff review and the follow-up docs-only CI run; evidence_link=`31071967990`; expires_at=`this closeout`; recovery_condition=`any executable, contract, fixture or generated file changes`, which requires rerunning the full gate.

Maximum claim: `repo_verified / repo_advisory_only`; host state remains `host_evaluation_partial`.

This slice does not prove universal automatic delegation, Luna availability on every spawn surface, model-policy business benefit, hook hard isolation, scheduled Radar reliability, provider authorization, production effects, or `live_accepted`.
