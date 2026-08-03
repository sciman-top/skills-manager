# Codex skill conflict retirement evidence

## Scope

- Removed the deprecated curated `openai-docs` mapping from `skills.json`.
- Kept Anthropic `skill-creator` in `agent/` and Claude, while excluding its per-skill Codex Junction.
- Added and validated `skill_projection.managed_link_excludes`.
- Did not delete `.system`, imports, retirement archives, or Anthropic source content.

## Existing dirty-worktree boundary

The pre-existing `microsoft-docs` mapping/import, `imports/microsoft-docs/`, skill/MCP research evidence, and audit runtime evidence are user-owned changes outside this rollback scope.

## Verification

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` -> exit 0.
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` -> Unit 433 passed; E2E 12 passed.
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0.
4. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` -> verified.
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` -> passed.
6. `reports/skill-projection/current.json` -> `skill_entry_count=115`, `unique_name_count=115`, `duplicate_name_groups=0`, `conflict_count=0`.
7. Codex curated `openai-docs` and Anthropic `skill-creator` Junctions are absent; system copies are present.
8. `agent/anthropics-skills-skills-skill-creator/SKILL.md` and the corresponding Claude path are present.

## Rollback

Re-add the curated `openai-docs` mapping, remove `skill_projection.managed_link_excludes`, revert only this slice's source/tests/docs/generated entry changes, then run `build.ps1` and `skills.ps1 构建生效`. Do not revert the pre-existing files listed above.
