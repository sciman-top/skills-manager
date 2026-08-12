# P4 unified capability routing

## Goal and entry evidence

- User problem: installed skills were unreachable outside the active profile; after cold loading was added, two real architecture/implementation requests still selected review-only `draft-spec` and interview-only `grill-with-docs`.
- User outcome: route skills, MCP, plugins/apps/connectors and native tools through one AI-assisted selection contract without profile switching, task creation, restart, silent authentication or hidden external mutation.
- Explicit authorization: the user requested the main chain, planning assets and implementation to proceed autonomously on 2026-08-02.
- Reuse decision: retain Codex progressive skill loading, skill `dependencies.tools`, native MCP/plugin runtime, approval annotations and current PowerShell modular monolith. Do not build a second auth/session/provider/runtime.
- Community disposition: retain metadata retrieval, abstention and selected-path ideas from `legendtkl/agentic-skill-router@160b30f0b67c923077f886376fdfae1016a70702` (MIT); reject rename/disable routing and any silent host mutation.

## Root cause and red evidence

- Root cause: generic `文档/规格/需求/方案` expansion accumulated positive score from name, description, activation and group context; the selector had no mutually exclusive intent or negative-trigger stage.
- Initial new regression run: `CapabilityRouter.Tests.ps1` reported 4 failures and 4 passes. The missing behaviors were negative-intent exclusion, available MCP selection, disabled MCP activation planning and schema v2 output.
- First green run after the selector change: 8 passed, 0 failed.
- Real 114-candidate replay exposed an additional substring collision (`spec` matched `inspect`) and an operator-skill safety collapse (`to-spec` looked read-only). Short Latin terms now require token boundaries; operator skills require explicit intent and emit `load_skill_with_approval`.
- Golden routing verifier: 10/10 direct, indirect, negative, ambiguous, cross-domain, cross-kind, runtime-snapshot and side-effect cases passed; findings=0, side-effect violations=0, writes=false.
- Verifier unit tests: 2/2 passed, including fail-closed expected-selection drift.

## Planned write set and boundary

- Source: `overrides/capability-router/`, `config/skill-routing-policy.json`, routing verifier/fixtures and targeted tests.
- Product truth: P4 spec/manifest/plan/todo, PRD, architecture, roadmap, documentation index and P4 entry decision.
- Generated: only `skills.ps1` and `agent/capability-router` through `build.ps1`.
- Prohibited: automatic profile/config mutation, plugin/MCP install or enablement, OAuth/token handling, Codex restart, new task creation, provider/model/session routing and live acceptance claims.

## Verification record

### Build transaction root cause and repair

- First `构建生效` correctly rolled back `agent/` after a downstream projection failure, but `.build-cache.json` had already persisted the new input signature. The rollback transaction did not include the cache.
- The next invocation accepted the restored stale `agent/` because the cache hit checked input signature and output directory names only. This produced a false cache hit even though the router source/output SHA-256 values differed.
- Red regression: `BuildCache.Tests.ps1` observed `old-signature` replaced by `new-signature` after rollback; 28 passed, 1 failed. A second red regression proved that a matching input signature with a mismatched output fingerprint was incorrectly accepted; 29 passed, 1 failed.
- Repair: the transaction now snapshots/restores `.build-cache.json` with `agent/`, deletes the cache on backup failure, bumps the cache algorithm, records a full `agent/` output fingerprint and rejects missing/mismatched fingerprints. The focused suite is now 30/30.

### Projection and fresh-profile evidence

- Real rebuild: 107 Agent skills, 12 overrides, no cache-hit shortcut; projection persisted 110 entries / 110 unique / 102 disabled / 0 conflicts.
- Codex config was stable on the idempotent rebuild: SHA-256 `60EEACFF1943AA220E973423C7215EFDB7FF2C0C2549B30D50A8A895ED863248` before and after.
- Router `SKILL.md`, `agents/openai.yaml` and `scripts/route-capability.ps1` source/output SHA-256 pairs are equal.
- Fresh `codex debug prompt-input` probes passed all 16 profiles and restored `default`. Every profile included resident `capability-router` and stayed within its declared budget; tightest was `coding-strict=7769/8000`, final default was `6109/8000`.
- Targeted cache/routing suites passed 48/48 before the output-fingerprint regression was added; the final cache suite passed 30/30. Golden corpus remains 10/10 with 0 findings and 0 side-effect violations.

The final ordered repository gates are recorded below after completion. Repository, host and live states remain distinct: no Codex restart, plugin/MCP activation, OAuth, provider/model/session routing or live business acceptance was performed.

### Ordered acceptance before full quality

- `build.ps1`: pass.
- Targeted router/planning/P4 entry tests: 19/19.
- `verify-capability-routing.ps1`: 10/10 cases, findings=0.
- `tests/run.ps1`: Unit 687/687 and E2E 18/18; total 705/705.
- `verify-vnext-planning.ps1`: pass at the pre-closeout checkpoint with 5 done / 1 in progress.
- `verify-vnext-phase4-entry-gate.ps1`: pass; historical entry decision remains `started/in_progress`, all required evidence=true.
- `skills.ps1 doctor --strict --threshold-ms 8000`: pass; one non-blocking average-performance warning was reported for `apply_targets`.
- Dependency baseline: pass. Host capability matrix: pass for 5 hosts / 7 evidence records.
- Final full quality and post-closeout planning results follow after the 6/6 truth update.

### Final closeout

- Post-closeout planning contract: tasks=6, done=6, open=0; planning/entry unit tests 11/11.
- `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`: pass.
- Full gate details: generated sync clean; Unit 687/687; E2E 18/18; skill integrity 106; routing findings=0; dependency baseline pass; config enforce finding_count=0; host matrix 5/7; planning 6/6; doctor JSON contract pass.
- Final repository state: P4 6/6 `repo_verified`. The fresh-profile probe proves current host visibility in new prompt-input processes, but no current Codex App restart/hot reload, plugin/MCP activation, OAuth, provider/model/session routing or live business acceptance was performed.
