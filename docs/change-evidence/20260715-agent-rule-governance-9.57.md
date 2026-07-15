# Agent Rule Governance 9.57

## Scope and boundary

- repository: `skills-manager`
- frozen baseline: `4addb13e201efb29e404b1c086f7cd4b48293911`
- refreshed default-branch baseline: `e3456a8862e72b1d5fb64b66806f749caca256be` (PR #3 merge commit)
- task branch: `codex/agent-rule-governance-9.56`
- write-set: `AGENTS.md` and this evidence file; `CLAUDE.md` remains the verified import-only wrapper
- release review: `rule_release=9.57 / project_contract_version=2.0 / coordination_schema=2.3`
- semantic basis: Claude Code's current official memory documentation permits imports up to five hops; the project WHERE/HOW contract itself is unchanged
- exclusions: no product/runtime/schema/data/dependency/auth/provider/secret/MCP/account/process/hosted-UI change

## Verification ledger

- wrapper: `CLAUDE.md` verified as the import-only `@AGENTS.md` wrapper, no BOM; control-repo `--require-all` target audit passed for all 9 isolated targets
- build: `build.ps1` passed and generated-sync check passed
- test: Pester 4.10.1 passed 455 unit tests and 12 E2E tests after incorporating the default-branch hidden-directory regression repair
- contract/invariant: strict doctor passed; dependency baseline passed; skill integrity verified 108 skills using a task-local copy of the parent `agent/` fixture, removed after verification
- hotspot/full: `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` passed
- diff hygiene and five-axis review: passed with no Critical or Required finding
- inherited remote blocker: resolved by merged repair PR #3; `3e2afa613615a4ac446c712e32edaedc380612fb` is an ancestor of fresh `origin/main=e3456a8862e72b1d5fb64b66806f749caca256be`
- Git publication: the 9.57 content is published at `c5a586215db30725580cfd3f035f4e5c65ea7298`; local merge commit `764f1f71e6b7edc8c01d73e338da89fa541af361` incorporates fresh default-branch fixes without rebasing or force-pushing; final hosted checks remain pending for the next published head

## Compatibility and rollback

- compatibility: content-release review marker only; repository commands, invariants, external behavior, data formats, and wrapper loading shape remain unchanged
- rollback: revert only `AGENTS.md` and this evidence file from the task commit; do not reset, clean, or include unrelated local history

## Completion boundary at capture

- `repo-side completed=true`
- `published branch=true`
- `default-branch effective=false`
- `hosted/manual accepted=false`
- `fully completed=false`
