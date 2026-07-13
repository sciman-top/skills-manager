# Skill Projection Performance Design

## Goal

Reduce the normal cache-hit `构建生效` path below the current `apply_targets` warning threshold without weakening package-hash correctness or changing the projection manifest's observable hashes.

## Observed Bottleneck

`apply_targets` reconciles managed Junctions and then recomputes SHA-256 package hashes for 115 skills backed by roughly 13,486 files / 83 MB. Recent runs take 13-16 seconds. `build_agent` also mixes 6-20 ms cache hits with 11-14 second full builds under one metric.

## Design

### Package Hash Reuse

The projection manifest remains the persisted package-hash catalog. A cached hash is eligible only when all of these checks pass:

1. The caller supplies an Agent build signature verified during the current build/apply flow.
2. The previous manifest records the same build signature and cache schema.
3. The projected directory is a Junction whose resolved target is inside `managed_source_path`.
4. The current per-package directory fingerprint matches the previous manifest.
5. The current `SKILL.md` content hash matches the previous manifest.
6. Every cached hash field has a valid SHA-256 representation.

Any missing, malformed, or mismatched value falls back to the existing full package hash. Non-managed and `.system` skills always use the full hash path. The manifest keeps `package_hash` unchanged and adds cache metadata as backward-compatible fields.

The hot-path metric means every managed skill was a cache hit with zero managed misses. Mandatory `.system` full hashes remain counted in the metric data but do not misclassify the managed path as a cold build. Unchanged projection Junctions are reconciled silently; aggregate phase metrics remain the audit record.

### Metrics

Add aggregate phase metrics for target-link application, managed-link reconciliation, projection planning, package hashing, TOML rendering, and persistence. Emit cache hit/miss counts with the package-hash phase.

New build events use separate `build_agent_cache_hit` and `build_agent_full` metric names. Historical `build_agent` remains readable by Doctor for compatibility.

### Failure Behavior

Cache reads are advisory. Invalid cache data never blocks projection and never produces an empty hash; it triggers full hashing. Cache metadata is written only after a successful, non-dry-run projection. Existing transactional Agent rollback and TOML backup behavior remain unchanged.

## Verification

- Unit tests prove cache hit, directory-fingerprint miss, content-hash miss, unmanaged-directory fallback, corrupt/legacy manifest fallback, and build metric separation.
- Cached and uncached plans must produce identical `package_hash` values.
- A cold live run seeds cache metadata; a second live run demonstrates the hot path and records phase timings.
- The fixed gate order remains `build -> test -> contract/invariant -> hotspot`.

## Rollback

Restore the touched `src/` and test files, rebuild `skills.ps1`, and run `构建生效`. Additive manifest cache fields can remain; older code ignores them and recomputes hashes.
