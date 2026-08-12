# Phase 5 Adaptive Capability Fabric evidence

## Scope and truth boundary

P4 had repository-verified reachability and activation planning, but current-host replay exposed four data-flow defects: snapshot `skill`/`mcp` kinds were dropped, static `seen` entries masked live availability/auth/callability, opaque App ids were not searchable by runtime/display identity, and capability-level `side_effect=unknown` could not safely model individual tools. P5-006 repairs those roots without taking ownership of host execution, auth, approval, activation, session or plugin installation.

The requested end state is a unified AI-assisted decision/control plane plus typed capability/tool policy and host-native execution adapters. It is not a second agent runtime. “Seamless” is allowed only for a capability already exposed to the current task, callable, authenticated, read-only/external-read and approval-free. Writes, destructive/unknown tools and activation-required capabilities remain visible transitions.

## Worktree boundary

- The task inherited 27 modified and 14 untracked user changes; all were preserved. P5 added routing/snapshot/policy regressions, then repaired two full-gate scripts/tests in the same declared closeout slice.
- No reset, checkout, cleanup, commit or push was performed.
- No auth/provider/model/sandbox, plugin/MCP enablement, profile/session or Codex App/CLI process state was changed.
- `agent/`, vendor caches and external import contents were not copied, linked or fabricated into this linked worktree.

## Official and reference evidence

- Current Codex manual cache: `C:\Users\sciman\AppData\Local\Temp\openai-docs-cache\codex-manual.md`; used for Skills as workflow/instruction surface, MCP/connectors as live data/action/auth surface, Plugins as distribution bundles, and independent workspace/plugin/connector/runtime permission boundaries.
- Local Codex 0.145.0 help/schema plus read-only App Server execution proved `skills/list`, `app/installed`, `app/list`, `app/read(includeTools=true)` and `mcpServerStatus/list(detail=toolsAndAuthOnly)` request shapes. `app/read` is display-only and cannot prove callability/auth.
- MCP specification revision `7634684382c3d14cf7e9f14073fe40a2d8ace3fa`: tool annotations are hints; protocol defaults are `readOnlyHint=false`, `destructiveHint=true`, `openWorldHint=true`.
- Read-only comparison revisions: OpenAI Codex `61a44880a85d2fd0d8770908dea5733495e571c8`; OpenAI plugins `11c74d6ba24d3a6d48f54a194cd00ef3beea18f9`; Agent Skills `38a2ff82958afee88dadf4831509e6f7e9d8ef4e`; Anthropic skills `b29e7cf65e5cb78a5ac33d582270551bc74a14eb`; Gemini CLI `3818efbbfbf8ef029ef53a6ab1093db39971ce83`.
- Adopted: catalog -> activation -> resources progressive disclosure; host model semantic narrowing over deterministic containment/freshness/safety ceilings; host-owned tool execution/approval; explicit materialization evidence.
- Rejected: a second plugin marketplace/runtime, provider call per route, daemon/embedding database/general agent runtime, and any AI/annotation-based permission upgrade.

## Red-green implementation evidence

- Host truth/App alias/tool gate baseline: existing CapabilityRouter 12/12 passed; 3 new cases failed. Green: CapabilityRouter 15/15.
- MCP annotation policy baseline incorrectly allowed explicit non-read-only Gmail label tools as external reads. New CapabilitySnapshotPolicy tests failed before the fix and pass 3/3 after protocol-default handling.
- Compound request baseline selected only the highest-scoring read tool for “search then send”. Green selects `gmail.search_email_ids` plus `gmail.send_email`, aggregates `controlled_write`, returns `request_approval`, `auto=false`.
- Dynamic verifier now inventories and identity-probes every current snapshot descriptor; missing, failed, invalid and shadowed selections are separate counters. CapabilityRoutingVerifier passes 3/3.
- The former SkillProjection test required runtime-materialized gitlink contents in a fresh worktree. It now always validates tracked routing/config policy and adds upstream metadata checks only when the imports are actually materialized; 30/30 passed in targeted replay.
- A final standard-command replay in this linked worktree found that policy/config auto-discovery depended on a generated projection manifest: OpenAI Docs fell back to activation-required and a same-name Playwright skill shadowed the MCP. The new source-only regression failed 1/16 before the fix. `Find-UpwardFile` now discovers same-repo policy/config only when no manifest exists, while arbitrary explicit fixture manifests never borrow another repo's policy; CapabilityRouter passes 16/16 and the standard command restores `use_available_mcp`/`request_mcp_activation` without explicit path arguments.

## Full-gate hermeticity follow-through

The first pre-closeout full quality run reran Unit 698/698 and E2E 18/18, then correctly failed at `skill-integrity`: `agent/` was empty and 7 dependency callers were reported missing. A quick rerun after the first repair exposed the same root in `skill-routing` (`development-flow/brainstorming`).

Root cause: `agent/` is an ignored generated layer and portable/CI explicitly exclude it; the 39 `imports/*` entries are locked gitlinks without `.gitmodules`, so a clean linked worktree cannot enumerate their package metadata. The gates incorrectly assumed a pre-existing materialized operator workspace.

Repair:

- `verify-skill-integrity.ps1` keeps strict package/resource/OpenAI metadata/installed closure when agent packages exist. With no generated agent it validates 130 tracked config/override declarations, 7 dependency entries and profile closure, reports `materialization_status=source_only`, and records 3 inactive historical Superpowers callers; missing declared dependencies still fail.
- `verify-skill-routing.ps1` keeps strict installed-member validation in materialized mode. Source-only mode validates 142 tracked config/override/policy declarations, reports 12 policy-only members requiring runtime evidence, merges resident skills into the active profile, and preserves structural group/conflict/intent checks.
- Regression suites: SkillIntegrityScript 13/13; SkillRouting 10/10. Real source-only reports exit 0 with zero blocking findings. Quick quality then passed the complete contract chain.
- Source-only is not package/runtime verification. Recovery is `构建生效` followed by both verifiers; for this task, the independent fresh App Server snapshot and dynamic identity/tool audit provide current-host runtime evidence without copying external assets.

