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

All manifest entries are `active`. A repository without a current consumer is not kept as a conditional or historical record; rediscover and review it when a real task needs it.

## Refresh

```powershell
pwsh -NoProfile -File .\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
pwsh -NoProfile -File .\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
pwsh -NoProfile -File .\scripts\verify-reference-governance.ps1
```

Before network operations, refresh verifies manifest containment, repository identity, actual `origin`, and dirty state. Default refresh updates `references/updates/reference-refresh-latest.md`; custom/tier runs create a dated runtime report without replacing the stable pointer. These reports are reference-workflow receipts, not product health or release gates.

Clone/fetch/fast-forward only authorizes read-only comparison. It does not authorize dependency installation, script execution, skill/MCP adoption, runtime activation, host mutation, or deletion from `skills.json`.

## Admission and removal

Add a repository only when a current consumer needs source-level comparison and existing first-party references are insufficient. Record name, tier, URL and contained path; verify license and revision during the task. Promote to core only for repeated current use.

Removing a manifest entry does not delete an external checkout and does not remove a runtime source/import. Those are separate, explicitly authorized operations.
