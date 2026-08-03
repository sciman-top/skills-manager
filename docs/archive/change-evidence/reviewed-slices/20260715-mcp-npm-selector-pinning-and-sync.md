# MCP npm selector pinning and sync evidence

## Scope and truth boundary

- Date: 2026-07-15.
- Starting point: `main@cad1646d7b0bfdb7f54748090049b1da1b8844a9`, ahead of `origin/main` by 17 commits.
- The fresh audit run `20260715-201159-374` produced zero skill or MCP add/remove actions, so its real apply remained `not_needed`.
- This is a separately authorized follow-up hardening slice. It pins existing disabled npm MCP selectors, fixes the generated Codex cache wrapper, documents immediate sync semantics, and synchronizes the current managed MCP target.
- Changing `skills.json` makes the prior audit's MCP fingerprint historical. The prior no-op report remains evidence for its point-in-time action set, not a current post-change fingerprint.
- Pre-existing worktree boundary: four untracked `docs/change-evidence/20260715-audit-runtime-*-20260715-201159-374*.md` files. This slice does not rewrite or remove them.

## Root cause and decision

- `Convert-CodexNpxServerToCachedNodeWrapper` normalized an exact selector such as `@upstash/context7-mcp@3.2.3` to the bare package name before passing it to `mcp-node-cache-wrapper.mjs`.
- The generated Node wrapper selected the first matching package path under npm `_npx` cache and did not inspect the candidate `package.json` version.
- Therefore an exact selector in `skills.json` could not prove that a future Codex projection would execute the requested version.
- The fix retains the original package selector for the wrapper, uses the normalized package name only for known-bin lookup, and fail-closes with exit `69` until a cache candidate has an exact manifest-version match.
- No install or removal was manufactured because the fresh audit's four action categories were empty. The three affected MCP services remain disabled, and the `filesystem` root remains `D:\CODE`.

## Reviewed package selectors

Registry values were queried again immediately before editing on 2026-07-15.

| MCP | Exact selector | npm integrity | Enabled |
| --- | --- | --- | --- |
| Context7 | `@upstash/context7-mcp@3.2.3` | `sha512-9L/9ufypc6lvlmiGxMLw/O94c8UcTCIvBI+o1R+FHVTgRw2lzg9FPGwcrKWuIOsAXH0+6pWFWm4dJWHbCm92sw==` | `false` |
| Playwright | `@playwright/mcp@0.0.78` | `sha512-XLTUeA6mEN9sQ+hJ4dfG8EIkDbxS0K3Trc2RBkUJuf02TgE2FQRNTMtq/aJfhyRMINsRl/Ybc4sxcWLtFn4/TQ==` | `false` |
| Filesystem | `@modelcontextprotocol/server-filesystem@2026.7.10` | `sha512-Mmjg4anFBD5OzbPnGJOA0jPPN8645ERhQk38HQLpSenx1ox9bfdPkmAzUnNjeQtqQGFLtKe13J20RtLBmUKMZA==` | `false` |

## Write set

- `src/Commands/Mcp.ps1`: preserve package selectors and verify exact cached package versions.
- `tests/Unit/Core.Tests.ps1`: cover selector preservation, mismatched-cache failure, and exact-version execution.
- `skills.json`: pin three existing disabled npm MCP selectors.
- `README.md`: use exact-version examples and document that `同步MCP` writes immediately.
- `skills.ps1`: generated from `src/` by `build.ps1`; not hand-edited.
- `docs/change-evidence/20260715-mcp-npm-selector-pinning-and-sync.md`: this evidence.
- Managed host target: `C:\Users\sciman\.claude\.mcp.json`. Sync ran successfully, but its content hash remained unchanged.

## Sync evidence

- During command-semantics inspection, `.\skills.ps1 同步MCP --help` did not display help and synchronized immediately. This occurred inside the authorized MCP-sync scope; target validation passed. README now records that there is no help or dry-run branch for this subcommand.
- Formal sync command: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 同步MCP`.
- Exit code: `0`.
- Managed targets written: `1`, at `C:\Users\sciman\.claude\.mcp.json`.
- Before SHA-256: `9EC875EB1F7B6A9EC6F4C75A27728280F59DB642257FCD03563ED839D14DBAE4`.
- After SHA-256: `9EC875EB1F7B6A9EC6F4C75A27728280F59DB642257FCD03563ED839D14DBAE4`.
- Projected services: `microsoft-learn`, `openaiDeveloperDocs`.
- Native Claude add/remove commands: skipped because `SKILLS_MCP_NATIVE_SYNC` was unset.
- Cross-CLI live list: skipped by repository default; configuration-state verification passed.
- Codex is not a current resolved MCP target in this configuration, so the live `C:\Users\sciman\.codex\scripts\mcp-node-cache-wrapper.mjs` was not projected by this sync. The corrected wrapper will be generated on a future managed Codex projection.

## Verification

| Stage | Command or evidence | Result |
| --- | --- | --- |
| Red reproduction | `Invoke-Pester -Script .\tests\Unit\Core.Tests.ps1` before the source fix | expected failure: `184` passed, `1` failed; exact selector became bare package name |
| Focused green | same Core test file after build | `185/185` passed |
| Wrapper runtime | temporary `_npx` cache test in Core suite | mismatch exited `69`; exact `3.2.3` entry executed; Core `186/186` passed |
| Build | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\build.ps1` | exit `0`; generated `skills.ps1` synchronized |
| Test | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1` | Unit `488/488`; E2E `12/12` |
| Contract | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 doctor --strict --threshold-ms 8000` | exit `0`; JSON/config contract valid |
| Dependency invariant | `python .\scripts\verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` | exit `0` |
| Hotspot/full | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | exit `0`; full gate passed |

The full gate reported the four pre-existing audit-runtime files as allowed hygiene warnings and reported skill-routing findings in `observe` mode. Neither category produced a gate failure.

## Rollback

- Revert only this slice's tracked files to `cad1646d`: `README.md`, `skills.json`, `skills.ps1`, `src/Commands/Mcp.ps1`, and `tests/Unit/Core.Tests.ps1`.
- Remove only this evidence file if the slice is abandoned.
- Re-run `build.ps1`, then `skills.ps1 同步MCP` to re-project the reverted source of truth.
- Do not remove or rewrite the four pre-existing audit-runtime evidence files.
- No host-file content rollback is currently required because the managed Claude target hash did not change.

## Residual risks and action ledger

- Exact selectors are configured but the three services remain disabled; no npm cache population was attempted. A future Codex enablement fails closed until the exact package version exists in npm `_npx` cache.
- `filesystem` remains disabled and read-only at the MCP tool allowlist layer, but `D:\CODE` is still a broad root. Enabling it requires a separate target-by-target permission review.
- The current managed target set projects only Claude. No claim is made that the corrected wrapper is already live in Codex.
- Install: not executed.
- Uninstall: not executed.
- Configuration modification: executed in repository source of truth.
- MCP synchronization: executed; managed target content converged unchanged.
- Process restart/stop/start: not executed.
- Commit/push/PR/branch/worktree operations: not executed.
