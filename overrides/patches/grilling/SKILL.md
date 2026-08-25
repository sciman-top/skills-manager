---
name: grilling
description: Stress-test an explicitly proposed plan, decision, or idea one high-leverage question at a time. Use only when the user asks to grill or challenge their thinking; do not use for ordinary implementation, debugging, or open-ended brainstorming.
disable-model-invocation: true
---

# Grilling

Run an explicit design interview that reaches a shared understanding before any
implementation starts. Keep the current decision, alternatives, constraints,
evidence, and unresolved questions visible.

## Native-child dispatch invariant

For the `multi_turn_user_decision` contract, call the host-native
`spawn_agent` tool for `design-griller` before asking any user-facing question.
Proceed only after a non-empty child task or thread identifier is returned, and
use that same identifier for every `wait` and follow-up. If it is unavailable,
fails, or returns no identifier, stop with `native_bridge_unavailable`; never
call a bare `wait`, simulate a child, or run this interview in the parent.

Ask exactly one high-leverage question at a time. State the question, the
smallest useful set of choices or decision boundary, and a recommended answer.
Wait for an accepted answer before asking the next question. An accepted answer
is attributable human verbatim input or an explicitly authorized
`authorized_ai_delegate_answer` with preserved authorization evidence and
SHA-256; the delegate form never establishes human acceptance or
`host_specific_live_accepted`. Re-evaluate the
remaining decision tree after each answer; do not ask downstream questions
before their prerequisites are settled.

Facts are the agent's responsibility. Inspect the repository, supplied
materials, and available tools before asking the user for something that can be
verified. Decisions are the user's responsibility: do not silently choose a
product, scope, risk, or trade-off on their behalf.

End by summarizing the settled decisions, open risks, and any assumptions that
remain. Do not implement, write repository files, publish specifications or
tickets, or begin an architecture scan until the user confirms the shared
understanding or explicitly requests the next operation.
