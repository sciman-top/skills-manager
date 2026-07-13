# Implementation Plan: Skill Projection Performance

## Overview

Add fail-safe package-hash reuse for managed Agent skills, split misleading build metrics, and expose projection phase timings while preserving manifest hashes and all existing fallback behavior.

## Architecture Decisions

- Reuse hashes only under the four-part validity contract: verified build signature, managed Junction target, package fingerprint, and `SKILL.md` content hash.
- Store additive cache metadata in the ignored projection manifest; do not introduce a second persistent cache file.
- Keep full hashing as the universal fallback and for all external/system skills.
- Preserve historical Doctor metrics while emitting distinct new build modes.

## Task List

### Phase 1: Contracts

- [x] Add failing projection cache validity and hash-equivalence tests.
- [x] Add failing Doctor/build metric separation tests.

### Checkpoint: Contracts

- [x] Targeted tests fail for the intended missing behavior.

### Phase 2: Package Hash Reuse

- [x] Load eligible cache context from the previous manifest.
- [x] Resolve managed Junction ownership and apply fail-safe cache lookup.
- [x] Persist additive cache metadata after successful projection.
- [x] Emit package hash and projection phase metrics.

### Checkpoint: Projection

- [x] Build succeeds and SkillProjection tests pass.
- [x] Cached and uncached package hashes are identical.

### Phase 3: Metric Semantics

- [x] Emit `build_agent_cache_hit` and `build_agent_full` separately.
- [x] Add thresholds and Doctor test coverage for the new metrics.

### Checkpoint: Metrics

- [x] BuildCache and DoctorPerf tests pass.

### Phase 4: Live Verification

- [x] Run cold and hot `构建生效` samples.
- [x] Verify manifest, Codex provider tables, and bare `codex mcp list`.
- [x] Run the complete project gate and update change evidence.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Stale package hash | High | Require all validity checks; full hash on any mismatch. |
| Cache schema drift | Medium | Version cache metadata and treat unknown versions as misses. |
| Manifest contract change | Medium | Add fields only; preserve schema and existing hashes. |
| Dirty worktree overlap | High | Touch only listed source/tests/generated/evidence files and preserve all import gitlinks. |

## Open Questions

None. The user approved autonomous execution of the recommended design.
