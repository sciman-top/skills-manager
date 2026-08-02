# Phase 1 read-only CLI evidence

- Task: `SMV-P1-008`.
- Added `capability-inventory`/`能力清单` and `rule-audit`/`规则审查` routes.
- `--json` emits one envelope. Without `--out`, config and scanned-rule hashes remain unchanged and write/provider/native/profile counters are zero.
- `--out` atomically writes exactly one explicit report and cannot overwrite a discovered rule document.
- Exit 0 means contract-valid with no deterministic blocker; exit 2 is reserved for profile-enabled deterministic blockers; runtime/input errors use exit 1. Semantic advice never changes the exit to 2.
- No host config, active profile, plugin, MCP, OAuth, or target-repo rule is modified.
