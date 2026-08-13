---
name: capability-router
description: Read-only cold discovery and deterministic validation for local skills. Invoke explicitly only when host-native visible metadata is insufficient, cross-directory discovery is needed, or a host-selected candidate needs containment/availability validation. Host AI owns semantic selection.
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
$result = pwsh -NoProfile -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -Candidate 'skill|codebase-design' | ConvertFrom-Json
$result.validation
```

Validation checks only existence, catalog-root containment, catalog entrypoint hash, availability, and disclosed side effect. A passing result authorizes reading that `SKILL.md`; it never authorizes the workflow's writes or external effects.

## Boundaries

- Do not invoke when a visible native skill/tool already matches.
- Do not rank semantics, switch profiles, preheat capabilities, manage sessions, or edit host/plugin/MCP/config state.
- Treat stale, missing, or escaping paths as unavailable.
- If discovery fails and the task is otherwise clear, continue with native reasoning.
- `decision_owner=host_ai`, `semantic_routing_performed=false`, and all router operations remain read-only.
