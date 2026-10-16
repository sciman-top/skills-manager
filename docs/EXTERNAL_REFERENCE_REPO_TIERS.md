# External reference shelf

## Boundary

The shelf is an optional read-only development cache. It is outside the runtime architecture and is not a prerequisite for ordinary build, test, update, projection, or closeout. `skills.json` remains the runtime source of truth.

`references/reference-shelf.manifest.json` is the inventory source only for an explicitly invoked refresh or verify. The only owned checkout root is:

```text
D:\CODE\external\skills-manager-references
```

The repository does not own `D:\CODE\external` as a whole and never mutates sibling projects or runtime imports through reference refresh. A missing checkout or stale shelf blocks source comparison for that task only.

## Tiers

- `core-mainline`: first-party specifications and implementations used for frequent decisions; entries may be in `default_refresh_set`.
- `secondary`: useful comparison implementations refreshed explicitly.
- `conditional`: repositories refreshed only by explicit tier or repository selection.

All manifest entries are `active` and must record a named current consumer and `retirement_trigger`, regardless of tier. A repository without both is not retained as a candidate or historical record; rediscover and review it when a real task needs it.

## Refresh

```powershell
pwsh -NoProfile -File .\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
pwsh -NoProfile -File .\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
pwsh -NoProfile -File .\scripts\refresh-reference-repos.ps1 -Tier conditional -CloneMissing -FetchOnly -SkipDirtyRepos
pwsh -NoProfile -File .\scripts\verify-reference-governance.ps1
```

Before network operations, refresh verifies manifest containment, repository identity, actual `origin`, and dirty state. Every run writes an ignored receipt under `reports/reference-refresh/<run-id>/receipt.md`; dynamic refresh state is not tracked in Git. These receipts are reference-workflow evidence, not product health or release gates.

Clone/fetch/fast-forward only authorizes read-only comparison. It does not authorize dependency installation, script execution, skill/MCP adoption, runtime activation, host mutation, or deletion from `skills.json`.

## Read-only boundary lock and baseline

The external root is normally left unlocked; its read-only property is enforced by rule plus a recorded baseline, not by ACLs. `references/external-readonly-baselines.json` pins `relative_path`, `head`, and `origin` for every Git checkout discovered below the external root, and `scripts/verify-reference-governance.ps1` fails on missing, relocated, dirty, or drifted entries.

```powershell
pwsh -NoProfile -File .\scripts\lock-external-repos.ps1 -Status          # root ACE + top-level write probes
pwsh -NoProfile -File .\scripts\lock-external-repos.ps1 -Status -Deep    # whole-tree residual deny ACE scan
pwsh -NoProfile -File .\scripts\lock-external-repos.ps1 -RefreshBaseline -WhatIf
pwsh -NoProfile -File .\scripts\lock-external-repos.ps1 -RefreshBaseline
```

`-Unlock` removes the root deny ACE and repairs residual descendant ACEs left by failed propagation, so it needs an elevated shell; re-locking requires an explicit `-Lock`. `-RefreshBaseline` previews the reviewed plan, refuses to write while any repository check is blocked, and replaces the baseline atomically. AI sessions do not change ACLs and do not re-pin the baseline on their own; both are explicit, user-authorized actions.

Checkout discovery skips reparse points, so a shelf path that has become a junction is legitimately replaced by its canonical `_shared/repos/<name>` entry. Two causes of drift are expected rather than defects, both observed on 2026-10-16:

- checkouts move into the shared canonical root `_shared/repos/`, leaving junctions behind in the project shelves;
- a maintenance `-Mode Advance` run fast-forwards floating checkouts, while `-Mode Observe` only refreshes inventory and state and fetches, so it does not move `HEAD`.

Recovery order after an expected advance: confirm no maintenance process is running, preview with `-RefreshBaseline -WhatIf`, apply, then re-run `verify-reference-governance.ps1` and require exit 0.

Re-pinning stays an explicit operator step. The maintenance job never refreshes the baseline itself, because the actor that advances floating checkouts must not author the value the verifier checks; an automatic re-pin would make the drift check unable to fail. The scheduled Advance job is paused, so an advance is a rare, reviewed event whose re-pin lands as its own commit. If that job is ever re-scheduled unattended, it should emit a re-pin receipt for review instead of writing the baseline silently.

## Admission and removal

Add a repository only when a current consumer needs source-level comparison and existing first-party references are insufficient. Record name, tier, URL, contained path, `consumer`, and `retirement_trigger`; verify license and revision during the task. Promote to core only for repeated current use.

Removing a manifest entry does not delete an external checkout and does not remove a runtime source/import. Those are separate, explicitly authorized operations.
