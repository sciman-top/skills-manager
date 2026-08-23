---
name: grill-me
description: Start an explicit, read-only design interview through the native design-griller subagent. Use only when the user explicitly asks to grill, challenge, or interrogate a proposed plan or decision - including compound requests that also ask for document or evidence grounding, which prefer cold-discovering grill-with-docs; do not use for ordinary implementation, debugging, or brainstorming.
disable-model-invocation: true
---

# Grill Me

This is the thin `core` entry for an explicit design interview. Do not perform
the interview in the parent task and do not change a shared skill profile.

A request that combines interrogation with evidence gathering (official docs,
community projects, best practices) is still an interview. Never answer it with
a one-shot analysis, report, or summary with trailing questions: that collapse
is forbidden regardless of whether this skill or the cold `grill-with-docs`
closure serves the request. When the interrogation must be grounded in external
evidence, route through cold discovery to `grill-with-docs` (closure:
grill-with-docs + domain-modeling + grilling) instead of spawning the plain
design-griller; gather evidence per question, never instead of asking it.

1. Use the host-native child-spawn tool to start the custom `design-griller`
   with the user's proposal, stated constraints, and exact request to grill it.
   A delegation is valid only when that tool returns a non-empty child task or
   thread identifier.
2. Keep the parent task as the user-facing conversation. Return the child's
   single question to the user only after receiving its result, then route each
   user answer back to that exact child identifier until it emits its decision
   capsule. A `wait` call without that identifier is not a delegation receipt.
3. The child may ask only decisions that can materially change the proposal.
   It must remain read-only: no repository edits, implementation, tickets,
   ADRs, host configuration, profile changes, or side effects.
4. When the child closes, return its settled decisions, open risks, and
   assumptions to the parent task. Resume normal `core` work; do not preserve
   a `design` profile or start another child unless the user asks again.

If the native `design-griller` is unavailable, the child-spawn tool fails, or
no child identifier/result is returned, report `native_bridge_unavailable` and
explain the missing bridge evidence. Do not silently fall back to shared-profile
switching, simulate a child question, or claim that delegation happened. Only
offer `codex exec --ephemeral` when the user explicitly asks for a no-trace CLI
fallback.
