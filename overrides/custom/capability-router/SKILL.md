---
name: capability-router
description: Read-only cold discovery and deterministic validation for local skills. Use only when host-native visible metadata is insufficient, cross-directory discovery is needed, or a host-selected candidate needs containment/availability validation. Host AI owns semantic selection; do not use as a normal preflight.
---

# Capability router

This is a narrow fallback, not a normal task preflight and not a second semantic router.

## Cold discovery

Use only when visible native metadata cannot expose the needed local skill:

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

Load validation checks only catalog schema/fingerprint, catalog-root containment, entrypoint hash, and availability. A passing `load_validation` authorizes reading that `SKILL.md` only. `execution_authorization.status` is always `not_granted`; the host must separately review the selected skill's declared workflow side effect and apply ordinary approval, sandbox, MCP, and external-write controls.

Every response also includes a read-only `routing_receipt`. It contains a SHA-256 of the query rather than the raw request, catalog fingerprint, requested and validated candidate names, status, and `truth_boundary`. Use it to record `candidate_discovery_only`, `candidate_load_validated`, or `candidate_discovery_blocked`; it never proves host loading, invocation, model routing, or live acceptance.

## Boundaries

- Do not invoke when a visible native skill/tool already matches.
- Do not rank semantics, switch profiles, preheat capabilities, manage sessions, or edit host/plugin/MCP/config state.
- Treat stale, missing, or escaping paths as unavailable.
- Treat malformed catalogs, unsupported schemas, duplicate identities, unknown domains, dangling memberships, and invalid hashes as structured fail-closed results.
- If discovery fails and the task is otherwise clear, continue with native reasoning.
- `decision_owner=host_ai`, `semantic_routing_performed=false`, and all router operations remain read-only.
