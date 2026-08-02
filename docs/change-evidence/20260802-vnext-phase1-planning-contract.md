# vNext Phase 1 planning contract evidence

## Scope and truth boundary

- Task: `SMV-P1-001`.
- Result target: establish executable P1 planning truth; this evidence does not claim P1 product implementation.
- Allowed writes: P1 spec/manifest/plan/todo/verifier/tests/entry docs/evidence only.
- Prohibited: global or target-repo rule writes, host/profile/config changes, provider calls, native plugin/MCP mutation, commit/push.
- Highest possible state in P1: `repo_verified`; `host_loaded` and `live_accepted` require separate fresh-session or real-workflow evidence.

## Official and reference basis

- Codex manual refreshed on 2026-08-02 with the repository-approved `openai-docs` manual helper.
- Adopted: persistent `AGENTS.md` guidance, progressive-disclosure skills, installable plugin bundles, and MCP/connector external-data/action surfaces remain distinct and complementary.
- Adapted: inventory records runtime/reference/official/host/candidate truth separately; installed, enabled, authorized, fresh-session loaded, and live accepted are not collapsed.
- Rejected: a new capability runtime, central target registry, cross-repo rule synchronizer, daemon/database, or prose-only enforcement layer.
- `openai/codex` revision: `61a44880a85d2fd0d8770908dea5733495e571c8`.
- `openai/plugins` revision: `11c74d6ba24d3a6d48f54a194cd00ef3beea18f9`.

## Planning design

- Nine maximum-reasonable slices separate planning, contracts, inventory, discovery, diagnostics, semantic coverage, repo evidence, CLI, and acceptance.
- `tasks/plan.md` declares `current_phase`; the verifier derives the default phase manifest/spec without a registry.
- Explicit `-ManifestPath` and `-SpecPath` preserve historical P0 validation without mixing P0 tasks into the active P1 todo.
- Deterministic diagnostics may block only when a profile opts in; semantic advice is always recommendation-only.
- P1 is zero-provider, zero-native-mutation, zero-profile-change, and zero-write except an explicit report `--out` introduced by P1-008.

## Verification and rollback

Verification is recorded after the manifest status is updated to `done`:

1. build generated source;
2. run `ProductPlanning.Tests.ps1`;
3. run the planning verifier in current P1 and explicit historical P0 modes;
4. run the repository full local quality gate.

Rollback removes only P1 planning files and restores current-phase routing and entry-document text. P0 manifests/evidence and unrelated working-tree changes are not reverted.
