# Agent Rule Governance 9.57

## Scope and boundary

- repository: `skills-manager`
- frozen baseline: `4addb13e201efb29e404b1c086f7cd4b48293911`
- task branch: `codex/agent-rule-governance-9.56`
- write-set: `AGENTS.md` and this evidence file; `CLAUDE.md` remains the verified import-only wrapper
- release review: `rule_release=9.57 / project_contract_version=2.0 / coordination_schema=2.3`
- semantic basis: Claude Code's current official memory documentation permits imports up to five hops; the project WHERE/HOW contract itself is unchanged
- exclusions: no product/runtime/schema/data/dependency/auth/provider/secret/MCP/account/process/hosted-UI change

## Verification ledger

- wrapper: `CLAUDE.md` verified as the import-only `@AGENTS.md` wrapper, no BOM; control-repo `--require-all` target audit passed for all 9 isolated targets
- build: `build.ps1` passed and generated-sync check passed
- test: Pester 4.10.1 passed 454 unit tests and 12 E2E tests
- contract/invariant: strict doctor passed; dependency baseline passed; skill integrity verified 108 skills using a task-local copy of the parent `agent/` fixture, removed after verification
- hotspot/full: `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` passed
- diff hygiene and five-axis review: passed with no Critical or Required finding
- inherited remote blocker: governance PR #2 remains dependent on the pre-existing GitHub Windows runner hidden-directory failure; repair PR #3 is frozen at `clarify_required` after the same failure recurred, despite local full gates passing
- Git publication: 9.57 content is not yet pushed at this capture point; branch name remains the existing `codex/agent-rule-governance-9.56` to avoid replacing PR #2 history

## Compatibility and rollback

- compatibility: content-release review marker only; repository commands, invariants, external behavior, data formats, and wrapper loading shape remain unchanged
- rollback: revert only `AGENTS.md` and this evidence file from the task commit; do not reset, clean, or include unrelated local history

## Completion boundary at capture

- `repo-side completed=true`
- `published branch=false`
- `default-branch effective=false`
- `hosted/manual accepted=false`
- `fully completed=false`
