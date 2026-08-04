# Lean Delivery M0.1 correction and M1 bootstrap evidence

## Scope

- Goal: correct the maintenance contract without creating a new runtime, then start the authorized ten-task pilot as an honest observe-only collection.
- Source: `docs/superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md`.
- Write set: the maintenance spec, pilot registry, existing Lean planning verifier/tests, PRD/architecture/roadmap/product index, `AGENTS.md`, plan/todo, and this evidence file.
- Shared-checkout boundary: product truth files already contain unrelated follow-up edits. This slice stages only the Lean M0.1/M1 hunks; generated files, `src/`, overrides, imports, unrelated evidence, and unrelated tests remain unstaged and outside rollback.

## Decisions

- North Star: improve verifiable user value per unit of user attention, token, and maintenance cost while remaining native-first and deletable.
- Native baseline: Goal, subagents, scheduled tasks, local memories, App Server, and SDK stay host-owned. The repository does not reproduce them.
- Stable intents: Discover, Advise, Transact, and Verify. Lean Delivery does not gain transaction authority.
- Pilot state: `collecting`, with zero of ten real samples. The current correction/bootstrap is self-referential and cannot count.
- Baseline method: prefer matched historical native-only work or alternating matched tasks. Unmatched work is descriptive-only; the same task is not duplicated merely to manufacture a comparison.
- Evidence flow: M1 evaluates the advisory lens independently of P5-local M2 defect correction. Both feed a later retain/revise/retire review; neither admits P6.
- Deletion review: reuse existing documentation fields for candidate value, native equivalent, consumers, cost, trigger, and evidence. No second registry is created.
- Product projection: PRD, architecture, roadmap, product index, root contract, plan, and checklist now expose the same `collecting (0/10)` boundary and link the registry without rewriting historical P5/M0 truth.

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
- product-truth projection verification: focused planning tests 33/33; P5 verifier 5/5 with 0 findings; Lean verifier M0 4/4 and M1 collecting 0/10 with 0 findings; exact-hunk staged review passed for eight paths with unrelated same-file hunks left unstaged.
- full-gate rerun: `gate_na`; reason is a docs-only projection after the verified implementation commit; alternative verification is focused product/Lean planning tests plus both verifiers and `git diff --cached --check`; prior evidence is the full gate above; expires at this docs-only commit; recovery condition is any code, script, schema, generated, or runtime behavior change.

## Rollback

Revert the implementation commit and/or the later product-projection commit by exact commit. Do not reset, restore, stage, or otherwise modify unrelated dirty paths.
