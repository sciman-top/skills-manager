# Installed Skill Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every retained managed skill structurally callable, close declared composite-skill dependencies, and block future broken entrypoint resources from reaching host projections.

**Architecture:** A standalone PowerShell verifier inventories generated top-level skills, validates entrypoint-local Markdown links and an explicit dependency contract, and emits JSON. The quality gate calls the verifier. Remediation removes incomplete redundant packages and adds one managed resource bridge for the retained Superpowers workflow.

**Tech Stack:** PowerShell 7/Windows PowerShell 5.1 compatible scripts, JSON configuration, Pester 4.10, existing skills-manager build/projection pipeline.

## Global Constraints

- Never edit `agent/` directly; repair `skills.json`, sources, `overrides/`, or `src/`.
- Do not install all Python/npm/.NET/media dependencies globally.
- Smoke tests must not publish, send, create remote issues, invoke paid APIs, or automate Office GUI.
- The final active profile must be `default`.
- Fixed gate order remains `build -> test -> contract/invariant -> hotspot/full`.

---

### Task 1: Fail-closed integrity verifier

**Files:**
- Create: `scripts/verify-skill-integrity.ps1`
- Create: `config/skill-dependency-closure.json`
- Create: `tests/Unit/SkillIntegrityScript.Tests.ps1`

**Interfaces:**
- Consumes: generated `agent/`, `skills.json`, and the dependency contract.
- Produces: exit code `0/1` plus a JSON object with `ok`, `skill_count`, `errors`, `warnings`, and `checks`.

- [x] Write failing Pester fixtures for a missing relative entrypoint link, missing required skill, profile closure mismatch, and a valid package.
- [x] Run `Invoke-Pester tests/Unit/SkillIntegrityScript.Tests.ps1` and confirm the verifier is missing.
- [x] Implement the verifier with path-safe relative link resolution, YAML frontmatter name extraction, unique-name checks, and explicit profile dependency validation.
- [x] Add dependency declarations for `grill-with-docs`, `improve-codebase-architecture`, `to-spec`, `to-tickets`, and the Superpowers planning/execution chain.
- [x] Re-run the focused tests and require all fixtures to pass.

### Task 2: Remove incomplete duplicate packages and repair retained resources

**Files:**
- Modify: `skills.json`
- Modify: `skills.lock.json` through `skills.ps1` lock generation
- Create: `overrides/resources/requesting-code-review/code-reviewer.md`
- Delete gitlinks: `imports/openpyxl`, `imports/python-docx`, `imports/python-pptx`, `imports/ppt-master`, `imports/python-design-patterns`, `vendor/web-quality-skills`

**Interfaces:**
- Consumes: verifier findings from Task 1.
- Produces: generated `agent/` with zero broken relative links in every retained top-level `SKILL.md`.

- [x] Run the verifier before remediation and capture the failing skills.
- [x] Remove the six mappings/imports and the unused `web-quality-skills` vendor/profile entry.
- [x] Add a resource-only override bridge for the Superpowers reviewer template without introducing a duplicate `SKILL.md`.
- [x] Regenerate the lock and rebuild/apply projections.
- [x] Run the verifier and require zero blocking findings.

### Task 3: Quality-gate integration and safe smoke coverage

**Files:**
- Modify: `scripts/quality/run-local-quality-gates.ps1`
- Modify: `tests/Unit/QualityGateScripts.Tests.ps1`
- Modify: `src/Commands/Utils.ps1`
- Modify generated: `skills.ps1`

**Interfaces:**
- Consumes: `scripts/verify-skill-integrity.ps1`.
- Produces: `skill-integrity` quality-gate stage and documented command entry.

- [x] Add a failing unit assertion that quick/full quality gates invoke `skill-integrity` after generated-sync and before dependency baseline/tests.
- [x] Wire the verifier into the quality-gate script and add the help command.
- [x] Build `skills.ps1` and run focused quality-script tests.
- [x] Validate every profile plan and budget without leaving the host on a non-default profile.

### Task 4: Evidence and full verification

**Files:**
- Modify: `docs/change-evidence/20260713-installed-skill-dependency-closure.md`
- Modify: `docs/superpowers/specs/2026-07-13-installed-skill-integrity-design.md` only if implementation changes an approved contract.

**Interfaces:**
- Consumes: final verifier report and gate output.
- Produces: auditable closeout with residual runtime boundaries and rollback commands.

- [x] Run `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`.
- [x] Run `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`.
- [x] Run strict doctor and dependency baseline verification.
- [x] Run `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`.
- [x] Confirm `default` is active, projection conflicts are zero, verifier errors are zero, and `git diff --check` passes.
