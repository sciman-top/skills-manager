# External Reference Repo Tiers

## 1. Purpose

This document defines how `skills-manager` should manage long-lived external reference repos without confusing them with the runtime source of truth.

- Runtime truth stays in `skills.json`.
- External reference repos are evidence and comparison inputs for future review, not the authoritative install source.
- Discovery sites and trend feeds can suggest candidates, but they do not justify install or long-lived mirroring on their own.

## 2. Boundary

### 2.1 Runtime truth vs reference shelf

- `skills.json` remains the only repo-owned truth for `vendors`, `imports`, `mappings`, `targets`, `mcp_servers`, and `mcp_targets`.
- `vendor/` and `imports/` are runtime materialization layers for installed content. They are not the same thing as a curated reference shelf.
- The dedicated external shelf for this repo lives under `D:\CODE\external\skills-manager-references`.
- Do not delete a currently used repo from `skills.json` just because it is not part of the default long-lived reference shelf.
- Repo-side governance entrypoints live in:
  - `references/reference-shelf.manifest.json`
  - `references/README.md`
  - `references/updates/README.md`
  - `scripts/refresh-reference-repos.ps1`

### 2.2 Current snapshot (2026-07-06)

The current runtime source surface is intentionally broader than the recommended persistent reference shelf:

- `9` vendor repos in `skills.json`
- `46` import entries
- `33` unique import repos
- `28` import repos currently contribute only `1` skill each

Implication:

- The runtime source set is optimized for installed capability coverage.
- The long-lived external reference shelf should be much narrower and tiered by authority, reuse frequency, and maintenance cost.

## 3. Source hierarchy

Use this order when reviewing whether a skill repo should be mirrored locally for long-term reference:

1. Official platform semantics and protocol specs
2. Official or first-party implementation repos
3. Strong multi-skill community repos with repeated local reuse
4. Narrow specialist repos only when the corresponding workstream is active
5. Discovery-only indexes or trend feeds

## 4. Recommended shelf layout

The external shelf stays outside this repo:

```text
D:\CODE\external\skills-manager-references\
  core\
  secondary\
  conditional\
```

Discovery-only sources are not cloned by default.

