---
name: ai-coding-workflow
description: Complete implementation and maintenance tasks with repository-grounded scope, proportionate verification, and resumable progress. Use for coding execution; use the dedicated review skill for review-only requests.
---

# AI coding workflow

Complete the user's authorized outcome under the target repository's contract.
Use the host's native planning, tools and execution capabilities; add a workflow
step only when it resolves current uncertainty or protects affected behavior.

## 1. Scope the current task

Infer the write set and minimum proof from the current diff, affected caller
and repository contract. The user need not supply file paths or test commands.
A small task needs only a sentence, not a form:

```text
Goal: the user's complete observable outcome
Exact write set: source files and compatibility/side-effect boundaries
Minimum proof: evidence sufficient for the requested behavior
Stop: acceptance of the whole authorized goal, or a concrete blocker
```

Choose depth by uncertainty and impact:

- **tiny/direct**: a clear, local, low-risk change, including a reproducible
  small bug. Inspect, change and run focused proof without a separate plan.
- **normal**: resolve meaningful design uncertainty, then implement verifiable
  slices. Clarify behavior conflicts rather than routine implementation details.
- **high-risk**: security, data, migration, public contracts or deployment
  consequences require the target repository's safeguards and rollback proof.

Diagnosis is separate from risk: use the cheapest reproducer or inspection to
establish the cause. A bug alone does not require broader gates or agents.

A passing slice is a checkpoint. Continue remaining authorized work, including
independent work when another action is blocked. Keep outstanding requirements
visible; a plan or one passing test does not complete an implementation goal.

### Select the executor by task fit

Treat GPT/Codex and GLM/ZCode as task-fit executors, not stages in a fixed
pipeline:

- Keep one primary executor through inspect, implement and verify for small or
  ordinary work. Prefer the host/model that has the required workspace and tool
  access with the lowest sufficient reasoning, latency and cost.
- As a starting hypothesis, use GPT/Codex for ambiguous root causes,
  architecture, security or release risk; use GLM/ZCode for bounded mechanical
  or multi-file implementation when its current host path is available. Judge
  the choice by same-task acceptance, correction effort, elapsed time and cost,
  not by model name or generation speed alone.
- Handoff only when the expected gain exceeds the context-transfer cost. Pass a
  task capsule, and require the receiving host to reread current state and the
  changed seam. Check current help, schema, documentation and actual inputs
  before assuming a model, provider, permission, vision or tool capability.

## 2. Implement and verify

Use existing build and affected verification commands. Add a test when it
protects required behavior or a regression not already covered; derive its
assertions from the requirement, not the implementation. Strict TDD, coverage
thresholds, full suites and independent reviews are not routine prerequisites;
apply them when the user, repository contract or affected risk requires them.

Reuse passing proof until its inputs change. Do not add fixtures, gates or
evidence files merely to demonstrate activity. Close out when the overall goal
and required integration are complete, reporting unrelated issues separately.

### Match observation to the changed behavior

Select only evidence relevant to acceptance; project type alone does not
require every check below or authorize live access.

| Changed behavior | Useful observation beyond build/unit checks |
| --- | --- |
| Web UI | Rendered page, affected interaction, viewport and console errors |
| Desktop/input integration | Actual window, focus/input events and affected lifecycle; hardware checks when relevant |
| API/service/bot delivery | Request-to-effect trace; timeout, idempotency and real acknowledgement when delivery is in scope |
| Automation/config/deployment | Repeat execution, partial failure, rollback and target-loaded version when projection is in scope |
| Data/migration | Transaction boundaries, compatibility, recovery and repeat execution on representative disposable data |

Report missing observation and the proven boundary. Distinguish
`repo_verified`, `filesystem_projected`, `host_loaded` and `live_accepted` when
those layers are relevant; do not turn unrelated layers into a mandatory report
or claim that a lower layer proves a higher one.

## 3. Resume and use capabilities selectively

On continue/resume, recover the overall goal, completed and outstanding work,
then check current status and latest evidence. Treat new messages as steering
unless they cancel or replace the goal. A handoff needs only that context,
decisions, write set, minimum proof and Stop; the receiver checks current facts.

Choose tools for missing data, operations or observation. Use an existing
equivalent host tool before adding an MCP service; model ability alone does not
prove tool access. Configuration changes remain within explicit authorization.

Prefer one primary executor; delegate only when authorized and independently
verifiable work makes coordination worthwhile. Load specialist skills only for
a current gap: difficult diagnosis, requested review or another needed method.
Do not reload a verification skill just to repeat already satisfied repository
checks. Use `capability-router` only for a missing specialist capability, never
as a routine preflight.

In skills-manager, consult `docs/product/ai-coding-playbook.md` only for detailed
usage and architecture background. Other repositories do not depend on it.
