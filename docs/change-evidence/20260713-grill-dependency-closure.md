# Grill dependency closure evidence

## Scope

- Added `grilling` from `skills/productivity/grilling`.
- Added `domain-modeling` from `skills/engineering/domain-modeling`.
- Enabled `grill-with-docs`, `grilling`, and `domain-modeling` in the `default`, `coding`, and `dotnet` skill profiles.
- Removed `grill-me` so `grill-with-docs` is the single user-facing interview entry point.

## Invocation contract

- `$grill-with-docs`: the unified interview entry; invokes `grilling` and `domain-modeling`.
- `$grilling`: direct use of the one-question-at-a-time design interview primitive.
- `$domain-modeling`: direct use when changing domain language, `CONTEXT.md`, or an ADR.
- `domain-modeling` creates or updates `CONTEXT.md` and ADRs only when terminology, boundaries, or durable decisions actually change.

## Supply chain

Both dependencies come from `https://github.com/mattpocock/skills.git`, are sparse manual imports, and are pinned in `skills.lock.json` to commit `66898f60e8c744e269f8ce06c2b2b99ce7660d5f`. `grill-with-docs` remains pinned to `391a2701dd948f94f56a39f7533f8eea9a859c87`.

## Cache correctness repair

Removing `grill-me` exposed a stale-output cache bug: `.build-cache.json` described 112 expected outputs while `agent/` still contained 113 directories, but `Test-AgentBuildCacheHit` checked only that expected directories existed. The fast path now rejects unexpected top-level output directories and falls back to the existing transactional full rebuild. `BuildCache.Tests.ps1` includes a regression case that failed before the source fix and passed after regenerating `skills.ps1`.

## Verification

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`: passed; generated `skills.ps1` is synchronized with `src/`.
- `skills.ps1 构建生效`: passed; performed a transactional full rebuild, reduced `agent/` from 113 to 112 skills, and removed the stale Codex Junction.
- Static inventory: `grill-me` is absent from `agent/`, `$HOME/.agents/skills`, and `$HOME/.claude/skills`; `grill-with-docs`, `grilling`, and `domain-modeling` exist in all three locations.
- Projection manifest: 116 entries, 116 unique names, 0 duplicate-name groups, 0 conflicts, and all profile budgets pass.
- `scripts/verify-codex-skill-profiles.ps1`: passed for `coding`, `ppt`, `dotnet`, and `default`; the script restored `default` as the active profile. Relevant budgets are `coding=7788/8000`, `dotnet=7588/8000`, and `default=7150/8000`.
- `tests/run.ps1`: passed, Unit 442/442 and E2E 12/12.
- `skills.ps1 doctor --strict --threshold-ms 8000`: passed. Historical average `apply_targets` latency remains a non-blocking performance warning under the current contract.
- `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`: passed.
- `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`: passed on the final source/config/test slice; build, repository hygiene, generated sync, dependency baseline, doctor JSON contract, Unit 442/442, and E2E 12/12 all passed.

## Rollback

Restore the removed `grill-me` import/mapping only if the separate lightweight entry is required again. To roll back the whole dependency slice, remove the three retained mappings/imports and profile entries, refresh `skills.lock.json`, then run `skills.ps1 构建生效`. Roll back only these paths and the corresponding host Junctions.
