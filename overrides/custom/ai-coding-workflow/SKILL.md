---
name: ai-coding-workflow
description: Complete implementation and maintenance tasks with repository-grounded scope, proportionate verification, and resumable progress. Use for coding execution; use the dedicated review skill for review-only requests.
---

# AI coding workflow

Use this resident entry point to complete the user's authorized coding outcome
with host-native planning and execution. Add a step
only when it resolves current uncertainty or protects affected behavior.

## Scope and depth

First inspect the current diff, affected caller, and repository contract. Freeze
the smallest useful task capsule:

```text
Goal: the complete observable outcome
Exact write set: files and compatibility/side-effect boundaries
Minimum proof: evidence sufficient for the changed behavior
Stop: acceptance of the authorized goal, or a concrete blocker
```

Discover files and commands from the user's outcome, reproduction, and
constraints. Follow the affected entrypoint, callers, and existing checks;
expand context only for unresolved questions. Check APIs against installed
definitions or current official docs rather than remembered APIs or old chats.

Choose the lightest depth that fits the evidence:

- **tiny/direct**: clear local work or a reproducible small bug; inspect, change,
  and run focused proof without a separate plan.
- **normal**: resolve meaningful design uncertainty, then implement verifiable
  slices.
- **high-risk**: security, data, migration, public-contract, deployment, or
  external-state changes require the repository's safeguards and rollback proof.

Diagnosis is separate from risk: use the cheapest reproducer or inspection that
can establish the cause. A passing slice is only a checkpoint; continue the
remaining authorized work until the whole goal is complete.

## Implement and verify

Use existing build and affected verification commands. Add a test only when it
protects required behavior or a real regression. Strict TDD, coverage
thresholds, full suites, independent reviews, extra fixtures, and extra gates
are not routine prerequisites; use them when the user, repository contract, or
affected risk requires them. Never let a skill invent a new gate.

Choose expected results from the requested behavior, including a relevant
failure or boundary case, before judging the implementation. When fixing a bug,
use the original reproducer to verify the fix; do not weaken assertions merely
to obtain a pass. Separate missing inputs, tool/environment failures, and wrong
reasoning before choosing a new attempt or changing model effort.

Before expanding proof, name the affected behavior the current evidence does
not cover. Reuse passed evidence while its inputs and environment remain
applicable; after a change, rerun only invalidated checks. A review suggestion
is actionable only when tied to the requested outcome or a demonstrated
failure. Do not turn optional improvements into prerequisites for completion.

Select observation evidence for the changed behavior only (for example, a
rendered interaction, request-to-effect trace, repeatable projection/rollback,
or migration compatibility check). Project type alone does not authorize live
access or force a full suite. Report missing observation and keep
`repo_verified`, `filesystem_projected`, `host_loaded`, and `live_accepted`
distinct whenever those boundaries are relevant.

## Resume and capabilities

On continue or handoff, reread current status and the changed seam; carry only
the current state, decisions, exact write set, minimum proof, and stop condition.
Keep one primary executor through inspect, implement, and verify for ordinary
work. Delegate only when authorized and independently verifiable. Treat
GPT/Codex and GLM/ZCode as task-fit executors, not stages in a fixed pipeline;
judge a choice by same-task acceptance and verify current help, schema, documentation and actual inputs.

Use a visible matching skill directly. Use `capability-router` only once as a
bounded fallback when an explicitly named skill is not visible or visible
capabilities are genuinely insufficient; it is not routine middleware. Load
specialist methods such as strict TDD or design grilling only when the request,
contract, or current risk calls for them.

Use the target repository's source/generated contract and existing entrypoints.
Do not carry another repository's directory conventions into the current task.
