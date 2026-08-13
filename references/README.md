# Reference shelf

`reference-shelf.manifest.json` lists the current read-only comparison repositories under `D:\CODE\external\skills-manager-references`.

- `core-mainline`: `codex`, `openai-plugins`, `anthropics-skills`, `gemini-cli`, `agentskills`, `modelcontextprotocol`, `registry`
- `secondary`: `servers`, `vercel-agent-skills`, `obra-superpowers`, `wshobson-agents`, `mattpocock-skills`, `trailofbits-skills`, `awesome-copilot`

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\verify-reference-governance.ps1
```

Refresh verifies path containment, origin identity and dirty state. It does not adopt, install, execute, activate, or remove runtime sources. Candidates without a current consumer are not kept in the manifest; rediscover them when needed.

`updates/reference-refresh-latest.md` is the stable pointer for the latest default refresh. Dated refresh reports are runtime history and should not be accumulated in Git.
