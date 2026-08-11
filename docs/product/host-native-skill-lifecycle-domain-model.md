# Host-Native Skill Lifecycle Domain Model

**status**: `P6 repo_verified; Desktop representative workflow accepted`
**owner**: `skills-manager-vnext / HostNativeSkillLifecycle`

## Ubiquitous language

| Term | Meaning | Not this |
| --- | --- | --- |
| `SkillSource` | A configured, provenance-bearing root or package that can contain skills | A host-visible skill by itself |
| `CanonicalSkill` | One deduplicated skill identity with name, path, metadata, source and content hash | A profile member or invocation |
| `CanonicalSkillInventory` | The complete compiled set before host/surface eligibility | The initial prompt list |
| `PortableColdCatalog` | Complete read-only metadata and relative entrypoints for explicit cold discovery | A resident projection or automatic dispatcher |
| `HostCapabilitySnapshot` | Effective capability facts for one surface/thread/turn with provenance/freshness | Raw `config.toml` or a global timeless fact |
| `SkillEligibilityDecision` | Deterministic allow/deny/needs-activation outcome for one skill and snapshot | Semantic relevance ranking |
| `NativeDiscoverySet` | Placement-admitted eligible metadata offered to the host under its effective budget | The complete portable cold catalog or a profile |
| `NativeMetadataPlan` | Token-aware plan with enabled/kept/omitted/truncated/headroom evidence | An applied projection |
| `NativeSkillProjectionReceipt` | Atomic apply/rollback evidence for a metadata/body projection | Proof the host selected the skill |
| `HostSkillAdjudication` | Host AI decision to select or abstain based on the full request | Script-owned keyword match |
| `DesktopRepresentativeAcceptance` | Scoped observations that skills are discoverable, reusable and behaviorally consistent in real Desktop tasks | CLI telemetry or a universal correctness claim |
| `ProfileCompatibilityView` | Read-only migration representation of legacy membership | Reachability or semantic routing boundary |

## Aggregate boundaries

### `SkillInventory`

Owns canonical identity, source provenance, duplicate resolution, metadata normalization and content freshness. It does not know prompts, profiles or host semantic relevance.

### `HostDiscoveryPlan`

Consumes a `HostCapabilitySnapshot`, canonical inventory, deterministic placement admission and eligibility decisions. It owns budget/headroom calculation and the invariant that admitted items cannot disappear silently.

### `ProjectionTransaction`

Owns explicit plan/apply tokens, expected hashes, atomic writes, receipts and rollback. It cannot assert selection or invocation.

### `DesktopAcceptance`

Records only the minimum facts from representative Desktop tasks: which skill was visible, reused and how its behavior matched the task contract. It is not a runtime Module, telemetry adapter or automatic gate.

## Invariants

1. A `CanonicalSkill` is identified independently of profile membership.
2. `SkillEligibilityDecision=deny` cannot be overridden by host semantic confidence.
3. A known-context successful `NativeMetadataPlan` satisfies `enabled_total == kept_total`, `omitted=0` and `truncated=false` for the placement-admitted resident set.
4. `source=config_fallback` cannot be reported as current runtime truth.
5. Desktop acceptance checks discoverability, reuse and behavior consistency through real tasks and always states its sample scope.
6. CLI/App Server telemetry is diagnostic only and cannot block or manufacture Desktop acceptance.
7. Only explicit placement configuration can change the resident discovery set; profile compatibility data cannot change it, and non-resident skills remain in the portable cold catalog.
8. Repository verification and Desktop representative acceptance remain separate claims.

## Context relationships

```text
SkillSource -> SkillInventory -> SkillEligibilityDecision
HostCapabilitySnapshot -------------------^

SkillInventory + Eligibility + Snapshot
  -> HostDiscoveryPlan
  -> ProjectionTransaction
  -> host-native selection and skill use
  -> DesktopAcceptance

SkillInventory -> PortableColdCatalog -> explicit cold discovery -> eligibility

ProfileCompatibilityView -> migration/reporting only
```

## Lifecycle states

```text
discovered -> canonical -> eligible -> planned -> projected
                                      -> blocked

projected -> Desktop-discoverable -> reused in a real task -> representative behavior accepted
```

Repository projection tests cannot establish Desktop acceptance. A representative Desktop result proves only its stated sample and must not be generalized to every task or model.
