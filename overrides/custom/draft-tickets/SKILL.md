---
name: draft-tickets
description: Draft dependency-aware tracer-bullet tickets or vertical implementation slices from a plan, spec, or conversation. Return them in chat or write an explicitly requested local draft; do not create issues in an external tracker.
---

# Draft Tickets

Turn the context already available into a reviewable ticket plan.
Identify the source plan and its agreed scope first. If neither the conversation
nor repository context identifies a target, ask for it before drafting tickets.

## Output

Return a numbered Markdown list, or write the same draft to a user-requested
local or repository path. For every ticket include:

- a short title;
- the end-to-end behavior it delivers;
- acceptance criteria that can be verified independently;
- the source/config write set supported by inspection, minimum proof, and stop condition;
- blockers and the reason each blocker is real; and
- the suggested execution order.

Prefer the smallest complete vertical slices that fit one fresh context. Keep
wide mechanical refactors as expand/migrate/contract sequences. Mark uncertain
scope and unresolved dependencies instead of inventing them. Do not create a
standalone ticket for work that has no independent behavior, proof, or proven
dependency role.

Give tickets stable local identifiers and reference those identifiers for
dependencies. Check that every agreed outcome has a ticket and acceptance
check, each dependency exists, and the execution order contains no cycle.
Mark proposed file paths as provisional when implementation discovery is still
needed. Do not force exact paths or time estimates from incomplete evidence.
List only true blocking dependencies; an arbitrary sequence is not a blocker.

## Side-effect boundary

This is a draft-only skill. A user-requested local Markdown file is an allowed
deliverable. Do not call an issue tracker or create remote issues, labels, or
blocking links. If the user wants the breakdown published, treat publication
as a separate task with its own exact tracker, project, and authorization.
