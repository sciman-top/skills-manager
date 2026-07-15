# 20260715 audit candidate research: 20260715-201159-374

## Goal and truth boundary

- Research target: `reports/skill-audit/20260715-201159-374`.
- Current landing point: candidate research only. This report does not create or modify `recommendations.json` and does not run preflight, dry-run, apply, install, uninstall, sync, or host projection.
- Decision rule: a discovery page can nominate a candidate, but cannot support a decision by itself. Any add/remove candidate must also match the fresh user profile, target-repo facts, installed state, and at least two independent HTTP primary sources inspected in this run.
- Result: the four change categories are all no-op. This is a research conclusion, not a persisted audit recommendation and not permission to apply changes.

## Fresh input evidence

All five required inputs were read in full and parsed successfully before external research.

| Input | SHA-256 | Relevant facts |
| --- | --- | --- |
| `user-profile.json` | `89EA8A484A5A3C7659D25DCA1DC002FAC99D62E0A01D0ECA8C17A63943A84F77` | Windows-first teacher workflows; PPT/PPTX, WPF/.NET, WeChat/Zhihu, Web/SVG/Manim, multi-agent governance; MCP should be local, controllable, reversible, and verifiable. |
| `repo-scans.json` | `15EB0A2940B5091CB05C4B2BC0E1BF973E78DE7C5C4CE18A526D30CF3E79BED1` | 9 clean `main` repositories. The set covers .NET/WPF, Python, React/Vite, Playwright, document/OCR, spreadsheet import, Docker, backup/migration, and multi-repo orchestration. `k12-question-graph` remains `design_package_only`. |
| `installed-skills.json` | `BB401B052458F8B31AAF12DD366A2214CB702373FAF026EC6FD303441FAF1D8E` | 108 managed skills, 13 external system/plugin skills, 7 repo-managed MCP servers. Enabled MCP: `microsoft-learn`, `openaiDeveloperDocs`; disabled: `context7`, `github`, `playwright`, `filesystem`, `codebase-memory-mcp`. |
| `source-strategy.json` | `BFDF8848C0D7DC3FBFB49D18879DCC808EFF76EE5DC7316C8880D4868D6C9BB3` | Requires primary/provider/security sources, HTTP evidence, source observations, and at least two unique sources for change decisions. |
| `decision-insights.json` | `8F832DD23A0E8C3005E08FA7B3857E442D1484CB8AC1F0BFE00C1B945A5C9461` | 121 total skill capabilities (managed plus external), 7 MCP servers, and `missing_preferred_agents=[]`. All 11 preferred agents in the user profile are present. |

Repository truth checked in addition to the audit package:

- `skills.json` has `filesystem.enabled=false`, a read-only client allowlist (`read_text_file`, `read_multiple_files`, `list_directory`, `directory_tree`, `search_files`, `get_file_info`), and root `D:\CODE`.
- `filesystem` is absent from every `mcp_profiles.profiles.*.enabled` list. The active `default` MCP profile enables only `microsoft-learn` and `openaiDeveloperDocs`.
- `mcp_targets=[]` does not prove that MCP has no managed targets: `Get-McpTargetCandidatePaths` also includes `cfg.targets`. Therefore removal impact is not isolated to Codex and cannot be inferred from the empty array.
- `skill_projection.managed_link_excludes` already excludes `anthropics-skills-skills-skill-creator` from the Codex user-skill projection, mitigating the built-in-name collision without deleting the managed cross-host source.
- `config/skill-routing-policy.json` already separates domain routers, workflow skills, validators, file executors, and privileged operators.

## Four change categories

