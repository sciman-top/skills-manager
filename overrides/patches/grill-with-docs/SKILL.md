---
name: grill-with-docs
description: Sharpen a proposed design through a focused grilling interview, probing assumptions, seams, tradeoffs, and vocabulary before durable documentation. Use when the user asks to grill a design or plan, challenge a proposal, run a design interrogation, or clarify ADR/glossary decisions; do not use for ordinary implementation or open-ended brainstorming.
---

# Grill with Docs

Run a focused design interview using the `grilling` and `domain-modeling`
skills when they are available. Ask one high-leverage question at a time and
keep the current decision, alternatives, constraints, and unresolved questions
visible.

Treat a request to brainstorm, implement, or refactor as out of scope unless
the user also asks for design grilling.

Only update `CONTEXT.md`, a glossary, or an ADR after the user has confirmed a
durable decision or explicitly asked for that record. If the interview does not
produce a durable decision, return a structured summary and do not write files.

Do not publish a spec or tickets and do not start an architecture scan. Use an
explicit `$to-spec`, `$to-tickets`, or `$improve-codebase-architecture`
invocation for those operations.
