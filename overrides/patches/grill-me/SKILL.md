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

## Native-child dispatch invariant

Before producing a user-facing question, conclusion, or delegation claim for a
`multi_turn_user_decision` workflow, call the host-native `spawn_agent` tool
for the custom `design-griller`. Pass the user's proposal, stated constraints,
and exact request to grill it. A delegation is valid only when that tool returns
a non-empty child task or thread identifier. Do not call `wait` until that
identifier exists, and pass the same identifier to every later `wait` or
follow-up call.

If `spawn_agent` is unavailable, fails, or returns no identifier, stop with
`native_bridge_unavailable` and name the missing spawn evidence. Do not call a
bare `wait`, simulate a child question, claim that a child was started, or
silently fall back to a parent or shared-profile interview.

1. Keep the parent task as the user-facing conversation. Return the child's
   single question to the user only after receiving its result, then route each
   accepted answer back to that exact child identifier until it emits its
   decision capsule. An accepted answer is either attributable human verbatim
   input or an explicitly authorized `authorized_ai_delegate_answer`; the latter
   must retain authorization evidence and its SHA-256 and never counts as human
   acceptance or `host_specific_live_accepted`. Before every later `followup_task`, the parent must call
   `New-ExecutionAdmissionSuccessor` with the predecessor admission/plan,
   current revalidation, original request, and the attributable answer;
   it must relay the returned successor `admission_id` and `plan_id`. A failed
   guard stops the interview. This is a parent-side soft guard, not evidence
   that the host supplied a hard pre-followup hook.
2. The child may ask only decisions that can materially change the proposal.
   It must remain read-only: no repository edits, implementation, tickets,
   ADRs, host configuration, profile changes, or side effects.
3. When the child closes, return its settled decisions, open risks, and
   assumptions to the parent task. Resume normal `core` work; do not preserve
   a `design` profile or start another child unless the user asks again.

Only offer `codex exec --ephemeral` when the user explicitly asks for a
no-trace CLI fallback.
