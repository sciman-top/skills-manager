# Phase 1 read-only capability inventory evidence

- Task: `SMV-P1-003`.
- Inventory accepts explicit descriptors and supplied config objects; it performs no fetch, clone, install, provider, native, profile, or file-write action.
- Same-name descriptors remain separate by `truth_origin` and source. Decisions are `canonical`, `duplicate`, `alternative`, or `conflict`; no input is deleted.
- Historical/deprecated reference truth is never promoted to runtime/official active truth.
- Sensitive MCP config values are redacted in converted components.
- Verification: targeted Pester, build/generated sync, planning gate, and full gate before task completion.
