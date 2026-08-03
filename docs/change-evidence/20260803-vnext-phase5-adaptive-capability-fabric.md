# Phase 5 Adaptive Capability Fabric evidence

## Scope and problem

P4 was repository-verified, but the real query “评估统一 capability selector…是否存在更优工程终态” produced no intent and selected unrelated Windows/MCP construction capabilities. P5 addresses task understanding, composition and current host truth while preserving host-owned execution.

## Sources and decisions

- Current Codex manual: stable `skills/list`, `app/installed`, `app/list`, `mcpServerStatus/list`; plugin list/install is under development and excluded from required runtime truth.
- Current host: `codex-cli 0.145.0`, `codex app-server --stdio` available.
- Decision: unified decision plane, native execution plane; no provider-per-route, daemon, database, OAuth, install, config/profile/session mutation.

## Worktree boundary

P4 and earlier user-authorized changes were already present and dirty. P5 edits only the declared manifest write sets and does not reset, reorder or absorb unrelated imports/vendor/runtime reports.

## Current evidence

- CapabilityRouter red baseline: 8 passed, 4 expected failures.
- CapabilityRouter after implementation: 12/12 passed.
- Golden routing: 11/11 passed, 0 findings, 0 side-effect violations.
- Live App Server snapshot: schema v2, read_only=true, 137 capabilities (123 skills, 6 installed/callable apps, 8 MCPs), status=`runtime_complete_catalog_partial`; only the wider uninstalled-app catalog returned HTTP 403.
- Live meta-query replay: `architecture_assessment`, `capability_orchestration`, forbidden selections=0, snapshot=current, writes=false.
- `quick_validate.py overrides/capability-router`: valid.
- P5 planning: 5 tasks, 4 done/1 in progress, 0 findings; historical P0-P4 verified.
- Targeted Pester: CapabilityRouter 12/12, CapabilityRoutingVerifier 2/2, ProductPlanning 7/7.

## Closeout

- Build and real projection: 107 agent skills; 110 unique projected entries; 0 conflicts; override/agent router SHA-256 `65563B903D499F130D8EC210332BD43D92025CF7C64F890773A5B95D6022A739` matched.
- Full tests: `tests/run.ps1` exit 0; E2E 18/18. Full quality reran the test suite and exited 0.
- Contracts: doctor strict, dependency baseline, host matrix (5 hosts/7 evidence), P5 planning, historical P4 entry and routing golden all exited 0.
- Profiles: 16/16 passed and restored `default=6176/8000`; tightest observed `marketing=7854/8000`.
- Full quality: build, hygiene, generated sync, tests, 106-skill integrity, routing, dependency, config, host, planning and doctor passed.

Systematic diagnosis of the live `app/list` error: initialization, `skills/list`, `app/installed` and `mcpServerStatus/list` returned valid responses; six enabled/callable installed apps and eight MCP servers were present. Only the external uninstalled-app connector directory returned HTTP 403. The adapter therefore reports bounded `source_errors`, per-source `coverage`, and `status=runtime_complete_catalog_partial`; it preserves complete current-runtime sources without claiming the wider catalog succeeded. It does not retry with auth changes or mutate auth.

Windows daemon/proxy reuse is `platform_na`: `codex app-server daemon version` exits 1 with `daemon lifecycle is only supported on Unix platforms`. The Windows-first adapter therefore uses an owned stdio child process; it does not start/restart the desktop app or mutate auth. Recovery condition: current Windows Codex officially supports daemon lifecycle or exposes another documented read-only current-client transport.

P5 is `repo_verified`. Current-host evidence is limited to read-only discovery. Plugin/MCP install, OAuth, config/profile/session mutation, authenticated business actions, ChatGPT web local projection and `live_accepted` remain host-owned or not run.

Final completion audit added the missing AI adjudication contract: script scores are retrieval evidence, while the already-running host model uses the full request to reject false matches and choose the smallest composition. AI may only narrow/abstain and cannot relax deterministic freshness, auth, approval or side-effect gates.
