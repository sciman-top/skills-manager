# Implementation Plan: Skill Profile Budget And Routing

## Overview

Raise the repository profile budget to 10000 with a realistic plugin reserve,
route selected orphaned skills through narrow task profiles, and expose profile
reachability in the projection manifest.

## Task 1: Reachability Contract

**Acceptance criteria:**

- Profile-excluded entries retain `decision = profile_excluded`.
- Entries used by another profile report `routed_elsewhere` and profile names.
- Entries used by no profile report `unrouted` and an empty profile list.

**Verification:** targeted `SkillProjection.Tests.ps1` test fails before and
passes after implementation.

## Task 2: Budget And Profile Configuration

**Acceptance criteria:**

- Limit is 10000 and external reserve is 3500.
- `python`, `mcp`, `review`, `marketing`, and `video` are selectable.
- Every configured profile passes the live plugin-aware budget.
- Routing policy no longer advertises an unreachable `agent-browser` operator.

**Verification:** profile listing, projection plan, integrity and routing checks.

## Task 3: Generated And User-Facing Surfaces

**Acceptance criteria:**

- Help and README list all selectable profiles.
- Generated `skills.ps1` matches `src/`.
- Change evidence records commands, dirty-worktree boundary, and rollback.

**Verification:** generated-sync and full local quality gate.

## Task 4: Lean Budget And Behavior Evidence

**Acceptance criteria:**

- `default` and `coding` have a 7500 effective ceiling under the global 10000
  hard limit.
- Every configured profile has a fresh Codex prompt probe.
- A 12-case lean-versus-strict corpus can run without model calls by default
  and can explicitly collect GPT-5.6 routing behavior and usage.
- Runtime docs state that profile changes apply to new tasks, not hot-loaded
  running tasks.

**Verification:** focused Pester red-green tests, all-profile prompt probe,
24-call read-only A/B report, and the full local quality gate.

## Dependencies And Risks

- Task 2 depends on Task 1 defining the additive manifest contract.
- Plugin metadata can continue growing; the 3500 reserve and per-profile
  headroom reduce, but do not eliminate, that external drift risk.
- Existing import and audit changes are user-owned and remain outside rollback.
