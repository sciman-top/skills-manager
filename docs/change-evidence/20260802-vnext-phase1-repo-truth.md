# Phase 1 repository truth integration evidence

- Task: `SMV-P1-007`.
- The adapter accepts current TargetAudit `repo-scan` facts and verifies bounded file paths plus observed build/test command strings.
- It does not execute declared commands. `verified`, `absent`, `out_of_root`, `not_observed`, `unknown`, and `not_checked` remain distinct.
- Recommendation output is explicitly rejected as an evidence source, preventing advisor self-proof.
- Target repository files remain unchanged; no host/provider/native/profile action occurs.
