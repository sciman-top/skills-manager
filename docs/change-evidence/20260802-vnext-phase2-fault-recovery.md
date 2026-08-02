# Phase 2 fault recovery evidence

- Task: `SMV-P2-005`.
- Test-only fault points cover before/after stage, before/after replace, before receipt, concurrency drift, and simulated rollback failure.
- Pre-replace failures write nothing; post-replace failures restore before content unless rollback failure is explicitly simulated.
- `rollback_failed` remains truthful and blocks closeout; transaction temp files are cleaned except recovery evidence required by a rollback failure.
