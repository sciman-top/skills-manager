# Lean Delivery M0.1 correction and M1 bootstrap evidence

## Scope

- Goal: correct the maintenance contract without creating a new runtime, then start the authorized ten-task pilot as an honest observe-only collection.
- Source: `docs/superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md`.
- Write set: the maintenance spec, `tasks/skills-manager-vnext-lean-delivery-pilot.json`, the existing Lean planning verifier, its focused Pester tests, and this evidence file.
- Shared-checkout boundary: product truth files, `AGENTS.md`, `tasks/plan.md`, `tasks/todo.md`, generated files, `src/`, overrides, imports, and unrelated tests belong to other work and are not staged or rolled back by this slice.

## Decisions

- North Star: improve verifiable user value per unit of user attention, token, and maintenance cost while remaining native-first and deletable.
- Native baseline: Goal, subagents, scheduled tasks, local memories, App Server, and SDK stay host-owned. The repository does not reproduce them.
- Stable intents: Discover, Advise, Transact, and Verify. Lean Delivery does not gain transaction authority.
- Pilot state: `collecting`, with zero of ten real samples. The current correction/bootstrap is self-referential and cannot count.
- Baseline method: prefer matched historical native-only work or alternating matched tasks. Unmatched work is descriptive-only; the same task is not duplicated merely to manufacture a comparison.
- Evidence flow: M1 evaluates the advisory lens independently of P5-local M2 defect correction. Both feed a later retain/revise/retire review; neither admits P6.
- Deletion review: reuse existing documentation fields for candidate value, native equivalent, consumers, cost, trigger, and evidence. No second registry is created.

## Truth boundary

- M0 remains historical `4/4 repo_verified`.
- M1 is authorized and its collection contract is implemented; sample count remains `0/10`.
- No pilot task has been observed or reviewed by this slice.
- No provider, model, auth, profile, plugin, MCP, host configuration, runtime, daemon, database, production, or live acceptance action occurs.
- P6 admission remains `hold`; no P6 manifest exists.

## Verification

- `git diff --check -- <exact write set>`: exit 0; only the repository's expected LF-to-CRLF notices were emitted.
- `build.ps1`: exit 0; `Build success: D:\CODE\skills-manager\skills.ps1`.
- focused `ProductPlanning.Tests.ps1` and `LeanAiDeliveryPlanning.Tests.ps1`: exit 0; 33 passed, 0 failed. After removing duplicate registry metadata, the affected Lean file was rerun: 20 passed, 0 failed.
- `verify-vnext-planning.ps1 -Json`: exit 0; P5 5/5 done, 0 open, 0 findings.
- `verify-lean-ai-delivery-planning.ps1 -Json`: exit 0; M0 4/4 done, M1 collecting 0/10, P6 hold, 0 findings.
- one full quality gate with `-AllowDirtyWorktree`: exit 0 in 193.478 s; Unit 766/766, E2E 18/18, skill integrity 107, routing findings 0, P5 planning 5/5, and all configured stages passed.

## Rollback

Revert only the four implementation/contract files and this evidence file from the eventual commit. Do not reset, restore, stage, or otherwise modify peer-owned dirty paths.
