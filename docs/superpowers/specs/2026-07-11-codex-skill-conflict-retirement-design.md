# Codex Skill Conflict Retirement Design

## Goal

Remove the two remaining Codex duplicate-name groups without removing Claude capabilities or host-owned system skills.

## Decisions

- Remove the managed mapping for the deprecated curated `openai-docs`; Codex keeps the host-owned `.system/openai-docs` implementation.
- Keep the Anthropic `skill-creator` mapping in `agent/` for Claude, but exclude its generated directory from the Codex per-skill Junction projection.
- Add `skill_projection.managed_link_excludes` as an optional array of exact managed directory names.
- Exclusions affect only `Sync-CodexManagedSkillLinks`; they do not delete imports, mappings, generated agent skills, `.system`, or retirement archives.
- Reject blank and duplicate exclusions in both configuration validation paths.

## Data Flow

`skills.json` supplies the exclusion list. `构建生效` builds `agent/`, then `Sync-CodexManagedSkillLinks` creates Junctions for non-excluded directories and removes an existing managed Junction when its directory becomes excluded. The projection scanner then sees the host `.system` copies without the excluded managed candidates.

## Expected Result

- Codex projection: `duplicate_name_groups = 0`, `conflict_count = 0`.
- `~/.agents/skills/skills-skills-.curated-openai-docs` is removed as a stale managed Junction.
- `~/.agents/skills/anthropics-skills-skills-skill-creator` is removed as an excluded managed Junction.
- `agent/anthropics-skills-skills-skill-creator/SKILL.md` remains available through `~/.claude/skills -> agent`.
- `.system/openai-docs` and `.system/skill-creator` remain active for Codex.

## Verification And Rollback

Run the repository gates in fixed order. Rollback restores the removed `openai-docs` mapping, removes `managed_link_excludes`, rebuilds, and reruns `构建生效`; no archive restoration is required.
