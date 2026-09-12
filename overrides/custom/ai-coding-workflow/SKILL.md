---
name: ai-coding-workflow
description: Complete implementation and maintenance tasks with repository-grounded scope, proportionate verification, and resumable progress. Use for coding execution; use the dedicated review skill for review-only requests.
---

# AI coding workflow

Follow the target repository's engineering contract and the user's intended
outcome. User instructions take precedence over this skill's guidance, within
host policy. Reuse authorization already given for the current scope, including
external actions; ask only for missing required authorization or information
that materially changes the outcome. If this skill causes a pause, identify the
exact instruction and unresolved input instead of requesting routine approval.

Prefer one primary executor through inspection, implementation and validation.
Delegate only when authorized, slices can be independently verified, writes do
not conflict, and coordination costs less than serial work.

## 1. Scope the current task

Read applicable project rules, current status/diff, the relevant entrypoint and
nearest tests. Infer files and verification commands when the user only knows
the desired behavior. Do not invent a target for an unanchored reference such
as "this file". Separate existing changes from this task's write set.

Write or infer the following; a small task needs only a sentence, not a form:

```text
Goal: observable outcome
Context: current repository, caller and relevant evidence
Constraints: write set, compatibility and side-effect boundaries
Success: behavior and minimum sufficient verification
Stop: where the current task ends
```

Choose depth by uncertainty and impact:

- **tiny/direct**: a clear, local, low-risk change, including a reproducible
  small bug. Inspect, change and run focused proof without a separate plan.
- **normal**: resolve meaningful design uncertainty, then implement a bounded
  slice. Clarify behavior conflicts rather than routine implementation details.
- **high-risk**: security, data, migration, public contracts or deployment
  consequences require the target repository's safeguards and rollback proof.

Diagnosis is separate from risk: reproduce an observed failure and establish
its cause before editing; a bug alone does not require broader gates or agents.
Use `systematic-debugging` when the cause needs investigation. After two failed
attempts on the same issue, summarize facts, rejected hypotheses and attempts,
then resolve missing input or disputed acceptance before trying another patch.

## 2. Implement and verify

Edit the target repository's source of truth and rebuild generated outputs
when required. Directory names alone do not identify generated or third-party
content. Add structure only when the current requested feature or demonstrated
failure needs it; prefer existing interfaces. Preserve unrelated changes and
secrets, and keep external actions within the authorized scope.

Use the lowest sufficient proof required by the repository, in dependency
order: build, affected tests, contracts/invariants, then relevant hotspot checks.
Do not run a full suite merely because source changed. Derive assertions from
required behavior; do not weaken them to fit the implementation. For a bug,
show the same regression failing before and passing after when feasible.

Inspect the final diff and run `git diff --check` when applicable. Use
`verification-before-completion` for evidence-backed completion claims. For
material risk, use authorized independent review of requirements, diff and
tests; require concrete triggers, impact and evidence. Stop after the agreed
proof and required closeout, reporting independent new issues separately.

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
HTTP 200 cannot substitute for the actual user path. Add instrumentation only
when current acceptance needs it and the change is within scope.

Report changed behavior, verification and remaining limitations. Distinguish
`repo_verified`, `filesystem_projected`, `host_loaded` and `live_accepted` when
those layers are relevant; do not turn unrelated layers into a mandatory report
or claim that a lower layer proves a higher one.

## 3. Resume and use capabilities selectively

On continue/resume, re-read current status, changed code and latest proof.
Reuse still-valid evidence; rerun only checks invalidated by changed inputs or
environment. When history is misleading, hand off a short capsule containing
Goal, current revision/evidence, decisions, write set, minimum proof and Stop.
The receiver checks current repository facts before acting.

Choose available tools by the task, not model names. Verify unstable API or
host behavior against current source/help or authoritative documentation.
MCP is optional: use relevant connected tools for needed evidence or authorized
integration, without configuring services or switching providers as a side
effect. Model ability alone does not prove tool access or host support.

Use specialist skills only for their current purpose: review-only requests use
`code-review-and-quality`; Windows PowerShell automation uses
`custom-powershell-windows-automation`. Use `capability-router` only when visible
capabilities are insufficient and cold discovery or validation is needed, not
as a per-task preflight. Do not chain all workflow skills for every task.

In skills-manager, consult `docs/product/ai-coding-playbook.md` only for detailed
usage and architecture background. Other repositories do not depend on it.
