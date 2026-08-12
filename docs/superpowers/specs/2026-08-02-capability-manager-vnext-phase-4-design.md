# skills-manager vNext Phase 4: Unified Capability Selection and Activation Planning

**program_id**: `skills-manager-vnext`
**phase**: `P4`
**implementation_status**: `repo_verified`

## 1. Problem statement

Profile-independent skill cold loading fixed reachability but not selection precision. The same task vocabulary can describe a review-only draft, a design interview, an implementation, an MCP lookup or a host tool action. Positive keyword accumulation alone cannot distinguish these intents or safely activate external capabilities.

## 2. Goals

- Select the narrowest skill, MCP, plugin/app/connector or native tool from current metadata and runtime snapshots.
- Preserve one task and process; never switch profiles merely to reach a skill.
- Auto-use cold skills and already-available read-only capabilities.
- Return an activation or approval plan for unavailable, write-capable, destructive or authenticated capabilities.
- Measure direct, indirect, negative, ambiguous and cross-kind routing behavior.

## 3. Phase boundary

P4 owns capability selection and activation planning, not capability execution runtimes. Skill instructions may be read in the current task. MCP/plugin/app/native actions remain host-owned. OAuth, install, enablement, provider/model/session routing, restarts and destructive writes are never hidden behind seamless routing.

## 4. User-visible contract

Input is a complete task plus repository/runtime capability snapshots. Output schema v2 contains `intents`, `selected`, `excluded`, `activation_plan`, availability, side-effect class, confidence evidence and `writes_performed=false`.

## 5. Selection pipeline

1. Normalize metadata without flattening type-specific fields.
2. Detect coarse task intents such as implement, draft, grill, research and diagnose.
3. Apply explicit-name precedence.
4. Apply required and excluded intents before ranking.
5. Retrieve and rank bounded candidates from metadata.
6. Prefer active/available matches only as a tie-breaker.
7. Abstain on weak evidence.
8. Emit an activation plan instead of mutating host state.

## 6. Capability adapters

- Skill: active or cold-loadable path under a declared root; read-only workflow action is `use_active_skill` or `load_skill`; operator skill action is `load_skill_with_approval` and cannot be auto-allowed.
- MCP: active profile determines `available`; inactive server becomes `needs_activation` and action `request_mcp_activation`.
- Plugin/app/connector/native tool: consume caller-provided current snapshots; never infer installation or authorization.
- Hook/policy: deterministic enforcement input, not a semantic capability selected for ordinary tasks.

## 7. Safety policy

Read-only and external-read capabilities may be auto-used only when already available. Write, destructive, open-world, unknown or activation-required capabilities require an explicit host step. Selection never changes `active_profile`, MCP profile, plugin state or host config.

## 8. Compatibility

Keep `selected[].name/path`, `candidate_count`, `selection_mode`, `abstained` and `writes_performed` for existing consumers. Schema v2 adds `kind`, `availability`, `side_effect`, `excluded` and `activation_plan`. PowerShell 7 remains primary; generated script compatibility gates remain unchanged.

## 9. Evaluation

Golden cases cover direct, indirect, negative, ambiguous, cross-domain and cross-kind prompts. Required metrics are expected selection, forbidden selection, abstention accuracy, unnecessary activation rate and side-effect violations. Negative precision is a blocker before enforce mode.

## 10. Task design

- `SMV-P4-001`: establish P4 entry evidence and planning truth.
- `SMV-P4-002`: implement intent-aware unified selector schema v2.
- `SMV-P4-003`: implement MCP and runtime-snapshot activation adapters.
- `SMV-P4-004`: add golden routing corpus and deterministic verifier.
- `SMV-P4-005`: integrate the resident skill, profile contract and documentation.
- `SMV-P4-006`: run acceptance, fresh probes and closeout evidence.

## 11. Failure handling

Malformed paths or snapshots fail closed. Weak matches abstain. Missing runtime state becomes `unknown` or `needs_activation`; it is never treated as installed, authenticated or loaded. A verifier failure blocks phase completion but does not trigger host mutation.

## 12. Ordered verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -Command "Invoke-Pester tests/Unit/CapabilityRouter.Tests.ps1,tests/Unit/ProductPlanning.Tests.ps1,tests/Unit/Phase4EntryGate.Tests.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-capability-routing.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-phase4-entry-gate.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

## 13. Rollback

Revert only P4 source, policy, fixtures, tests and planning assets; restore the prior P4 deferred decision and P3 current-phase pointers; rebuild generated outputs. Do not roll back unrelated user or earlier capability-router changes.

## 14. Done definition

All six tasks are `done`; build, full tests, routing verifier, planning, entry, doctor and full quality gates pass; real negative prompts no longer select review-only/interview-only skills; MCP available/activation behavior is proven; profile/config/plugin state remains unchanged; highest affirmative state is `repo_verified` plus any separately recorded fresh-task probe, never implied `live_accepted`.
