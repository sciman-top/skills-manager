# Skill profile budget and MCP refresh evidence

## Goal and boundary

- Goal: complete the interrupted skills update, restore fail-closed skill projection, refresh the supply-chain lock, and synchronize managed MCP configuration.
- Source of truth: `skills.json`; generated/runtime outputs remain `agent/`, `reports/skill-projection/current.json`, the Claude target junction, and managed host configuration blocks.
- Existing worktree boundary: 25 `imports/*` gitlinks were already advanced when this task started. They were preserved as the intended upstream refresh and recorded in the regenerated lock; no unrelated worktree changes were reverted.
- Host boundary: no Codex or Claude process was restarted, stopped, or killed. MCP native CLI registration and cross-CLI live probing remained disabled by their existing opt-in guards.

## Root cause and change

- Reproduction: `skills.ps1 构建生效` failed closed with `coding=8255/8000`, `content=8064/8000`, and `physics=8392/8000`.
- The budget calculation was correct. Enabled plugin skill metadata had grown beyond the configured 1,700-character reserve to 2,038 characters, adding 338 characters to every profile. The current physics skill set also measured 6,354 managed metadata characters versus 4,598 in the older manifest.
- The 8,000-character limit and external inventory accounting were retained. No upstream `SKILL.md`, generated `agent/` content, or projection estimator was patched to hide the growth.
- `coding` stopped keeping `spec-driven-development`, `grill-with-docs`, and `grilling` permanently active; the profile retains brainstorming, planning/execution, domain modeling, implementation, review, and verification coverage.
- `content` stopped keeping the standalone `baoyu-compress-image` operator permanently active; the primary creation, editing, illustration, formatting, publication, and research path remains active.
- `physics` stopped keeping generic `storyboard-creation` and `frontend-design` permanently active; the domain router, Manim, D3, Web UI engineering, Vite, Playwright, research, and Remotion validation remain active.
- All removed skills remain installed. Only their always-active profile membership changed.
- `skills.lock.json` was regenerated against the current 8 vendor and 49 import sources, including the 25 advanced import gitlinks.

## Live projection and MCP state

- `skills.ps1 构建生效`: exit 0; projection persisted with 112 entries, 112 unique names, 21 active default entries, 91 disabled paths, and 0 conflicts.
- External plugin inventory: 10 skills and 2,038 metadata characters.
- Failing profiles now measure `coding=7749/8000`, `content=7867/8000`, and `physics=7684/8000`; all 10 profiles pass.
- `skills.ps1 同步MCP`: exit 0; `C:\Users\sciman\.claude\.mcp.json` contains the default managed servers `microsoft-learn` and `openaiDeveloperDocs`.
- Native Claude MCP add/remove and cross-CLI live checks were not requested and remained skipped by default.
- A separate read-only CLI probe confirmed both managed HTTP servers are enabled in `codex mcp list` and connected in `claude mcp list`. Codex host-owned `node_repl`/`sites-design-picker` and Claude servers from other scopes remain outside this repository's managed ownership.

## Verification

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`: exit 0.
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 构建生效`: exit 0; reproduced failure is resolved.
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 同步MCP`: exit 0; configuration-state validation passed.
4. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 锁定`: exit 0; lock refreshed.
5. The first complete Pester attempt reported 3 unit failures, but an immediate unit-only rerun passed 490/490 and the failures did not reproduce. The subsequent full `tests/run.ps1` run passed Unit 490/490 and E2E 12/12.
6. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`: exit 0. The historical `apply_targets` performance anomaly remains warning-only under the current contract.
7. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`: exit 0.
8. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`: exit 0; build, hygiene, generated sync, skill integrity, routing, dependency baseline, doctor JSON contract, Unit 490/490, and E2E 12/12 passed.
9. `codex mcp list`: exit 0; configuration parsed and the two managed HTTP servers are enabled. `claude mcp list`: exit 0; all 11 merged-scope servers reported connected, including the two managed servers.

## Risk and rollback

- Upstream skill content changed independently of this repository. The lock pins exact commits and repository gates validate structure and contracts, but do not semantically certify every upstream instruction.
- Future enabled-plugin or upstream description growth can legitimately trip the same fail-closed budget again; re-evaluate profile composition instead of raising the limit without evidence.
- Roll back only this slice by restoring the six profile memberships in `skills.json`, restoring the prior `skills.lock.json` and intended import gitlinks, then running `build.ps1`, `skills.ps1 构建生效`, and `skills.ps1 同步MCP`.
- Do not restore or overwrite unrelated host configuration outside managed blocks, and do not restart Codex or Claude as part of rollback.

## Fresh revalidation and audit boundary

- Fresh audit runs `20260717-224731-911`, `20260717-225404-537`, and `20260717-230624-690` each produced complete input bundles and schema-valid no-op recommendations, but preflight failed closed with `target_repo_drift` because `D:\CODE\local-ai-dev-orchestrator` was being changed concurrently.
- The initial scan plus two automatic rescans exhausted the configured drift retry boundary. No stale override was used; dry-run and apply were not executed, so the audit no-op is not an accepted current closeout.
- Independent hardening revalidation passed in fixed order: `build.ps1`, `tests/run.ps1`, strict doctor, dependency baseline, and the full local quality gate with `-AllowDirtyWorktree` all exited 0.
- After that gate, `imports/data-visualization` advanced to `e22ad0491df17d66acb38b0fae389f7630b91c32` and `imports/mcp-cli` advanced to `71df97432a4d077e2df17e163199fc27e8b8e1e8`. Their HEAD set remained stable for 20 seconds, `skills.ps1 锁定` refreshed the exact lock, and the complete fixed-order gate plus full quality gate were rerun successfully against the new lock.
- A subsequent real `skills.ps1 构建生效` exited 0 and persisted a 112-entry projection with 112 unique names, 21 active default entries, 91 disabled paths, and 0 conflicts. All profiles pass the 8,000-character limit; `coding=7749`, `content=7867`, `physics=7684`, and the highest current profile is `dotnet=7926`.
- A subsequent real `skills.ps1 同步MCP` exited 0. `C:\Users\sciman\.claude\.mcp.json` contains only `microsoft-learn` and `openaiDeveloperDocs`, with SHA-256 `9EC875EB1F7B6A9EC6F4C75A27728280F59DB642257FCD03563ED839D14DBAE4`.
- Read-only `codex mcp list` reported both managed HTTP servers enabled. Read-only `claude mcp list` reported them connected; all other merged-scope Claude services and Codex host-owned services remain outside this repository's ownership.
- No Codex or Claude process was restarted. File projection and CLI configuration/health are verified, but hot reload into this already-running Codex conversation is not proven; classify it as `next_session_projected`, not `current_session_live_verified`.
- No commit or push was performed.
