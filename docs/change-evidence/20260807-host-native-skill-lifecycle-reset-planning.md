# Host-Native Skill Lifecycle Reset Planning Evidence

**date**: `2026-08-07`
**truth_level**: `planning_contract`
**runtime_migration**: `not_started`
**host_loaded**: `not_run`
**live_accepted**: `not_run`
**full_gate**: `not_passed`

## Problem and admission basis

Repeated user requests showed that repository completeness did not imply host invocation: formerly unrouted skills, profile-excluded skills and `grill-with-docs` could exist in catalog/projection while the host did not automatically trigger discovery. P5-local router/profile/cold-load corrections improved deterministic reachability and bounded replay but could not force the host pre-turn decision or prove full skill-body injection.

The user explicitly authorized a full architecture reset. P6 admission therefore replaces the primary runtime target instead of adding another P5-local patch.

## Adopted architecture

```text
effective HostCapabilitySnapshot
  -> complete CanonicalSkillInventory
  -> deterministic SkillEligibilityPolicy
  -> token-aware all-enabled NativeDiscoverySet
  -> host AI semantic selection
  -> native full skill injection
  -> NativeInvocationTrace
```

Explicit strict/fallback requests may use bounded pre-turn candidates and supported App Server skill injection. This is not the default path.

## Official-source review

The fresh Codex manual confirms the architecture inputs used here:

- Skills use progressive disclosure: the host starts with name/description (and Codex path), then loads full `SKILL.md` only after selection.
- The initial Codex skill list is bounded to 2% of the model context window, or 8,000 characters when the context window is unknown; descriptions are shortened before skills may be omitted.
- Implicit invocation is host matching against the skill description, so concise scope/boundaries are the supported optimization surface.
- App Server exposes effective `config/read`, `model/list`, `modelProvider/capabilities/read`, `skills/list`, `skills/changed`, and explicit `turn/start` skill input items.

The current local configuration sample was re-read as `model_context_window=272000`, which implies a nominal 5,440-token 2% ceiling for that input. P6 still resolves effective turn/thread/surface truth before using it.

## Planning deliverables

- P6 spec and domain model;
- product PRD, architecture ADRs, roadmap admission and index update;
- 12-task machine-readable manifest with dependencies, exact write sets, tests, commands, rollback and stop boundaries;
- file-level implementation plan with TDD loop and execution waves;
- generic and P6-specific planning verifiers plus negative Pester cases;
- current plan/todo/AGENTS truth update.

## Existing worktree boundary

This planning slice did not revert or absorb concurrent watch-runtime changes in `README.md`, `skills.json`, reference shelf files, watch skill files or watch tests. The P6 manifest may name those shared paths for future tasks; no pending task is implemented by this planning change.

## Verification

Fresh focused evidence:

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success`.
- `Invoke-Pester` for `HostNativeSkillLifecyclePlanning.Tests.ps1`, `ProductPlanning.Tests.ps1` and `QualityGateScripts.Tests.ps1` → 43/43 passed, 0 failed.
- `scripts/verify-host-native-skill-lifecycle-planning.ps1 -Json` → pass, 12 tasks, 0 findings.
- `scripts/verify-vnext-planning.ps1 -Json` → pass, P6, 12 open tasks, 0 findings.
- Phase 6 manifest JSON parse → `current_phase=P6`, `task_count=12`.

The full quality gate was started but explicitly stopped at the user's request to avoid repeatedly running the expensive full suite. It is not counted as passed and remains reserved for the actual P6 closeout task. Passing focused planning verifiers proves internal consistency only; it does not prove native projection completeness, host selection, full `SKILL.md` invocation, profile/router retirement or business behavior.

## SMV-P6-001 execution receipt

**task_status**: `repo_verified`
**scope**: planning truth boundary only; no runtime, host, provider or generated-output write

- RED: the focused fixture promoted `host_loaded` from `not_run` to `repo_verified`; before the verifier change, `HostNativeSkillLifecyclePlanning.Tests.ps1` reported 5 passed and 1 failed because no planning-boundary finding was emitted.
- GREEN: `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'tests/Unit/HostNativeSkillLifecyclePlanning.Tests.ps1'"` → 6 passed, 0 failed.
- The P6 verifier now requires machine-readable `truth_level=planning_contract`, `runtime_migration=not_started`, `host_loaded=not_run`, `live_accepted=not_run` and `full_gate=not_passed` markers in this evidence file, while allowing verified task progress.
- `SMV-P6-001` is the only completed P6 task; `SMV-P6-002` through `SMV-P6-012` remain pending. Runtime migration has not started, host loading and live acceptance remain unverified, and the full quality gate remains not passed.

## Rollback

Remove P6-only files and revert only the P6 current-phase/admission paragraphs in product docs, plan, todo, tests and AGENTS. Preserve P0–P5 manifests/specs/evidence and all unrelated concurrent changes.
