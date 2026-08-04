# Watch hook shell boundary and silent heartbeat hardening

## Problem and root cause

Two live probes exposed that the revision-2 cross-thread guard was still too permissive:

- Shell parsing split only on `;`, `&`, and `|`, so a newline or nested shell could place `codex app-server ... thread/send` behind a harmless first command.
- The repair initially trusted a reader-looking command prefix. That was insufficient because `rg --pre`, `git grep -O`, PowerShell/Bash subexpressions, and parenthesized command expressions can execute a sender before or inside the reader.

A separate live Desktop run showed routine heartbeat chatter in the target task. `needs_input` was classified correctly, but the durable prompt allowed a repeated status summary and then emitted commentary before `DONT_NOTIFY`. Desktop also retains scheduled input cards and run transcripts; notification suppression cannot hide that native history.

## Implemented changes

- Split shell input on CR/LF and command separators, then evaluate every segment containing a cross-thread send marker.
- Keep the inspection allowlist fail-closed and reject nested execution syntax, `rg --pre`, and `git grep -O` / `--open-files-in-pager` even when the segment begins with a reader.
- Expand the host doctor from one direct-tool simulation to direct, multiline, nested-shell, reader-subexpression, and reader-exec-option cases.
- Require every repeated observe-only target heartbeat to emit no commentary or summary and return exactly `DONT_NOTIFY` unless a newly discovered, deduplicated human gate is proved.
- Apply the same exact-output rule to the fleet supervisor and prevent it from overwriting target prompts while the installed target generator is stale.
- Record the Desktop truth boundary: `DONT_NOTIFY` and `notification_policy=failed_runs_only` suppress routine notifications and chatter, but cannot remove host-retained scheduled cards or run transcripts.

## Verification

- Original shell probe: semicolon denied; newline and `cmd /c` incorrectly allowed.
- First regression RED: `8 passed / 1 failed` for multiline and nested-shell bypasses; GREEN affected slice: `33/33`.
- Extended lexical-boundary probe reproduced five additional allowed cases: `rg --pre`, `git grep -O`, `rg $(...)`, `Select-String $(...)`, and `Get-Content (...)`.
- Extended hook RED: `9 passed / 1 failed`; GREEN: `10/10`.
- Doctor RED: `1 passed / 1 failed` because the new simulation fields were absent; GREEN combined hook/installer run: `12/12`.
- Silent-heartbeat RED: `22 passed / 2 failed`; GREEN target/fleet contract: `24/24`, followed by the stale-generator guard at `5/5`.
- Final affected run, including target, fleet, hook, installer, and projection contracts: `68/68`; skill integrity verified `107 skills`.
- Final full gate: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` exited `0`; all build, Unit/E2E, repository hygiene, generated sync, skill integrity, routing, dependency, config, host capability, planning, and doctor JSON stages passed in `185713 ms`.
- Formal `skills.ps1 构建生效` rebuilt `108` agent skills and projected the new watch prompt through the governed path.
- Native automation metadata re-read showed three unique heartbeats, all `ACTIVE`, all at 10 minutes, and all `notification_policy=failed_runs_only`. Target prompt hash is `688dbcca261ed76735cd130029c328bd8778e722f71eec0a125cbb11845873ca`; fleet prompt hash is `18cd04243d6e2ef70644480d1ecff2bbb0a3e0dfdddc60b5df2d5c426e8868a9`.
- `approval_policy = "never"` remained unchanged.

## Live boundary and rollback

The verified repository hook SHA-256 is `4c395157b99077b16361b84832fd0e13616c88275b6a1beb1a9bfbf3bb07f603`; the currently installed host hook is still the older `b38177095ed83fcfc9328d712ac0b7a892243d8870873840a90f651703323106`. Until the formal installer updates the host definition, `/hooks` exact-definition review/trust is repeated, and a fresh supported-path probe passes, the guard remains `soft_guard_only`.

Rollback only the three watch override files, two hook scripts, four affected test files, this evidence file, the governed host hook install, and the three native automation prompt/notification updates. Do not edit automation TOML, change `approval_policy`, stop Codex/Desktop, or send content to another task.
