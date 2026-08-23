---
name: grill-me
description: Start an explicit, read-only design interview through the native design-griller subagent. Use only when the user explicitly asks to grill, challenge, or interrogate a proposed plan or decision; do not use for ordinary implementation, debugging, or brainstorming.
disable-model-invocation: true
---

# Grill Me

This is the thin `core` entry for an explicit design interview. Do not perform
the interview in the parent task and do not change a shared skill profile.

1. Spawn the native `design-griller` custom subagent with the user's proposal,
   stated constraints, and the exact request to grill it.
2. Keep the parent task as the user-facing conversation. Return the child's
   single question to the user, then route each user answer back to the same
   child until it emits its decision capsule.
3. The child may ask only decisions that can materially change the proposal.
   It must remain read-only: no repository edits, implementation, tickets,
   ADRs, host configuration, profile changes, or side effects.
4. When the child closes, return its settled decisions, open risks, and
   assumptions to the parent task. Resume normal `core` work; do not preserve
   a `design` profile or start another child unless the user asks again.

If the native `design-griller` is unavailable, report
`native_bridge_unavailable` and explain the missing projection. Do not silently
fall back to shared-profile switching. Only offer `codex exec --ephemeral` when
the user explicitly asks for a no-trace CLI fallback.