Default operational commands:

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
```

Meaning:

- first command: refresh the default `core` set without creating new clones
- second command: bootstrap missing `core` repos, then fetch them
- third command: bootstrap or refresh the `secondary` tier without disturbing the stable `core-default` latest report

## 5. Core tier

Keep these as the default, high-signal, long-lived reference set. They define platform semantics, protocol contracts, or first-party skill structure across the current tool boundary.

| Repo / Source | Why it belongs in core | Refresh | Relation to `skills.json` |
| --- | --- | --- | --- |
| `openai/codex` | Codex runtime, `AGENTS.md`, skills, config, and workflow semantics | Weekly or before Codex workflow/governance changes | Not a current runtime source repo; add as reference shelf |
| `openai/plugins` | Current first-party plugin, skill, MCP and packaging examples | Weekly or before plugin/skill governance changes | Current official reference; do not copy its public directory into runtime truth |
| `anthropics/skills` | First-party Claude skill structure and strong cross-tool examples | Weekly or before skill packaging changes | Keep in `skills.json`; also belongs in reference shelf |
| `google-gemini/gemini-cli` | Official Gemini CLI rule-loading and `GEMINI.md` semantics | Weekly or before Gemini wrapper changes | Not a current runtime source repo; add as reference shelf |
| `modelcontextprotocol/modelcontextprotocol` | MCP spec source of truth | Weekly or before MCP governance changes | Not a current runtime source repo; add as reference shelf |
| `modelcontextprotocol/servers` | Official MCP server examples and packaging patterns | Weekly or before MCP add/remove decisions | Not a current runtime source repo; add as reference shelf |
| `modelcontextprotocol/registry` | Official server discovery/catalog truth when checking MCP availability | Weekly or before MCP recommendation changes | Not a current runtime source repo; add as reference shelf |

Related official docs that should be treated as first-party truth even without local clone:

- [OpenAI AGENTS.md Guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [OpenAI Plugins](https://learn.chatgpt.com/docs/plugins)
- [OpenAI Plugin architecture](https://developers.openai.com/plugins/concepts/plugins)
- [Anthropic Claude Code Skills](https://docs.anthropic.com/en/docs/claude-code/skills)
- [Gemini CLI GEMINI.md](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/gemini-md.md)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/specification/2025-11-25)
- [Agent Skills Best Practices](https://agentskills.io/skill-creators/best-practices)

### 5.1 Historical compatibility

`openai/skills` is deprecated upstream in favor of `openai/plugins`. Keep its existing clone and any still-used `skills.json` mapping intact until a separate runtime migration proves replacements. It is not in `default_refresh_set`, must be refreshed explicitly with `-Tier historical`, and must not be recommended as the current official source.

## 6. Secondary tier

Keep these when repeated local use justifies persistent comparison material, but do not treat them as always-on core truth.

Current local state on this machine as of `2026-07-06`:

- the `secondary` tier has been cloned under `D:\CODE\external\skills-manager-references\secondary`
- it is intentionally still outside the default refresh set

| Repo / Source | Why it belongs in secondary | Refresh | Relation to `skills.json` |
| --- | --- | --- | --- |
| `vercel-labs/agent-skills` | Reused high-quality engineering skills; already part of runtime truth | Monthly or before frontend/React guidance changes | Keep in `skills.json`; secondary shelf candidate |
| `obra/superpowers` | Reused workflow/meta-skills; already part of runtime truth | Monthly or before process/governance changes | Keep in `skills.json`; secondary shelf candidate |
| `wshobson/agents` | Highest current multi-skill import density outside primary vendors | Monthly or before Python/backend workflow changes | Keep current imports; secondary shelf candidate |
| `mattpocock/skills` | Repeated planning/productivity imports with clear reuse value | Monthly or before planning workflow changes | Keep current imports; secondary shelf candidate |
| `trailofbits/skills` | High-signal modern engineering guidance; currently used for `modern-python` | Monthly or before Python tooling decisions | Keep current import; secondary shelf candidate |
| `github/awesome-copilot` | Official GitHub-owned source; already used for `mcp-cli` and relevant to shared MCP/Copilot workflows | Monthly or before GitHub/Copilot workflow changes | Keep current import; secondary shelf candidate |
| `anthropics/claude-plugins-official` | Official plugin examples if Claude plugin governance becomes an active lane | On demand until plugin work is active, then monthly | Not a current runtime source repo; conditional promotion path from docs to local clone |

## 7. Conditional tier

These sources are useful, but they should not be part of the default persistent shelf unless the matching workstream is active or repeated.

| Repo / Source | Current use | Default policy |
| --- | --- | --- |
| `vamseeachanta/workspace-hub` | `openpyxl`, `python-pptx`, `python-docx` | Clone or refresh only when Office artifact work is active |
| `aktsmm/agent-skills` | `powerpoint-automation`, `drawio-diagram-forge` | Keep because these skills are installed; do not mirror as default shelf unless PPT/diagram work is active |
| `adithya-s-k/manim_skill` | `manimce-best-practices`, `manim-composer` | Refresh only when Manim work is active |
| `currents-dev/playwright-best-practices-skill` | `playwright-best-practices` | Refresh only when Playwright-heavy debugging is active |
| `supabase/agent-skills` | `supabase-postgres-best-practices` | Refresh only when Supabase/Postgres work is active |
| `ant-design/antd-skill` | `ant-design` | Refresh only when Ant Design work is active |
| `slidevjs/slidev` | `slidev` | Refresh only when Slidev work is active |
| `anthropics/knowledge-work-plugins` | `data-visualization` | Refresh only when knowledge-work/plugin pattern review is active |
| `remotion-dev/skills` | `remotion-best-practices` | Keep runtime source; refresh only when Remotion/video work is active |

Current singleton or narrow-source imports that should default to conditional, not persistent mirroring:

- `affaan-m/everything-claude-code` -> `windows-desktop-e2e`
- `jarmen423/skills` -> `d3-viz`
- `mblode/agent-skills` -> `ui-animation`
- `rmyndharis/antigravity-skills` -> `dotnet-backend-patterns`
- `snakeo/claude-debug-and-refactor-skills-plugin` -> `debug-dotnet`
- `intellectronica/agent-skills` -> `markdown-converter`
- `inference-sh-6/skills` -> `storyboard-creation`
- `op7418/guizang-ppt-skill` -> `guizang-ppt-skill`
- `hugohe3/ppt-master` -> `ppt-master`
- `Leonxlnx/taste-skill` -> `design-taste-frontend`

Default rule:

- Keep the installed import if it still serves a real workflow.
- Do not automatically maintain a separate long-lived mirror for every singleton source repo.

## 8. Discovery-only tier

These sources are valuable for search and candidate generation, but they should not be treated as persistent local mirror targets by default.

| Source | Use | Default policy |
| --- | --- | --- |
| `skills.sh` | Find packaged skills and compare metadata | Do not clone; use as discovery input only |
| GitHub Trending monthly | Spot active projects | Do not clone from popularity alone |
| `VoltAgent/awesome-agent-skills` | Broad landscape scan | Do not clone by default; use as survey material only |
| Generic best-practice articles | Compare approaches | Cite in audit reasoning; do not mirror as repo shelf |

## 9. What should change now

### 9.1 Add to the long-lived reference shelf first

If a dedicated shelf is created or refreshed, add these first:

1. `openai/codex`
2. `openai/plugins`
3. `google-gemini/gemini-cli`
4. `modelcontextprotocol/modelcontextprotocol`
5. `modelcontextprotocol/registry`
6. `anthropics/skills` if it is not already represented outside runtime cache
7. `modelcontextprotocol/servers` if it is not already represented outside runtime cache

`openai/skills` remains historical compatibility evidence only; do not bootstrap it as a current source.

### 9.2 Keep, but do not widen by default

Keep these sources available through current runtime config and imports, but do not automatically promote them into the default persistent mirror set:

- `wshobson/agents`
- `mattpocock/skills`
- `trailofbits/skills`
- `workspace-hub`
- `aktsmm/agent-skills`
- `adithya-s-k/manim_skill`
- the current singleton specialist repos listed in section 7

### 9.3 Do not remove from `skills.json` yet

No immediate repo should be removed from `skills.json` purely based on this governance pass, because:

- this document governs the reference shelf, not the runtime install truth
- several narrow sources still map to active installed skills
- removal should happen only after a separate usage and replacement review

## 10. Promotion and removal rules

Promote a repo to persistent mirroring when at least one of these is true:

- it is first-party for a platform or protocol we actively govern
- it defines rule-loading, skill packaging, or MCP semantics used across tools
- more than one installed skill or repeated audit recommendations depend on it
- it is repeatedly cited during cross-repo audits over multiple sessions

Keep a repo out of persistent mirroring, or remove it from the default shelf, when all of these are true:

- it is narrow or singleton
- it is not first-party
- it has low repeat use across recent work
- another already-mirrored source covers the same decision surface with higher authority

## 11. Review cadence

- Core: weekly, or before any rule/governance/MCP packaging change
- Secondary: monthly, or before related domain work
- Conditional: only when the corresponding workstream is active
- Discovery-only: no scheduled refresh; consult on demand

## 12. Operational rule

For `skills-manager`, the stable answer is:

- runtime truth stays broad enough to preserve installed workflows
- the external reference shelf stays narrow, tiered, and authority-first
- default local mirroring should favor first-party semantics and repeated reuse, not the broadest possible list of interesting repos
