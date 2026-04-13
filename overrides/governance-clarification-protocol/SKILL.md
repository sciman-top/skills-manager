---
name: governance-clarification-protocol
description: Use when governance tasks hit repeated failures or intent mismatch, then switch from direct_fix to bounded clarification and return to execution.
---

1. Default mode is `direct_fix`; do not ask questions first when evidence is sufficient to execute.
2. Trigger clarification when any one is true: same issue repeats failures, symptom/expectation conflict persists, or acceptance criteria are ambiguous.
3. Ask at most 3 high-value questions, in this order: status definition, expected state transition, acceptance sample.
4. Use concise format per question: `当前观察 -> 需要确认 -> 确认后动作`.
5. Record clarification trace in evidence: `issue_id`, `attempt_count`, `clarification_mode`, `questions`, `answers`, `resume_condition`.
6. After clarification is confirmed, switch back to `direct_fix`, clear retry counter for this issue, and continue gates.
7. If clarification is still unresolved after one round, block risky changes and request explicit acceptance baseline.
