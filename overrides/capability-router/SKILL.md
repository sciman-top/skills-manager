---
name: capability-router
description: Understand and route a task to the narrowest installed skill, MCP, plugin/app/connector, or native tool; compose a safe capability graph, reuse compatible session capabilities, and recommend profile preheating without changing host state. Use at task start, task or domain changes, architecture/meta-capability assessment, multi-capability work, missing visible capabilities, host-snapshot routing, or requests for automatic capability/profile selection.
---

# Capability Router

Select and compose capabilities, not runtime profiles. Keep the current conversation and process alive.

## Route

1. Pass the user's complete current request to `scripts/route-capability.ps1`:

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<request>'
   ```

2. Adjudicate the result with the full current request. Treat deterministic scores as retrieval evidence, not final semantic truth. Remove any candidate whose purpose does not directly advance the task goal, repair an obviously wrong task type/domain in working memory, and keep the smallest sufficient composition. Never add an unreturned cold capability without reading its metadata through an available discovery surface.
3. Inspect `task_model`, `inventory`, `capability_graph`, `session_plan`, and `activation_plan` before acting:
   - For `load_skill` or `use_active_skill`, read the selected skill `path` completely and apply its ordinary trigger, precedence, safety, and announcement rules.
   - For `use_available_mcp` or `use_available_capability`, use only the already surfaced host tool and continue to obey its approval and side-effect rules.
   - For `load_skill_with_approval`, `request_authentication`, `request_approval`, `request_mcp_activation`, or `request_activation`, do not mutate host state. Explain or execute the required explicit host step only when the task separately authorizes it.
4. Pass a current schema-v3 host snapshot with `-HostSnapshotPath`; schema v1/v2 and `-CapabilitySnapshotPath` remain compatible. Use `-SessionSnapshotPath` only for caller-provided loaded-capability state. Reject stale snapshots rather than inferring current installation, callable, accessibility, or authentication state.
5. Follow the minimal ordered stages in `capability_graph`. Reuse items in `session_plan.reuse`; load only the returned narrow set. Treat `preheat_recommendation` as advice and never apply it automatically.
6. If `abstained` is true, continue with native reasoning or ask a question only when the task itself is materially ambiguous.

## Boundaries

- Do not edit skill/MCP profiles, Codex config, skill enablement, MCP/plugin state, authentication, or session state.
- Do not restart Codex or create another conversation to route a task.
- Treat returned paths as local data. The script accepts only existing `SKILL.md` files contained by declared skill roots.
- Current snapshot fields may override static availability/auth/callability/freshness; static path, policy, role/group, and profile reachability remain containment and fallback facts. Host discovery alone never proves current-task tool exposure.
- Auto-use only read-only skills or already-available, callable, authenticated, no-approval `read_only`/`external_read` tools. Keep write, destructive, open-world, unknown, and activation-required capabilities behind the returned plan.
- AI semantic adjudication may narrow or abstain, but must never upgrade availability, auth, approval, freshness, containment, or side-effect permissions returned by deterministic policy.
- Preserve schema-v2 consumer fields while using schema v3 task, retrieval, graph, session, snapshot, and preheat fields.
- Abstain on weak matches. Profiles are optional preheat bundles, never reachability gates or silent runtime switches.
