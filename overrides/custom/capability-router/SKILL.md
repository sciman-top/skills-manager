---
name: capability-router
description: Read-only cold discovery and deterministic validation for local skills. Use only when host-native visible metadata is insufficient, cross-directory discovery is needed, or a host-selected candidate needs containment/availability validation. Host AI owns semantic selection; do not use as a normal preflight.
---

# Capability router

This is a narrow fallback, not a normal task preflight and not a second semantic router.

## Cold discovery

Use only in either of these cases:

- the user explicitly names a local skill that is absent from the current visible
  metadata; or
- the host has determined that no visible native skill is a sufficient semantic
  match for the complete request.

The second case is a bounded fallback, not a blanket preflight. Pass the
complete request and at most two host-chosen domain hints. The router retrieves
descriptions; the host still makes the semantic choice from that small candidate
set. For an explicitly named invisible skill, validate that exact candidate
instead of declaring it unavailable before checking the cold catalog.

Do not pretend that ordinary language has a reliable binary “skill request”
classifier. A quoted name, a discussion of a skill, or an ambiguous task is
not an invocation. If the host is uncertain and can complete the request with
ordinary reasoning or a visible skill, do that instead of cold discovery. The
only permitted implicit trigger is a high-confidence conclusion that visible
capabilities are insufficient and a specialized workflow is materially needed.
The router's read-only retrieval is deliberately separated from semantic
selection so a false positive cannot load or execute a cold skill.

```powershell
$result = pwsh -NoProfile -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover | ConvertFrom-Json
$result.retrieval.candidates
```

If the catalog is large, narrow it with one or two known domain names via `-DomainHint`. The host AI selects the smallest sufficient candidate set from names, descriptions and the complete user request.

## Deterministic validation

Validate a host-selected candidate before loading it:

```powershell
$result = pwsh -NoProfile -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -Candidate 'skill|codebase-design' | ConvertFrom-Json
$result.load_validation
$result.execution_authorization
```

Load validation checks catalog schema/fingerprint, catalog-root containment,
entrypoint hashes, availability, and the selected skill's declared dependency
closure. A passing `load_validation` authorizes reading only that validated
closure. `execution_authorization.status` is always `not_granted`; the host
must separately review every closure member's declared workflow side effect and
apply ordinary approval, sandbox, MCP, and external-write controls.

Every response also includes a read-only `routing_receipt`. It contains a SHA-256 of the query rather than the raw request, catalog fingerprint, requested and validated candidate names, status, and `truth_boundary`. Use it to record `candidate_discovery_only`, `candidate_load_validated`, or `candidate_discovery_blocked`; it never proves host loading, invocation, model routing, or live acceptance.

## Native cold-capability handoff

When a matching native skill/tool is already visible, use it directly and do
not involve this router or a bridge. Otherwise, the host may hand one exact
candidate to the native `cold-capability-runner` subagent only when this
router has returned all of the following for the same request:

- `load_validation.pass=true`;
- `routing_receipt.truth_boundary=candidate_load_validated`;
- one selected candidate plus its `validated_closure`, with validated paths and
  declared side effects for every member.

Pass the complete validation result, original request, exact selected name, and
an admission contract to the child. The child must not treat validation as execution authorization. The result and receipt also carry the effective `execution_contract` for the selected dependency closure. The host must preserve it: `one_shot` may use `cold-capability-runner`;
`parent_user_input` must stop for parent-mediated user input; and
`multi_turn_user_decision` must use `design-griller`, relay exactly one
question to the user, and wait for that answer before resuming the same child.
Never send an interactive contract to `cold-capability-runner` with a request
for a summary or final conclusion. A read-only admission may execute a bounded
read-only subset even when a skill's maximum declared side effect is
`controlled_write`; it must never write. A `controlled_write` admission
additionally records the user's implementation request, exact write set,
minimum proof, and stop condition. For `external_read`, `unknown`, ambiguity,
a missing execution contract, or any request to alter host/session/profile state, return an admission request to the parent instead. Never use the bridge as automatic middleware or make every natural-language request cold-discover skills.

## Boundaries

- Do not invoke when a visible native skill/tool already matches.
- Do not rank semantics, switch profiles, preheat capabilities, manage sessions, or edit host/plugin/MCP/config state.
- Treat stale, missing, or escaping paths as unavailable.
- Treat malformed catalogs, unsupported schemas, duplicate identities, unknown domains, dangling memberships, and invalid hashes as structured fail-closed results.
- If discovery fails and the task is otherwise clear, continue with native reasoning.
- `decision_owner=host_ai`, `semantic_routing_performed=false`, and all router operations remain read-only.
