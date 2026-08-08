# Host-Native Skill Lifecycle Reset Implementation Plan

> Execute one manifest task at a time. Each task begins by re-reading its current files and recording the exact write-set boundary; no task may assume this planning snapshot is still current.

**Goal:** Replace profile/router-owned reachability with complete host-native progressive disclosure while retaining deterministic inventory, policy, projection, rollback and evidence.

**Architecture:** A deep catalog/policy core feeds a `HostCapabilitySnapshot`-aware metadata planner. Host adapters expose effective capabilities; native host AI owns semantics and full skill injection. A narrow App Server strict-dispatch adapter is optional and separately traced.

**Stack:** PowerShell 7, JSON/plain-object contracts, Pester, App Server/CLI native probes, Git/hash/atomic receipt transactions. C#/.NET stays shadow-only; no new service, database, embedding or provider call.

## Execution waves

| Wave | Tasks | Parallel rule |
| --- | --- | --- |
| 0 | `SMV-P6-001` | single writer for product/planning truth |
| 1 | `SMV-P6-002`, `SMV-P6-004` | may run in parallel only with disjoint source/test files |
| 2 | `SMV-P6-003`, `SMV-P6-005` | adapters and planner may run in parallel after contracts freeze |
| 3 | `SMV-P6-006`, `SMV-P6-007`, `SMV-P6-008` | projection, metadata eval and trace use separate modules; shared fixtures have one integration owner |
| 4 | `SMV-P6-009`, `SMV-P6-011` | both read prior outputs; no shared generated/config writes |
| 5 | `SMV-P6-010` | single writer for config/schema/profile migration |
| 6 | `SMV-P6-012` | single integration owner; full gate exactly once |

## Task execution contract

For every task, follow the exact `preconditions`, `write_set`, `implementation_steps`, `tests`, `verification`, `rollback`, `done_when` and `out_of_scope` fields in `tasks/skills-manager-vnext-phase6.tasks.json`. Apply this test loop:

1. Add or update the smallest failing Pester/contract fixture for the stated risk.
2. Run the focused test and confirm the expected failure reason.
3. Implement the named interface/module with no unrelated cleanup.
4. Re-run the focused test, then the affected contract verifier.
5. Run `build.ps1` whenever source/config/override affects generated output.
6. Record command output and truth level in the task's reviewed evidence.
7. Update manifest/plan/todo status only after verification succeeds.

## Task file-level checkpoints

| Task | Primary interfaces/files | Red test | Completion command |
| --- | --- | --- | --- |
| `SMV-P6-001` | product docs, P6 spec/manifest/verifiers | planning verifier rejects inconsistent admission/current phase | `scripts/verify-host-native-skill-lifecycle-planning.ps1` |
| `SMV-P6-002` | `HostCapabilitySnapshot`, precedence resolver | conflicting sources choose wrong precedence or hide unknown | affected snapshot Pester |
| `SMV-P6-003` | App Server, CLI and config-fallback adapters | fallback is incorrectly labeled runtime truth | adapter contract + bounded native probe |
| `SMV-P6-004` | `SkillCatalogCompiler`, `SkillEligibilityPolicy` | semantic ranking/profile exclusion survives in core | catalog/policy Pester + routing contract |
| `SMV-P6-005` | `NativeMetadataPlanner` | enabled item is silently omitted or character budget used as token truth | budget fixtures at known/unknown contexts |
| `SMV-P6-006` | projection plan/apply/receipt | eligible skill missing from native root or rollback drifts | projection tests + generated sync |
| `SMV-P6-007` | metadata lint and eval corpus | long/ambiguous/negative descriptions pass without findings | corpus verifier |
| `SMV-P6-008` | `NativeInvocationTrace` normalizer | visibility is incorrectly promoted to invocation | trace fixtures and truth-level tests |
| `SMV-P6-009` | shadow evaluator/report | legacy result changes runtime or hides disagreement | shadow zero-write contract |
| `SMV-P6-010` | config migration/profile compatibility view | profile still excludes enabled skill or rollback loses data | migration round-trip tests |
| `SMV-P6-011` | strict dispatch adapter | fallback runs by default or injects unadjudicated skill | App Server fixture + opt-in negative test |
| `SMV-P6-012` | release docs/evidence/manifests | incomplete task or partial host truth is called complete | planning verifier + one full quality gate |

## Integration and release checkpoints

- Checkpoint A: contracts compile and unknown host facts fail closed.
- Checkpoint B: catalog/policy contain no semantic selector and no profile reachability filter.
- Checkpoint C: all-enabled plan reports `enabled_total == kept_total`, `truncated=false`, `omitted=0` for the verified host snapshot.
- Checkpoint D: fresh native projection exposes representative formerly unreachable skills.
- Checkpoint E: trace distinguishes listed, selected, injected, executed and abstained.
- Checkpoint F: legacy profile/router path is compatibility-only and round-trip rollback is proven.
- Checkpoint G: strict dispatch is explicit opt-in and shares the same policy core.
- Checkpoint H: full gate and release evidence pass; only then mark P6 `repo_verified`.

## Truth boundary

Creating and validating this plan establishes a `planning_contract`. Individual pending tasks have not been implemented. Repository tests cannot prove the host will select every correct skill probabilistically, and visibility cannot prove full `SKILL.md` invocation. Those claims require fresh host trace at the level explicitly recorded by each task.