| Category | Decision | Evidence-based reason |
| --- | --- | --- |
| New managed/custom skills | `[]` | Every preferred agent is installed. The 9 repos' detected stacks and capabilities are already covered by domain routers, implementation/reference skills, validators, and Codex-specific external plugins. No researched candidate provided a non-duplicative, cross-repo increment. |
| Managed/custom skill removals | `[]` | Low keyword score is not usage telemetry. The apparent `pdf` and `skill-creator` duplicates have different ownership: managed skills remain portable/cross-host assets, while system/plugin skills are read-only Codex/OpenAI-surface capabilities. Current projection already suppresses the managed `skill-creator` collision for Codex. |
| New repo-managed MCP servers | `[]` | Official Microsoft and OpenAI docs are already enabled. GitHub, general-library docs, browser automation, filesystem access, and codebase memory already exist as disabled on-demand entries. MarkItDown/Desktop Commander add permission surface without a demonstrated workflow gap. |
| Repo-managed MCP removals | `[]` | Disabled entries are not enough to prove retirement. `filesystem` and Playwright retain bounded fallback value; GitHub and Context7 retain scoped source gaps; codebase memory matches multi-repo work. No candidate had cross-host usage telemetry plus verified projection-impact evidence sufficient for removal. |

## Candidate decisions and independent sources

### Managed/custom skills

