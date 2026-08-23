---
name: grilling
description: Stress-test an explicitly proposed plan, decision, or idea one high-leverage question at a time. Use only when the user asks to grill or challenge their thinking; do not use for ordinary implementation, debugging, or open-ended brainstorming.
---

# Grilling

Run an explicit design interview that reaches a shared understanding before any
implementation starts. Keep the current decision, alternatives, constraints,
evidence, and unresolved questions visible.

Ask exactly one high-leverage question at a time. State the question, the
smallest useful set of choices or decision boundary, and a recommended answer.
Wait for the user's answer before asking the next question. Re-evaluate the
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
