# SMV-P0-004 OperationPlan and Receipt v1 contract evidence

**Date**: 2026-08-01
**Scope**: repository-side pure contracts only
**Runtime baseline**: PowerShell 7.6.3 primary; Windows PowerShell 5.1.26100.8972 bounded compatibility smoke

## Goal and destination

- Current destination: `src/Domain/OperationPlan.ps1` and `src/Domain/Receipt.ps1`, generated into `skills.ps1` by `build.ps1`.
- Contract destination: versioned plain objects with declarative schemas in `config/operation-*.schema.json`.
- Verification destination: deterministic Pester fixtures plus the existing ordered repository gates.
- No existing Audit, MCP, SkillProjection, config write, host projection or native command path is migrated in this task.

## Existing-field review

| Surface | Existing facts | Decision for v1 contract |
| --- | --- | --- |
| Audit Apply | Distinguishes preflight, dry-run and apply; writes command-specific reports and automatic evidence; preserves original recommendation indexes. | Adopt the distinct dry-run/applied truth boundary. Reject report-specific fields and automatic evidence IO from the pure domain contract. |
| MCP | Uses `$DryRun` to suppress config/native writes and renders target-specific human previews. | Adopt zero-write planning semantics. Reject human output and target-specific CLI rendering as the shared contract shape. |
| SkillProjection | Returns `success`, `persisted`, `changed`, paths, backup path and projection summary; dry-run does not persist config/manifest. | Adopt explicit persisted/change/backup concepts for later receipts. Reject the large projection result object as a generic domain model. |

This keeps the shared envelope small. Command-specific payloads remain owned by their current modules until a real consumer is migrated in later tasks.

## Implemented contract

- `OperationPlan` schema v1 with deterministic `action_id`, normalized target ordering, structured findings, freshness checks for root/owner/hash/existence/source revision, and caller-supplied IDs/timestamps.
- `Receipt` schema v1 with independent `static_validated`, `repo_gates_passed`, `host_loaded` and `live_accepted` states.
- Recursive construction-time redaction for token/API key/password/authorization properties, URL userinfo/query secrets, PostgreSQL/Npgsql connection strings, env, headers and argv.
- Pure domain boundary: no file, Git, network, environment, clock, terminal output or process execution side effects.
- PowerShell 7 is the primary runtime. PowerShell 5.1 coverage is intentionally limited to parse and plain-object construction smoke; the formal support matrix remains `SMV-P0-008`.

## Fault and invariant coverage

- Valid and invalid plan/receipt fixtures.
- Input enumeration reorder preserves action IDs, targets and serialized plan.
- Constructors do not mutate caller inputs.
- Lexical root traversal, sibling-prefix paths, owner drift, before-hash drift, newly created targets and source revision drift fail closed.
- Updating repo verification does not promote host/live; a higher-level failure does not clear a lower-level pass.
- Known secret forms are absent from serialized plan/receipt objects.
- JSON parsed by PowerShell 7.6 is accepted when RFC3339 values have already become `DateTime` instances.

## Verification evidence

| Order | Command | Result |
| ---: | --- | --- |
| 1 | `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0; generated `skills.ps1` |
| 2 | targeted `tests/Unit/OperationContracts.Tests.ps1` with Pester 4.10.1 | 10 passed, 0 failed |
| 3 | `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` | Unit 531/531; E2E 12/12 |
| 4 | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json` | 9 tasks; 4 done; 5 open; 0 findings |
| 5 | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skills-config.ps1 -ConfigPath skills.json -Mode enforce` | valid; hash before/after identical |
| 6 | `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000` | exit 0 |
| 7 | `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` | exit 0 |
| 8 | `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/check-generated-sync.ps1 -AllowDirtyWorktree` | source/generated sync; dirty development state explicitly allowed |
| 9 | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | exit 0; full local quality gates passed |

All listed closeout gates were rerun after the task status and evidence surfaces were synchronized. The final diff/write-set audit is recorded in the handoff and must remain clean before commit.

## N/A and truth boundary

| Classification | Reason | Alternative evidence | Recovery condition |
| --- | --- | --- | --- |
| `platform_na` host load | No host-loaded surface changed. | Pure contract/freshness tests and full repo gates. | Run native fresh-session probes only when a consumer changes host state. |
| `gate_na` live workflow | No user workflow or apply path consumes the new contract yet. | Existing behavior regression suite and zero-IO tests. | Execute a real consumer workflow before any `live_accepted` claim. |

This evidence closes only `SMV-P0-004` at repository pure-contract scope. `SMV-P0-005` through `SMV-P0-009`, Phase 0 completion, host loading and live workflow acceptance remain open.

## Rollback

Remove the two Domain sources from `build.ps1`, remove the schemas/tests/fixtures/evidence, restore the prior planning status surfaces, and rebuild `skills.ps1`. Rollback must not touch `skills.json`, imports, audit runtime reports, host config or unrelated user changes.