| Candidate | Decision | Primary/independent sources inspected | Decision and counterevidence |
| --- | --- | --- | --- |
| Managed `pdf` versus `pdf@openai-primary-runtime::pdf` | `overlap` + `keep` | [Anthropic `pdf` skill](https://github.com/anthropics/skills/blob/main/skills/pdf/SKILL.md); [OpenAI Build skills](https://learn.chatgpt.com/docs/build-skills); [OpenAI customization: skills](https://learn.chatgpt.com/docs/customization/overview#skills) | OpenAI documents that same-name skills are not merged and that plugins should be reused on OpenAI surfaces. That establishes overlap, not cross-host redundancy. The external plugin adds Codex artifact render/verify behavior; the managed skill remains a portable PDF workflow for Claude/Gemini/Trae-style projections and matches the user's frequent document work. Removal rejected. |
| Managed `pptx` / `docx` / `xlsx` versus Codex document plugins | `overlap` + `keep` | [Anthropic Skills repository](https://github.com/anthropics/skills); [OpenAI Build skills](https://learn.chatgpt.com/docs/build-skills); [OpenAI Build plugins](https://learn.chatgpt.com/docs/build-plugins) | The managed skills provide portable file workflows across managed hosts. OpenAI plugins are installable OpenAI-surface distributions with their own bundled runtimes and qualified identities; they are complementary current-host executors, not evidence that the managed sources are unused elsewhere. The user's PPT/document/spreadsheet workflows and target-repo document/spreadsheet capabilities are affirmative keep evidence. |
| Managed `skill-creator` versus Codex system `skill-creator` | `overlap` + `keep` | [Anthropic `skill-creator`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md); [OpenAI Build skills](https://learn.chatgpt.com/docs/build-skills) | OpenAI identifies `skill-creator` as a SYSTEM built-in and states that same-name skills both appear rather than merge. Anthropic's managed skill also includes evals, benchmarks, variance analysis, and description optimization. The repo already excludes the managed link from Codex projection, so deleting the cross-host/eval-capable source would remove value without reducing current Codex exposure. |
| `powerpoint-automation` | `keep` + routed operator | [Microsoft PowerPoint solutions](https://learn.microsoft.com/visualstudio/vsto/powerpoint-solutions?view=visualstudio); [Microsoft unattended Office automation considerations](https://learn.microsoft.com/office/client-developer/integration/considerations-unattended-automation-office-microsoft-365-for-unattended-rpa) | This skill owns interactive Windows PowerPoint/COM operation, which is distinct from courseware planning and file-generation executors. The user's workflow explicitly includes Windows PowerPoint. Keep it as an explicitly selected operator, but do not route it into unattended/server-side Office automation; Microsoft's guidance documents stability and security limitations for unattended Office automation. |
| `ant-design` | `keep` | [official Ant Design skill repository](https://github.com/ant-design/antd-skill); [Ant Design React documentation](https://ant.design/docs/react/introduce/) | Its decision-insights score of 0 is keyword-match output, not long-term usage telemetry. `k12-question-graph` has React/Vite facts, and the official Ant Design product/skill sources remain current. Without a measured zero-trigger observation window or a replacement analysis, removal is unsupported. |
| Remotion leaf skills as additional independent root installs | `do_not_install` | [Remotion root skill](https://github.com/remotion-dev/skills/blob/main/skills/remotion-best-practices/SKILL.md); [OpenAI Build skills](https://learn.chatgpt.com/docs/build-skills); [Remotion license](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md) | The installed root skill already routes to create/render/captions/markup/interactivity/Mediabunny leaf instructions. Registering the leaves again as independent roots adds selector/context competition without a repo scan showing a Remotion project. Keep the root route, and review Remotion's entity-dependent license before commercial use. |
| Managed Playwright workflow | `keep` | [OpenAI Playwright skill](https://github.com/openai/skills/tree/main/skills/.curated/playwright); [Microsoft Playwright MCP/CLI comparison](https://github.com/microsoft/playwright-mcp) | `classroom-answer-toolkit` and `qq-codex-bot` both detect Playwright. Microsoft explicitly positions CLI + Skills as preferable for high-throughput coding agents, while MCP remains for persistent exploratory loops. This is complementary routing, not a removal case. |

### Repo-managed MCP

| Candidate | Decision | Primary/independent sources inspected | Decision and counterevidence |
| --- | --- | --- | --- |
| `filesystem` | `keep-disabled` + `overlap` | [MCP filesystem server](https://github.com/modelcontextprotocol/servers/blob/main/src/filesystem/README.md); [MCP reference-server positioning](https://github.com/modelcontextprotocol/servers); [MCP Security Best Practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices); [npm `npx` documentation](https://docs.npmjs.com/cli/v11/commands/npx/); [OpenAI permissions](https://learn.chatgpt.com/docs/permissions#define-and-select-a-profile) | Risk evidence is real: the upstream server can write/move files, the reference servers are not production-ready, `D:\CODE` is a broad root, and `npx -y` can fetch a missing unpinned package while suppressing the prompt. Counterevidence is also material: repo policy keeps it disabled, outside all profiles, and restricts exposed tools to reads; Codex already has workspace-scoped local filesystem permissions, but equivalent coverage and removal impact are not proven for every managed target. Keep disabled; do not expand the root; pin an audited package version before any future enablement. |
| `playwright` MCP | `keep-disabled` | [Microsoft Playwright MCP](https://github.com/microsoft/playwright-mcp); [MCP Security Best Practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices); [OpenAI customization: skills and MCP](https://learn.chatgpt.com/docs/customization/overview#skills) | The current entry already uses `--isolated` and a narrow browser-tool allowlist. CLI/skill is the default for coding and tests; MCP retains distinct value for persistent structured exploration. It is in the explicit `browser` profile rather than the active default. Before enabling, replace `@latest` with a reviewed version and continue to treat origin lists as convenience controls, not a security boundary. |
| `github` MCP | `keep-disabled` | [GitHub MCP Server](https://github.com/github/github-mcp-server); [GitHub PAT management](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) | Nine Git repos and `github-toolkit` justify retaining an on-demand semantic GitHub route. The repo allowlist is read-only, but a token still needs minimum scopes, a dedicated secret, rotation, and no repository persistence. Disabled-by-default is the correct permission boundary; there is no removal evidence. |
| `context7` MCP | `keep-disabled` | [Context7 data privacy](https://context7.com/docs/security/data-privacy); [Context7 troubleshooting](https://context7.com/docs/resources/troubleshooting) | It can fill versioned documentation gaps outside Microsoft/OpenAI, but queries and client metadata leave the machine and Windows/Node startup adds operational cost. Retain only as an explicit coding-profile fallback, with secrets removed from queries. |
| `codebase-memory-mcp` | `keep-disabled` | [Codebase Memory MCP](https://github.com/DeusData/codebase-memory-mcp); [Codebase Memory security policy](https://github.com/DeusData/codebase-memory-mcp/blob/main/SECURITY.md); [releases](https://github.com/DeusData/codebase-memory-mcp/releases) | The capability fits large multi-repo work but reads deeply, writes agent configuration/state, and runs a local process. The snapshot launcher does not prove binary version, checksum, or provenance. Keep disabled until those are verified; lack of attestation is not, by itself, proof that the catalog entry should be deleted. |
| Microsoft MarkItDown MCP | `do_not_install` | [MarkItDown MCP README](https://github.com/microsoft/markitdown/blob/main/packages/markitdown-mcp/README.md); [MarkItDown core README](https://github.com/microsoft/markitdown); [OpenAI customization: skills and MCP](https://learn.chatgpt.com/docs/customization/overview#skills) | The server exposes one local conversion tool accepting `file:`, `http:`, `https:`, and `data:` URIs, has no authentication, and runs with the user's permissions. Current managed `markdown-converter` and format-specific document/PDF/presentation/spreadsheet workflows already cover the need. A local repeatable conversion workflow belongs in skill/CLI routing unless a live external-system gap is demonstrated. |
| Desktop Commander MCP | `do_not_install` | [Desktop Commander security model](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/SECURITY.md); [MCP Security Best Practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices) | Its own security policy calls it privileged local automation: arbitrary terminal commands are first-class, directory and command restrictions are guardrails rather than a sandbox, and it does not distinguish user intent from prompt injection. This directly conflicts with the user's avoidance of high-permission desktop control without a boundary and rollback. Existing native shell/file tools plus explicit `computer-use` routing already cover bounded cases. |
| Microsoft WinAppDriver | `do_not_install` (not an MCP) | [Microsoft WinAppDriver README](https://github.com/microsoft/WinAppDriver); [official releases](https://github.com/microsoft/WinAppDriver/releases); [maintenance status issue](https://github.com/microsoft/WinAppDriver/issues/1550) | It requires Windows Developer Mode and a local service; non-default listening requires administrator privileges. Current WPF routing already separates implementation, UI Automation validation, and explicit desktop operation. Do not add it to the skill/MCP catalog absent a concrete compatibility gap and a maintained release path. |

## Routing decisions

1. **PPT/courseware:** `custom-teacher-courseware-ppt` is the domain router. Use one primary executor per deck: the OpenAI `Presentations` plugin on a supported Codex surface, managed `pptx` as cross-host/file fallback, `powerpoint-automation` only for an explicitly opened Windows PowerPoint/COM workflow, and `baoyu-slide-deck` for bitmap-oriented output.
2. **PDF/documents:** prefer the host plugin when its render-and-verify runtime is available; retain managed `pdf`/`docx`/`xlsx`/`pptx` as portable workflows. Do not infer deletion from a same base name.
3. **Skill authoring:** use Codex's system `skill-creator` on Codex; retain the managed Anthropic skill for cross-host and evaluation/benchmark workflows. The existing `managed_link_excludes` entry remains the collision control.
4. **Browser:** use managed Playwright CLI for isolated terminal testing; `playwright-best-practices` for test design; in-app Browser for Codex-owned web state; Chrome control only for existing authenticated Chrome state; `computer-use` only when browser-native paths cannot complete the authorized operation. Never run multiple operators against the same profile.
5. **Windows desktop:** `custom-windows-wpf-teacher-app` is the domain workflow, `windows-desktop-e2e` is the validator, and `computer-use` is a privileged current-host operator. Production teaching data and automation test desktops must remain separate.
6. **Technical docs:** use `microsoft-learn` for Microsoft and `openaiDeveloperDocs` for OpenAI. Use Context7 only for a specific third-party version gap after query redaction.

## Discovery-source boundary

- `skills.sh` and GitHub Trending monthly were inspected as discovery inputs. Their current pages did not provide decision-grade evidence for any non-duplicative candidate.
- Popularity, download counts, rankings, and discovery-page descriptions were not used to support keep/remove/install decisions.
- GitHub repository metadata was used only to check maintenance, license, archived state, and source ownership. Behavioral and permission conclusions came from the projects' own docs/security files plus independent platform/security guidance.

## Residual risks and recovery conditions

- There is no long-term per-skill trigger telemetry in the fresh package. A low keyword score cannot prove that a skill is unused. Removal should require a measured observation window and cross-host impact review.
- Disabled MCP entries still contain mutable package selectors (`npx -y` without a version and `@latest`). Before enabling one, pin a reviewed version, record its digest/provenance, and rerun the normal MCP sync/verification workflow under explicit authorization.
- `filesystem` remains broad at `D:\CODE`, but its current effective controls are fail-closed: disabled, absent from profiles, and read-only allowlisted. Reconsider removal only after proving no managed target needs the portable interface and after mapping target fallback behavior.
- Context7 has privacy/external-query implications; GitHub has token-scope implications; codebase memory has privileged local-read and supply-chain implications. Their disabled state is part of the decision and must not be silently changed.
- This report's rollback is deletion of this report only. No generated audit bundle, source file, configuration, host setting, or runtime state was changed.

## Source ledger (inspected 2026-07-15)

- OpenAI: [Build skills](https://learn.chatgpt.com/docs/build-skills), [Build plugins](https://learn.chatgpt.com/docs/build-plugins), [Customization / Skills](https://learn.chatgpt.com/docs/customization/overview#skills), [Permissions](https://learn.chatgpt.com/docs/permissions#define-and-select-a-profile).
- Anthropic: [`pdf`](https://github.com/anthropics/skills/blob/main/skills/pdf/SKILL.md), [`skill-creator`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md), [skills repository](https://github.com/anthropics/skills).
- Ant Design: [official skill repository](https://github.com/ant-design/antd-skill), [React documentation](https://ant.design/docs/react/introduce/).
- MCP Steering Group: [filesystem README](https://github.com/modelcontextprotocol/servers/blob/main/src/filesystem/README.md), [reference-server README](https://github.com/modelcontextprotocol/servers), [Security Best Practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices).
- npm: [`npx` command](https://docs.npmjs.com/cli/v11/commands/npx/).
- Microsoft: [PowerPoint solutions](https://learn.microsoft.com/visualstudio/vsto/powerpoint-solutions?view=visualstudio), [unattended Office automation considerations](https://learn.microsoft.com/office/client-developer/integration/considerations-unattended-automation-office-microsoft-365-for-unattended-rpa), [Playwright MCP](https://github.com/microsoft/playwright-mcp), [MarkItDown](https://github.com/microsoft/markitdown), [MarkItDown MCP](https://github.com/microsoft/markitdown/blob/main/packages/markitdown-mcp/README.md), [WinAppDriver](https://github.com/microsoft/WinAppDriver).
- GitHub: [GitHub MCP Server](https://github.com/github/github-mcp-server), [PAT guidance](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
- Other candidate owners: [Remotion skills](https://github.com/remotion-dev/skills), [Remotion license](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md), [Context7 privacy](https://context7.com/docs/security/data-privacy), [Codebase Memory MCP](https://github.com/DeusData/codebase-memory-mcp), [Desktop Commander security](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/SECURITY.md).
- Discovery only: [skills.sh](https://skills.sh), [GitHub Trending monthly](https://github.com/trending?since=monthly).

## Verification

- Recomputed all five input SHA-256 values after writing this report: all matched the pre-research values above (`ALL_INPUTS_UNCHANGED=True`).
- Confirmed `reports/skill-audit/20260715-201159-374/recommendations.json` does not exist.
- Checked report structure: all required sections exist, the four change-category rows are present with `[]`, and 68 HTTP links are recorded.
- `git diff --check -- docs/change-evidence/20260715-audit-candidate-research-20260715-201159-374.md`: exit code 0.
- Latest `git status --short` shows this report and the independently created runtime-scan report as untracked. This task did not modify the runtime-scan report.
- `gate_na`:
  - `reason`: research-only Markdown evidence; the user explicitly prohibited audit preflight, dry-run, apply, and code/config/host mutations.
  - `alternative_verification`: JSON parse and hash checks, candidate/source coverage inspection, Markdown structure checks, and `git diff --check`.
  - `evidence_link`: this report and the exact hashes recorded above.
  - `expires_at`: before any recommendation persistence, config change, install/uninstall, sync, or apply action based on this research.
  - `recovery_condition`: if a later task authorizes a change, restart from a fresh audit package and run the repository's normal `build -> test -> contract/invariant -> hotspot` gates before persistence.
