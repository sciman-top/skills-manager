# Skills / MCP update evidence (2026-07-13)

## Goal and scope

- Goal: finish the interrupted skills update, repair the Remotion projection failure, refresh the lock, and synchronize managed MCP configuration.
- Source of truth: `skills.json`; generated outputs remain `agent/`, `reports/skill-projection/current.json`, and managed host configuration blocks.
- Pre-existing worktree boundary: 21 modified `imports/*` gitlinks were already present before this task. They were preserved and completed by the authorized update flow. The successful update additionally advanced `drawio-diagram-forge`, `mcp-cli`, `powerpoint-automation`, and `slidev`.
- Out of scope: ownership of model, auth, provider, context, sandbox, and native Claude MCP registration. The skills projection renderer was hardened so its managed markers cannot delete foreign host tables that another TOML writer moved between those markers.

## Root cause and change

- Reproduction: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 构建生效` exited 1. It reported the invalid mapping `skills\remotion -> skills-2-skills-remotion`, then failed closed because profile `physics` referenced missing canonical skill `remotion-best-practices`; `agent/` was restored transactionally.
- Upstream evidence: `remotion-dev/skills` moved from locked commit `6726bf2d4bcce0359806749b3656b0c886d74aaa` to `8b1d51ade295b2d9bd22a8f07047d13c0740f275`, deleting `skills/remotion` and adding `skills/remotion-best-practices`.
- Fix: changed the vendor import and mapping source to `skills\remotion-best-practices`, retaining the existing output directory and declared profile name for compatibility.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 更新 -Upgrade` exited 0, refreshed vendor sparse-checkout, rebuilt 115 unique projected skills with 0 conflicts, restored the Remotion Junction, and regenerated `skills.lock.json`.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 同步MCP` exited 0. Claude configuration state validated with active servers `microsoft-learn` and `openaiDeveloperDocs`. Native Claude registration and cross-CLI live checks remained disabled by repository defaults.
- Manual live probes were then run read-only: `claude mcp list` reported all 12 configured services Connected; `codex -c 'model_provider="openai"' mcp list` showed the two default-profile services enabled and the other managed services disabled as intended.

## Codex provider boundary regression

- Cockpit Tools writes both `model_provider = "codex_local_access"` and `[model_providers.codex_local_access]`. Its TOML serializer can move the provider and `[features]` tables between the skills-manager projection comments.
- Root-cause replay against the pre-fix renderer produced `input_provider=True`, `output_provider=False`, `input_features=True`, and `output_features=False`: `Build-CodexSkillsProjectionToml` deleted every line between its comments even when those lines belonged to another host configuration owner.
- Fix: the renderer now removes only `[[skills.config]]` tables inside its comments, preserves any foreign TOML tables, removes the old comments, and appends one regenerated projection block at the end.
- Regression test: `Preserves foreign TOML tables moved inside the managed markers` failed before rebuilding the fixed source and passed after `build.ps1`; the complete SkillProjection suite passed 15/15.
- Live apply: `skills.ps1 构建生效` exited 0. The resulting host config retains the selector, `[model_providers.codex_local_access]`, and `[features]`; the foreign tables precede the single projection block. Bare `codex mcp list` then exited 0 without a provider override.

## Performance assessment

- Root cause: `apply_targets` recursively SHA-256 hashed all 115 skill packages on every run, covering about 13,486 files / 83MB. Historical samples were about 13-16 seconds. The old `build_agent` metric also mixed 6-20ms cache hits with 11-14 second full builds.
- Fix: the projection manifest now stores additive cache metadata. A package hash is reused only after a current verified Agent build signature, managed Junction target check, per-package directory fingerprint, `SKILL.md` content hash, and strict SHA-256 field validation all pass. Any invalid value or managed miss falls back to full hashing; the five `.system` skills always remain on the full-hash path.
- Metrics: Agent work is split into `build_agent_cache_hit` and `build_agent_full`. Projection link reconciliation, package hashing, plan, TOML render, persistence, and target-link phases are recorded independently. A hot projection means every managed package hit the cache with zero managed misses, even though system packages remain fully hashed.
- Cold cache-seeding sample: `apply_targets=19042ms`, `projection_package_hash_full=16202ms`, `cache_hits=0`, `cache_misses=110`, and `full_hash_count=115`.
- Hot samples after seeding: `apply_targets=4449ms`, then `4089ms`, then `3765ms`. The final sample recorded `projection_link_reconcile=675ms`, `projection_package_hash_cache_hit=1134ms`, `projection_plan_cached=2765ms`, `cache_hits=110`, `cache_misses=0`, and `full_hash_count=5`.
- The final three-sample Doctor window reported `apply_targets last=3765ms avg=4101ms`, below the unchanged 5000ms threshold, with no performance anomaly. `build_agent_cache_hit` remained 7-9ms. Thresholds were not raised to hide the bottleneck.
- Stable projection content was unchanged across cold/hot runs: schema 2, 115 entries, 115 unique names, 97 disabled paths, 0 conflicts, and stable name/content/package digest `dd7691fe6f14b48e4a0d84363f97e573098b5c955d86d8f0f991eb87af97cc47`.

## Verification

Fixed order and exit codes:

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\build.ps1` - exit 0.
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1` - exit 0.
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 doctor --strict --threshold-ms 8000` - exit 0.
4. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` - exit 0.
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` - exit 0; build, hygiene, generated-sync, dependency baseline, doctor JSON contract, unit tests, and E2E tests passed.

Additional review evidence:

- Performance-focused regression suite passed 50/50 after adding managed cache hot-path classification and malformed-hash fallback coverage.
- Remotion import path, mapping path, frontmatter name, physics profile reference, generated skill, Junction target, and projection manifest canonical entry agree.
- Projection manifest: 115 unique names, 97 disabled paths, 0 conflicts, active and all-profile metadata budgets pass.
- Lock/workspace comparison: 52 imports and 9 vendors match their locked commits.
- `git diff --check` passed; sensitive-keyword scan outside the lock returned 0 matches.
- Doctor reported non-blocking performance warnings for `apply_targets` and `build_agent`; `--strict` passed. These warnings predate and are not caused by the path migration.
- Bare `codex mcp list` exits 0 after the projection renderer repair; no model-provider override is required.

## Risk and rollback

- Risk: this is a bulk upstream content refresh; upstream skill text changed independently of this repository. The lock records the exact commits and the full local gate validates repository contracts, but it does not semantically certify every upstream instruction.
- Risk: the renderer uses TOML table headers as ownership boundaries but does not parse or rewrite foreign tables. This deliberately preserves unknown host configuration instead of claiming ownership of it.
- Roll back only this slice by restoring the two Remotion paths in `skills.json`, restoring the prior `skills.lock.json` and the intended import gitlinks, then running `更新 -Locked`, `构建生效`, and `同步MCP`.
- To roll back only the provider-boundary or performance fixes, restore the relevant changes in `src/Commands/SkillProjection.ps1`, `src/Commands/Install.ps1`, `src/Commands/Doctor.ps1`, `src/Core.ps1`, and their matching tests, then run `build.ps1`. Additive manifest cache fields are backward compatible and may remain; older code ignores them and recomputes hashes. The live config backup created before projection remains under `~/.codex/config-backups/`.
- Do not restore or overwrite unrelated `imports/**`, audit/MCP source changes, or user configuration outside managed blocks. Back up current managed host configuration before any rollback.
