---
name: systematic-debugging
description: Diagnose a concrete bug, failing test, build break, or unexpected behavior from evidence before changing code. Use when an observed failure needs root-cause analysis; do not invoke for straightforward implementation with no failure.
---

# Systematic debugging

Find the smallest causal explanation for the observed failure, then make the
smallest change that removes that cause.

1. Record expected behavior, observed behavior, and the cheapest command or
   inspection that reproduces the difference.
2. Read the failing path and its immediate inputs before proposing a fix.
3. Form one falsifiable cause at a time and use the cheapest discriminating
   evidence. Do not launch broad audits, full suites, or external research
   unless the current evidence cannot distinguish the cause.
4. Fix the causal seam. Add a focused regression only when it protects the
   observed failure mode and is not already covered.
5. Re-run the reproducer or affected test. Escalate to a wider gate only when
   the change crosses a shared, security, data, migration, or public-contract
   boundary required by the repository.

Stop when the cause is explained and the focused evidence passes. Do not add a
debugging framework, evidence artifact, compatibility layer, or generalized
abstraction unless the current failure requires it. After two failed attempts
on the same issue, pause and clarify the disputed semantics or acceptance
criterion instead of repeating speculative fixes.
