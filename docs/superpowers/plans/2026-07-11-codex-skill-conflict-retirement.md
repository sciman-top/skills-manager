# Codex Skill Conflict Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate the two remaining Codex duplicate-name groups while retaining Anthropic `skill-creator` for Claude.

**Architecture:** Add an exact-directory exclusion list at the managed Junction boundary. Retire only the obsolete curated `openai-docs` mapping and leave vendor sources, imports, `.system`, and Claude's root Junction intact.

**Tech Stack:** PowerShell 7, Pester 4, JSON configuration, Windows Junctions.

## Global Constraints

- Do not delete or modify host-owned `.system` skills.
- Do not remove the Anthropic `skill-creator` mapping from `agent/`.
- Exclusions match exact directory names case-insensitively.
- Preserve the fixed `build -> test -> contract/invariant -> hotspot` gate order.

### Task 1: Managed Link Exclusions

**Files:**
- Modify: `tests/Unit/SkillProjection.Tests.ps1`
- Modify: `src/Commands/SkillProjection.ps1`

- [ ] Add a test with managed `keep` and `exclude` directories, an existing Junction for each, and `managed_link_excludes = @("exclude")`.
- [ ] Verify the test fails because the excluded Junction remains projected.
- [ ] Normalize the optional exclusion array into a case-insensitive set, skip excluded directories, and let stale-link cleanup remove their managed Junctions.
- [ ] Verify the focused projection tests pass.

### Task 2: Configuration Contract And Documentation

**Files:**
- Modify: `src/Config.ps1`
- Modify: `tests/Unit/ConfigUpdate.Tests.ps1`
- Modify: `README.md`

- [ ] Add contract tests proving `managed_link_excludes` remains an array and rejects blank or duplicate names.
- [ ] Validate the field in both non-throwing and throwing configuration validation paths.
- [ ] Document that exclusions affect only Codex Junction projection and preserve `agent/` for Claude.

### Task 3: Apply Targeted Retirement

**Files:**
- Modify: `skills.json`
- Generated: `skills.ps1`, `agent/`, `reports/skill-projection/current.json`

- [ ] Remove only the curated `openai-docs` mapping.
- [ ] Add `anthropics-skills-skills-skill-creator` to `managed_link_excludes`.
- [ ] Build and apply the projection.
- [ ] Verify duplicate/conflict counts are zero, both system skills remain active, both non-system Codex Junctions are absent, and Claude's generated Anthropic skill remains present.

### Task 4: Full Verification

- [ ] Run `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`.
- [ ] Run `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`.
- [ ] Run strict doctor and dependency baseline verification.
- [ ] Run the full local quality gate with the documented dirty-worktree allowance.
- [ ] Review the final diff for scope, secrets, generated drift, and rollback completeness.