## Current-host read-only evidence

Fresh snapshot: `C:\Users\sciman\AppData\Local\Temp\skills-manager-host-snapshot-20260803-final.json`.

- schema v3, `read_only=true`, status=`runtime_complete_catalog_partial`; the snapshot itself has no `writes_performed` field, so zero-write evidence comes from router outputs and worktree comparison rather than an invented snapshot claim.
- 137 capabilities: 123 skills, 6 installed/enabled/callable Apps, 8 discovered MCP servers.
- 300 tool descriptors: 162 read-only/external-read, 48 controlled writes, 90 destructive, 0 unknown; all 300 carried protocol annotations in this snapshot.
- `app/list` and display-only `app/read(includeTools=true)` returned bounded HTTP 403. `app/installed` and `mcpServerStatus/list` succeeded; the wider uninstalled catalog is the only missing coverage.
- App callability comes from `app/installed`; tool policy comes from MCP annotations and `codex_apps` namespace mapping. Server discovery is not current-task tool exposure.
- Final dynamic closeout verifier after source-only auto-discovery repair: exit 0 after 340.0 seconds, golden 11/11, findings 0. Its fail-closed loop covered all 137 inventory entries and 137 identity probes; JSON recorded routed=137, passed=137, missing=0, shadowed=0, tools=300, unsafe-tool violations=0, annotation-policy violations=0.

Required replay:

- `grill-with-docs` -> `load_skill`, auto=true.
- `debug:dotnet` -> `load_skill`, auto=true.
- `docx` -> `load_skill`, auto=true.
- `openaiDeveloperDocs` -> `use_available_mcp`, auto=true with a matched read tool.
- `Playwright` -> `request_mcp_activation`, auto=false; discovery does not pretend hot loading.
- `Gmail` read -> `use_available_capability`, auto=true for the matched external-read tool.
- `GitHub` read -> `use_available_capability`, auto=true for the matched external-read tool.
- Gmail search+send -> both read and send tools, `request_approval`, auto=false.

Fresh-task black-box acceptance:

- Independent Codex task `019fc775-8716-7013-b4a2-26a1464ae822` ran from `C:\Users\sciman\.codex\worktrees\7871\skills-manager` against this target worktree by absolute path, without relying on the parent task summary.
- It replayed all eight cases using only `-Query` and `-HostSnapshotPath`, deliberately omitting `-PolicyPath` and `-ConfigPath`. All eight automatically resolved this repository's `config/skill-routing-policy.json` and `skills.json` and matched the required action, auto, side-effect, approval and tool contract; exact failures: zero.
- Every router response recorded `writes_performed=false`; the target worktree path set was unchanged before and after the replay. The task performed no file edit, staging, commit, push, host mutation or process restart.
- Fresh-task planning verification exited 0 with 6 done/0 open, and `git diff --check` exited 0 with line-ending conversion warnings only. The task independently parsed 137 capabilities and 300 tools from the snapshot; it did not rerun the dynamic verifier, Unit/E2E suites or full quality gate, so those remain the repository closeout evidence recorded below.
- Result: fresh-task black-box routing acceptance `PASS`. This establishes an independent fresh-context probe for repository routing behavior, not authenticated business execution, fresh-profile host projection or `live_accepted`.

## Final repository verification

- Build: exit 0.
- Final affected Pester: 82/82, including the source-only repo discovery red-green regression; SkillIntegrityScript 13/13 and SkillRouting 10/10 remain included.
- Final full tests after the auto-discovery repair: Unit 703/703, E2E 18/18, exit 0.
- Contracts: strict doctor, dependency baseline, host matrix (5 hosts/7 evidence), P5 planning (6 tasks, 6 done/0 open), historical P4 entry, capability-router skill lint and dynamic routing verifier all exited 0.
- Quick quality after gate repair: exit 0 across build, hygiene, generated sync, source integrity/routing, dependency, config, host, planning and doctor.
- Final full quality on the stabilized implementation passed with exit 0 after 285.5 seconds, including Unit 703/703, E2E 18/18 and every source/config/host/planning/doctor stage. P5-006 and P5 are `repo_verified`; this does not imply host activation, authenticated business action or `live_accepted`.

## Host and acceptance boundary

- Windows App Server daemon reuse is `platform_na`: `codex app-server daemon version` reports daemon lifecycle only on Unix. Alternative verification uses an owned read-only stdio child; recovery is an officially supported Windows daemon/current-client read transport.
- App catalog/metadata coverage is partial because of host HTTP 403. Recovery is host entitlement/admin availability; this task does not alter auth.
- Current App Server discovery proves `host_discovered`; `app/installed` proves the six Apps callable in that runtime. It does not prove every discovered MCP is surfaced to this task.
- No authenticated business write, OAuth, install/activation, fresh-profile host projection or ChatGPT Web local projection was performed. Independent fresh-task black-box routing acceptance passed, but business `live_accepted` remains `not_run`.

## Rollback

Revert only the P5-006 router/snapshot/verifier, hermetic gate scripts/tests and the P5 docs/task/evidence files, then rebuild `skills.ps1`. Do not reset or overwrite P4, imports, vendor/cache, audit artifacts or unrelated user changes.
