# Phase 1 deterministic rule diagnostics evidence

- Task: `SMV-P1-005`.
- Checks are file/encoding/budget/wrapper/exact-duplicate/scope-leak/prose-enforcement facts only; rule command text is never executed.
- Finding IDs and ordering are stable. A finding blocks only when its deterministic code is listed by the supplied profile.
- `not_applicable` is not synthesized to hide missing evidence; semantic judgments remain outside this module.
- Verification uses positive/negative fixtures, zero-command/write/provider/native counters, generated sync, and full gate.
