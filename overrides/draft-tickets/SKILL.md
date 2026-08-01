---
name: draft-tickets
description: Draft a dependency-aware tracer-bullet ticket breakdown from a plan, spec, or conversation without creating issues or publishing it. Use when the user asks to split work into tickets, vertical slices, or an implementation sequence for review; do not use for tracker publication.
---

# Draft Tickets

Turn the context already available into a reviewable ticket plan.

## Output

Return a numbered Markdown list. For every ticket include:

- a short title;
- the end-to-end behavior it delivers;
- acceptance criteria that can be verified independently;
- blockers and the reason each blocker is real; and
- the suggested execution order.

Prefer the smallest complete vertical slices that fit one fresh context. Keep
wide mechanical refactors as expand/migrate/contract sequences. Mark uncertain
scope and unresolved dependencies instead of inventing them.

## Side-effect boundary

This is a draft-only skill. Do not call an issue tracker, create labels,
blocking links, ticket files, or other repository files; do not invoke
`to-tickets` or `to-spec`. If the user approves the breakdown and wants it
published, hand off to an explicit `$to-tickets` invocation.
