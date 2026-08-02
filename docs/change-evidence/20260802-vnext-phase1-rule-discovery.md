# Phase 1 host-profile rule discovery evidence

- Task: `SMV-P1-004`.
- Discovery is bounded to the explicit repo root/current directory and optional user rule root; it does not enumerate drives or configured target repositories.
- Codex candidates implement the official per-level first-existing selection and combined byte budget as a repository-side model; `load_verification` remains `not_run`.
- Claude scans only explicit `CLAUDE.md` candidates. Project precedence is `inferred`/unknown without a host probe and is not copied from Codex.
- Input file hashes remain unchanged; provider/native/write counters remain zero.
- Rollback removes the application module/profile/tests/build entry and rebuilds generated source. No discovered rule file changes.
