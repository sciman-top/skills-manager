# Phase 2 apply guard evidence

- Task: `SMV-P2-003`.
- Guard order validates plan, explicit fixture root, no drive root/reparse escape, exact token, target existence/freshness, and desired hash.
- Every failure occurs before executor IO and reports `writes=0`.
- Real repository authorization is intentionally absent; callers cannot convert a semantic recommendation into apply authority.
