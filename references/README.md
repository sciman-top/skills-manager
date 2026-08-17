# Reference shelf

This directory describes an optional, read-only development cache under `D:\CODE\external\skills-manager-references`. It is not runtime state or a prerequisite for build, test, update, or projection; `skills.json` remains the runtime source of truth.

`reference-shelf.manifest.json` is consulted only when refresh or governance verification is invoked explicitly. A missing external checkout therefore means "reference unavailable for this research task", not "product unavailable".

- `core-mainline`: `codex`, `openai-plugins`, `anthropics-skills`, `gemini-cli`, `agentskills`, `modelcontextprotocol`, `registry`
- `secondary`: `servers`

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\verify-reference-governance.ps1
```

Refresh verifies path containment, origin identity and dirty state. Failure blocks only that explicit refresh/verify run. It does not adopt, install, execute, activate, or remove runtime sources. Candidates without a current consumer are not kept in the manifest; rediscover them when needed.

`updates/reference-refresh-latest.md` is the stable pointer for the latest default refresh. Dated refresh reports are runtime history and should not be accumulated in Git.
