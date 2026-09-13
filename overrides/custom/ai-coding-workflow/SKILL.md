---
name: ai-coding-workflow
description: Complete implementation and maintenance tasks with repository-grounded scope, proportionate verification, and resumable progress. Use for coding execution; use the dedicated review skill for review-only requests.
---

# AI coding workflow

Complete the user's authorized outcome under the target repository's contract
and host policy. Reuse existing authorization; ask only for required missing
input. If this skill causes a pause, name the instruction and unresolved input.

## 1. Scope the current task

Read applicable project rules, current status/diff, the relevant entrypoint and
nearest tests. Infer files and verification commands when the user only knows
the desired behavior. Do not invent a target for an unanchored reference such
as "this file". Separate existing changes from this task's write set.

Write or infer the following; a small task needs only a sentence, not a form:

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

Diagnosis is separate from risk: reproduce an observed failure and establish
its cause before editing; a bug alone does not require broader gates or agents.
Use `systematic-debugging` when the cause needs investigation. After two failed
attempts on the same issue, summarize facts, rejected hypotheses and attempts,
then resolve missing input or disputed acceptance before trying another patch.

A slice is a checkpoint, not a replacement for the overall goal. After its
proof passes, continue remaining authorized work. Keep outstanding requirements
visible across slices and resumes; do not silently reduce implementation to a
plan, documentation, or one passing test. A blocked action does not block other
independent authorized work. Report the unresolved remainder when it needs user
input or an unavailable capability; do not claim the whole goal is complete.

## 2. Implement and verify

Edit the repository's source of truth, rebuild generated outputs when required,
and preserve unrelated changes. Add structure only for the requested feature or
demonstrated failure; prefer existing interfaces.

Use the lowest sufficient proof required by the repository, in dependency
order: build, affected tests, contracts/invariants, then relevant hotspot checks.
Do not run a full suite merely because source changed. Derive assertions from
required behavior; do not weaken them to fit the implementation. For a bug,
show the same regression failing before and passing after when feasible.

Inspect the final diff and run `git diff --check` when applicable. Use
`verification-before-completion` for evidence-backed completion claims. For
material risk, use authorized independent review of requirements, diff and
tests; require concrete triggers, impact and evidence. Reuse passing proof until
its inputs change. Close out when the overall goal and required integration are
complete, reporting unrelated new issues separately.

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

Reuse existing logs, tests and tools. If required observation is unavailable,
report missing evidence and the proven lower boundary. A mock, health check or
HTTP 200 cannot substitute for the actual user path.

Report changed behavior, verification and remaining limitations. Distinguish
`repo_verified`, `filesystem_projected`, `host_loaded` and `live_accepted` when
those layers are relevant; do not turn unrelated layers into a mandatory report
or claim that a lower layer proves a higher one.

## 3. Resume and use capabilities selectively

On continue/resume, recover the overall goal, completed and outstanding work,
then check current status and latest evidence. Treat new messages as steering
unless they cancel or replace the goal. A handoff needs only that context,
decisions, write set, minimum proof and Stop; the receiver checks current facts.

Choose available tools by the task, not model names. Verify unstable API or
host behavior against current source/help or authoritative documentation.
MCP is optional: use relevant connected tools for needed evidence or authorized
integration, without configuring services or switching providers as a side
effect. Model ability alone does not prove tool access or host support.

Prefer one primary executor; delegate only when authorized and independently
verifiable work makes coordination worthwhile. Load specialist skills for the
current need, not as a fixed chain. Use `capability-router` only for a missing
specialist capability, never as a routine preflight.

In skills-manager, consult `docs/product/ai-coding-playbook.md` only for detailed
usage and architecture background. Other repositories do not depend on it.
