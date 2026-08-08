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
- `conditional-not-cloned`：`workspace-hub`、`aktsmm-agent-skills`、`manim-skill`、`playwright-best-practices-skill`、`supabase-agent-skills`、`antd-skill`、`slidev`、`knowledge-work-plugins`、`remotion-skills`、`anthropics-k12-teacher-skills`、`community-accessibility-agents`、`iofficeai-officecli`、`emilkowalski-skills`、`tirth8205-code-review-graph`、`codex-watchdog`、`polly`、`temporal-dotnet`、`hangfire`、`quartznet`、`uptime-kuma`、`mcp-csharp-sdk`

默认只刷新 manifest 的 `core-default` 集合，不把所有 runtime source repo 都自动升级成长期镜像参考棚。

`reference-refresh-latest.md` 只代表最近一次默认 `core-default` 刷新。报告中的 `remote refs current` 表示 fetch 成功，`working tree matches upstream` 才表示当前 checkout 已追平；审计和复制时使用完整的 `consumable revision`，不能把 fetch-only 误读为工作树已更新。

常用命令：

```powershell
.\scripts\verify-reference-governance.ps1
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier conditional -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -RepoNames <registered-candidate> -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier historical -FetchOnly -SkipDirtyRepos
```

规则：

- 默认不带参数时，使用 manifest 的 `default_refresh_set`，也就是稳定的 `core-default`
- 指定 `-Tier secondary` / `-Tier conditional` 时，会生成单独历史报告，但不会覆盖 `references/updates/reference-refresh-latest.md`
- `historical-compatibility` 只能显式刷新；其内容不作为新能力推荐或默认安装来源
- 现有资料不足且源码级比对有明确收益时，可以自主发现公开开源候选；必须先把 URL、完整 review revision、license、触发条件、review evidence 和采纳决定登记为 `conditional-not-cloned`，再按名称克隆到 manifest 控制的 `conditional/` 路径
- 来源或许可证不明、需要认证、目录冲突、已有 checkout 脏或没有当前消费者时阻断；克隆只授权只读比对，不等于采纳、安装、执行或进入默认长期镜像
- Portfolio lifecycle：`discover -> conditional-not-cloned -> on-demand read-only -> secondary/core-mainline -> historical-compatibility -> retire/remove`；晋级需要第一方权威或重复当前消费者，官方替代、长期无消费者、重复、stale、许可证/供应链风险或维护成本过高时降级/退役
- 先降级、停刷或保留 historical evidence，再删除干净且 manifest-controlled 的 checkout；reference checkout 删除、manifest 删除和 `skills.json` runtime/import 删除是独立事务，不得联动误删
- Owned-root boundary：只管理 `D:\CODE\external\skills-manager-references` 内 manifest 登记路径；`D:\CODE\external` 根、兄弟 `*-references`、`_shared` 和产品 checkout 只可按显式映射只读查阅，不纳入自动 refresh/move/delete
