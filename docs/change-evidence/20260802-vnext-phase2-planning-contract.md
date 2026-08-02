# vNext Phase 2 planning contract evidence

- Task: `SMV-P2-001`.
- P1 closeout is the entry evidence; P2 is limited to fixture-only transactional explicit apply.
- Seven maximum-reasonable slices cover plan contract, guards, executor, failure recovery, CLI/MCP compatibility, and acceptance.
- Planning tests now follow the declared current phase while preserving explicit P0/P1 historical validation.
- Real global/project rules, host config/profile, plugin/MCP native state, provider calls, commit, and push remain outside the authorized write set.
- Any executor introduced by P2 must reject non-fixture roots by default; repo-side completion cannot claim host loading or live acceptance.
