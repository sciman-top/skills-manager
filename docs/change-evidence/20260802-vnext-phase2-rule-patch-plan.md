# Phase 2 RulePatchPlan evidence

- Task: `SMV-P2-002`.
- Added a single-target v1 plan, deterministic IDs/hashes, bounded unified diff, schema, and pure validator.
- Desired content must be `explicit_user_input` or `reviewed_file`; `semantic_recommendation` is rejected.
- Sensitive content is rejected before a plan can be serialized or applied.
- Planner performs no file IO; PowerShell 7 is primary and Windows PowerShell 5.1 receives parse/plain-object smoke only.
