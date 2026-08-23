---
name: grill-with-docs
description: Sharpen a proposed design through a focused grilling interview, probing assumptions, seams, tradeoffs, and vocabulary before durable documentation. Use when the user asks to grill a design or plan, challenge a proposal, run a design interrogation, or clarify ADR/glossary decisions; do not use for ordinary implementation or open-ended brainstorming.
---

# Grill with Docs

Run a focused design interview using the `grilling` and `domain-modeling`
skills when they are available. Ask one high-leverage question at a time and
keep the current decision, alternatives, constraints, and unresolved questions
visible.

## Native-child dispatch invariant

This skill's `multi_turn_user_decision` contract is executed by the native
`design-griller`, never by the parent. Before producing a question, conclusion,
or delegation claim, call the host-native `spawn_agent` tool with the exact
user request, available evidence, and constraints. Continue only after it
returns a non-empty child task or thread identifier; bind that same identifier
to every later `wait` and follow-up call.

If native spawn is unavailable, fails, or returns no identifier, stop with
`native_bridge_unavailable`. Do not call a bare `wait`, simulate a child,
continue the interview in the parent, or replace the interview with a one-shot
analysis, report, or summary. Evidence gathering informs each child question;
it never substitutes for the child.

Treat a request to brainstorm, implement, or refactor as out of scope unless
the user also asks for design grilling.

Only update `CONTEXT.md`, a glossary, or an ADR after the user has confirmed a
durable decision or explicitly asked for that record. If the interview does not
produce a durable decision, return a structured summary and do not write files.

Do not publish a spec or tickets and do not start an architecture scan. Use an
explicit `$to-spec`, `$to-tickets`, or `$improve-codebase-architecture`
invocation for those operations.
