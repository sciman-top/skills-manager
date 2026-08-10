# Host-Native Skill Lifecycle Domain Model

**status**: `P6 repo_verified; host_evaluation_partial`
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
| `NativeInvocationTrace` | Observable listed/selected/injected/executed/abstained lifecycle events | Inference from visibility alone |
| `StrictDispatchRequest` | Explicit opt-in request for bounded pre-turn dispatch | Default path for ordinary requests |
| `ProfileCompatibilityView` | Read-only migration representation of legacy membership | Reachability or semantic routing boundary |

## Aggregate boundaries

### `SkillInventory`

Owns canonical identity, source provenance, duplicate resolution, metadata normalization and content freshness. It does not know prompts, profiles or host semantic relevance.

### `HostDiscoveryPlan`

Consumes a `HostCapabilitySnapshot`, canonical inventory, deterministic placement admission and eligibility decisions. It owns budget/headroom calculation and the invariant that admitted items cannot disappear silently.

### `ProjectionTransaction`

Owns explicit plan/apply tokens, expected hashes, atomic writes, receipts and rollback. It cannot assert selection or invocation.

### `InvocationEvidence`

Normalizes host-observable events and truth levels. Missing events remain unknown/partial; evidence cannot relax eligibility or authorize actions.

## Invariants

1. A `CanonicalSkill` is identified independently of profile membership.
2. `SkillEligibilityDecision=deny` cannot be overridden by host semantic confidence.
3. A known-context successful `NativeMetadataPlan` satisfies `enabled_total == kept_total`, `omitted=0` and `truncated=false` for the placement-admitted resident set.
4. `source=config_fallback` cannot be reported as current runtime truth.
5. Listed, selected, injected and executed are distinct states.
6. Strict dispatch requires explicit opt-in and host adjudication.
7. Only explicit placement configuration can change the resident discovery set; profile compatibility data cannot change it, and non-resident skills remain in the portable cold catalog.
8. Planning, projection, host loading and live acceptance are separate truth levels.

## Context relationships

```text
SkillSource -> SkillInventory -> SkillEligibilityDecision
HostCapabilitySnapshot -------------------^

SkillInventory + Eligibility + Snapshot
  -> HostDiscoveryPlan
  -> ProjectionTransaction
  -> host-native adjudication/injection
  -> InvocationEvidence

SkillInventory -> PortableColdCatalog -> explicit cold discovery -> eligibility

ProfileCompatibilityView -> migration/reporting only
StrictDispatchRequest -> HostDiscoveryPlan subset -> host adjudication -> optional injection
```

## Lifecycle states

```text
discovered -> canonical -> eligible -> planned -> projected
                                      -> blocked

projected -> listed -> selected -> injected -> executed
                    -> abstained
                    -> partial/unknown (when host evidence is missing)
```

State advancement always requires evidence from the owning context. Repository projection tests cannot advance an item past `projected`.
