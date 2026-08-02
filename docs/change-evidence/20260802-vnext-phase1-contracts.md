# Phase 1 capability/rule contract evidence

## Scope

- Task: `SMV-P1-002`.
- Added only plain-object v1 constructors, validators, JSON Schemas, generated build inputs, and contract tests.
- No file discovery, host inventory, provider call, native command, profile change, or rule write is performed by these domain modules.

## Invariants

- `CapabilityDescriptor`, `RuleDocument`/`RuleFinding`, and `RuleResponsibility` remain separate contracts linked only by evidence/source references.
- Stable IDs derive from normalized identity fields; arrays emitted by constructors have deterministic ordering where order has no contract meaning.
- `semantic` findings with `blocking=true` fail contract validation.
- `not_applicable` responsibility coverage requires a recovery condition.
- Verification states do not auto-promote from repository evidence to `host_loaded` or `live_accepted`.

## Verification

- Build and generated-sync.
- Pester contract suite including valid/invalid/stability/no-IO tests.
- Bounded Windows PowerShell 5.1 parse and plain-object construction smoke; PowerShell 7 remains the primary runtime.
- Full repository gate before task status advances.

## Rollback

Remove the three new Domain modules, schemas, tests, and build entries, then rebuild `skills.ps1`. No user config or host state requires rollback.
