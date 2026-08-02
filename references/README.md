# references

这个目录保存 `skills-manager` 的外置参考仓治理入口，不保存上游源码本体。

外部参考仓源码当前约定放在：

- `D:\CODE\external\skills-manager-references`

当前 repo-side 真源入口：

- [reference-shelf.manifest.json](D:/CODE/skills-manager/references/reference-shelf.manifest.json)：参考棚根路径、默认刷新集合、分层与上游映射真源
- [updates/README.md](D:/CODE/skills-manager/references/updates/README.md)：参考仓刷新摘要与稳定入口说明
- [docs/EXTERNAL_REFERENCE_REPO_TIERS.md](D:/CODE/skills-manager/docs/EXTERNAL_REFERENCE_REPO_TIERS.md)：为什么这样分层、哪些仓应该保留/降级/仅发现
- [scripts/refresh-reference-repos.ps1](D:/CODE/skills-manager/scripts/refresh-reference-repos.ps1)：刷新和按需补齐本地参考棚的脚本入口

当前默认分层口径：

- `core-mainline`：`codex`、`openai-plugins`、`anthropics-skills`、`gemini-cli`、`agentskills`、`modelcontextprotocol`、`registry`
- `historical-compatibility`：`openai-skills`；只用于现有 runtime mapping 和迁移取证，不进入默认刷新或新安装推荐
- `secondary`：`servers`、`vercel-agent-skills`、`obra-superpowers`、`wshobson-agents`、`mattpocock-skills`、`trailofbits-skills`、`awesome-copilot`
- `conditional-not-cloned`：`workspace-hub`、`aktsmm-agent-skills`、`manim-skill`、`playwright-best-practices-skill`、`supabase-agent-skills`、`antd-skill`、`slidev`、`knowledge-work-plugins`、`remotion-skills`

默认只刷新 `core`，不把所有 runtime source repo 都自动升级成长期镜像参考棚。

物理 clone/fetch 状态以最近一次 `reference-refresh-latest.md` 为准，不把机器瞬时状态固化为长期治理结论。

常用命令：

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier conditional -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier historical -FetchOnly -SkipDirtyRepos
```

规则：

- 默认不带参数时，使用 manifest 的 `default_refresh_set`，也就是稳定的 `core-default`
- 指定 `-Tier secondary` / `-Tier conditional` 时，会生成单独历史报告，但不会覆盖 `references/updates/reference-refresh-latest.md`
- `historical-compatibility` 只能显式刷新；其内容不作为新能力推荐或默认安装来源
