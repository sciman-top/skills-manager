# Phase 2 fixture executor evidence

- Task: `SMV-P2-004`.
- Executor runs guards before IO, stages in the target directory, rechecks freshness, atomically replaces, verifies desired hash, and emits a versioned receipt.
- A post-replace failure restores exact before content through the existing atomic-file seam.
- Receipts never auto-promote repository execution to host loading or live acceptance.
