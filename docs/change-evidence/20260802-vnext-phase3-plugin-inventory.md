# Phase 3 plugin inventory snapshot adapter

## Result

- `SMV-P3-002 = done` at repo/fixture scope.
- official/personal/workspace snapshots are caller-labelled and converted to typed plugin descriptors without reading host config or executing native commands.
- Same-name personal/workspace entries retain distinct source/scope truth.

## Evidence

- Combined new-feature matrix: 21 passed, 0 failed.
- Generated CLI `plugin-inventory`: exit 0, pass=true, descriptors=3.
- Snapshot hashes remained unchanged; counters are writes=0, provider_calls=0, native_mutations=0.

## Boundary and rollback

This is snapshot adaptation, not current host discovery or load acceptance. Remove `ConvertFrom-CodexPluginInventorySnapshot`, its command route, tests and fixture, then rebuild; do not change plugin config/cache.
