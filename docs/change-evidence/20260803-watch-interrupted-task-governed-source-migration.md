# watch-interrupted-task governed source migration

## Problem and root cause

`watch-interrupted-task` was created directly under `~/.codex/skills`, bypassing this repository's governed skill chain. The creation flow applied `skill-creator`'s generic personal-install default before resolving the repository-specific ownership contract. A second premature assumption treated `build.ps1` as the `agent/` generator even though the real apply entrypoint is `skills.ps1 构建生效`.

The repository contract and current runtime truth define this chain:

```text
overrides/<skill> -> agent/<skill> -> ~/.agents/skills/<skill>
```

`~/.codex/skills/.system` and the plugin cache remain host-owned. Direct custom skills under `~/.codex/skills` are outside the governed source chain.

## Changes

- Added `overrides/watch-interrupted-task` as the tracked source, including `agents/openai.yaml`.
- Added `watch-interrupted-task` to `skill_projection.resident_names` so the night-watch command remains available under every profile.
- Kept the stable skill name and `watch-interrupted-task:v1` automation marker for compatibility.
- Shortened only frontmatter metadata to stay within the existing 8000-character profile budgets; no budget was raised.
- Extended `verify-skill-integrity.ps1` with `misplaced_codex_user_skill` and an isolated regression test.
- Removed the old host-local Skill files after source/generated/projected hashes matched.

## Directory audit

Fresh post-migration inventory:

- `overrides`: 13 top-level directories, 12 Skill entrypoints; tracked customization source.
- `agent`: 108 generated directories, 107 Skill entrypoints.
- `~/.agents/skills`: 107 managed Junctions; zero non-link or wrong-target entries.
- `~/.codex/skills`: zero custom Skill entrypoints; `.system` remains host-owned.
- `~/.claude/skills`: configured target linked to generated `agent/` content.
- Codex plugin cache: 46 plugin-owned Skill entrypoints; not copied into `overrides`.
- Projection manifest: 111 unique names, zero conflicts; `watch-interrupted-task` is resident.

## Verification and boundaries

- `quick_validate.py overrides/watch-interrupted-task`: required.
- `build.ps1`: required before tests.
- `SkillIntegrityScript.Tests.ps1` and `SkillProjection.Tests.ps1`: regression and projection coverage.
- `verify-skills-config.ps1`, `verify-skill-integrity.ps1`, and `verify-skill-routing.ps1`: config and contract checks.
- `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`: final acceptance gate before commit.

`构建生效 -DryRun` is `gate_na` for a newly added resident Skill because dry-run does not materialize the candidate `agent/` tree before projection validates `resident_names`.

- reason: projection reads the existing generated tree while dry-run only collects mirror operations.
- alternative_verification: normal transactional `构建生效`, which rolls back `agent/` on failure, followed by hash, Junction, manifest, prompt-discovery, and full-gate checks.
- evidence_link: this change evidence and the command receipts for the migration turn.
- expires_at: when dry-run projection evaluates the candidate generated tree.
- recovery_condition: a regression test proves new resident Skills can pass dry-run without host writes.

The empty directory shell left at `~/.codex/skills/watch-interrupted-task/agents` contains no files or `SKILL.md`; host command policy denied removing the empty directories. It is not a discoverable Skill and is excluded from source, projection, and integrity counts.

Rollback is limited to removing the new override and resident entry, rebuilding projection, and restoring the pre-migration host copy only if continuity behavior must be reverted. Do not edit `agent/`, projection Junctions, or Codex managed config blocks directly.
