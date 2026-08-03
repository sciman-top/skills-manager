# 2026-07-10 Skill / MCP 外部研究独立复核

## 1. 范围与结论

- 审查包：`reports/skill-audit/20260710-224146-955/`
- 复核对象：`recommendations.json` 中的 `microsoft-code-reference`、`postgres`、浏览器能力重叠，以及 `skills.sh` / GitHub Monthly Trending 是否存在更高价值缺口。
- 证据边界：外部判断只使用 Microsoft、OpenAI、Playwright、MCP Steering Group、NVIDIA 官方仓库/文档，以及 `skills.sh` 和 GitHub Trending 原页面；本地用途判断使用审查包与目标仓事实。
- 总结：当前四类 dry-run 数量 `技能新增 1 / 技能卸载 0 / MCP 新增 0 / MCP 卸载 0` 基本正确。唯一新增 `microsoft-code-reference` 有明确增量；`postgres` 只适合迁移期保留，不能恢复为默认常开或长期实现；Browser、Chrome、Playwright MCP 不应同时默认暴露。Trending 未发现应直接加入本轮四类清单的更高价值技能或 MCP。

### 1.1 受管真源与 Codex live 不是同一状态

- 2026-07-10 复核 `codex mcp list`：当前 Codex live 共 9 个可见 MCP，只有 `node_repl`、`microsoft-learn`、`openaiDeveloperDocs` 为 enabled；`context7`、`github`、`playwright`、`filesystem`、`postgres`、`codebase-memory-mcp` 均为 disabled。
- `node_repl` 不在 skills-manager 的 8 个受管 MCP 中。`skills.json` 的 8 个受管项均未显式声明 `enabled` 或 `enabled_tools`；按当前生成默认语义，它们仍等价于 `enabled=true` 且工具不受限。
- 审查包的 `installed-skills.json` / preflight 描述的是受管真源的有效投影，不是当前 live 启停快照。若现在运行同步，受管默认值可能覆盖 live 中 6 个服务的临时关闭。
- 所以后续修复应落到 `skills.json`/profile 真源，而不是只在 live 配置手工关闭；本研究没有执行同步或修改任何开关。

## 2. 逐项裁决

### 2.1 `microsoft-code-reference`：正确，建议新增

**裁决：正确，高置信度。**

- Microsoft 官方技能的声明职责是查找官方代码样例、核验 API 签名、修复 Microsoft SDK 错误，并显式覆盖错误方法、错误重载和弃用模式。[S1]
- 该技能直接使用 Microsoft Learn MCP 的 `microsoft_docs_search`、`microsoft_docs_fetch`、`microsoft_code_sample_search`；本机快照已经有 `microsoft-learn`，无需再新增 MCP。[S1][S2]
- 本机 `debug:dotnet` 是 ASP.NET Core/EF Core/诊断工具的静态排障指南，没有 Microsoft Learn MCP 的 API/样例检索工作流。两者有“修错”交集，但职责不等价。
- `ClassroomToolkit`、`k12-question-graph`、`ai-content-delivery-studio` 均有真实 .NET 代码，其中前两类教师软件还包含 WPF/Windows 目标；该技能的收益有目标仓证据，不是仅凭 Trending 扩张。
- `recommendations.json` 的官方仓库、`skills/microsoft-code-reference` 路径和 `main` ref 均与上游一致。[S1][S2]

建议仍按 Windows/.NET profile 使用，不把 Microsoft Learn MCP 设为所有任务的默认服务。官方端点支持 `maxTokenBudget`，可在后续 profile 投影时限制返回量。[S2]

### 2.2 `postgres`：暂不卸载正确，但只限迁移期

**裁决：有条件正确。**

- MCP Steering Group 明确把仓库服务器定位为参考实现而非生产方案，并已将 PostgreSQL server 移入 archived；归档实现只提供 schema 检查和 READ ONLY transaction 查询。[S3][S4]
- 因此“长期保留并默认常开”不成立，也不应把 `@modelcontextprotocol/server-postgres` 作为未来数据库 profile 的首选实现。
- 但本轮直接卸载同样不正确：`k12-question-graph/README.md` 和其 2026-05-18 证据已记录该 MCP 对 `k12_question_graph` 的实际只读诊断用途和成功查询；审查包也捕获了现有服务。立即卸载会破坏已验证的代理排障入口。
- 审查包捕获的受管投影仍会把连接串展开到子进程参数；`governed-ai-coding-runtime` 已有 `postgres_mcp_connection_string_not_in_process_args` 检查并将这种形态标为 attention。当前 Codex live 已改用 `mcp-postgres-env-wrapper.mjs` 且服务为 disabled，说明 live 侧已临时收紧，但该修复尚未回写受管真源。保留必须伴随真源默认关闭、凭据边界固化、替代实现验证和回滚，不应无限期延后。

所以 `mcp_removal_candidates=[]` 对这一次 dry-run 是正确的操作排序；它表示“先迁移再卸载”，不表示“把受管的八个 MCP 恢复为全部启用”。

### 2.3 Browser / Chrome / Playwright：不应同时默认常开

**裁决：正确。**

- Playwright 官方明确建议编码代理优先考虑 CLI + SKILL：CLI 避免加载大型工具 schema 和冗长 accessibility tree，更适合同时处理代码、测试与推理的高吞吐编码任务。[S5]
- 同一官方说明把 MCP 留给需要 persistent state、rich introspection、探索式自动化、自愈测试或长时间自治循环的任务。[S5]
- OpenAI 官方说明 plugin 可以同时捆绑 skills、apps、MCP servers、browser extensions 和 hooks；安装后可按任务显式选择插件，Codex CLI 也支持把已安装 plugin 打开或关闭。[S6]
- 因而当前最小分工合理：编码 E2E 默认 Playwright CLI skill；普通网页浏览选 Browser；只有依赖用户现有登录态时选 Chrome；需要持续浏览器状态时才开 Playwright MCP。这里的“每次选一个”是基于权限面和功能重叠的工程策略，不是官方宣称三者绝对互斥。

本轮 `MCP 卸载 0` 仍可接受，因为正确动作是 profile/开关收窄，而不是删除仍有按需用途的服务。OpenAI 配置支持 `enabled_tools`/`disabled_tools`，后者在前者之后应用。[S7]

## 3. `skills.sh` 与 GitHub Monthly Trending

### 3.1 没有应直接加入本轮的更高价值技能

2026-07-10 复核 `skills.sh/trending` 原页面后，与用户用途最相关的高位项目已被当前能力覆盖或缺少目标仓触发条件：[S8]

| 候选 | 判断 |
|---|---|
| `find-skills`、`frontend-design`、`vercel-react-best-practices`、`remotion-best-practices`、`supabase-postgres-best-practices` | 当前快照已有对应能力；不重复安装。 |
| `edit-article` | 与现有 `copy-editing`、`copywriting`、`custom-creator-publishing` 重叠，且其流程要求逐节确认，不适合作为无条件默认入口。[S9] |
| `ai-video-generation` | 依赖额外的 `belt` / `inference.sh` 登录和 40+ 外部模型，不是 PPT、物理动画或文章配图的必要增量；页面出现时间仅 3 天，当前不扩大供应链。[S10] |
| `hyperframes` 系列 | 面向 HTML/GSAP 视频合成，与现有 Remotion、Manim、Web 动画能力重叠；只有明确选择 HyperFrames 输出链时再评估。[S11] |
| Microsoft Azure / Foundry skills | 官方且质量较高，但需要 Azure/Foundry 部署、RBAC、配额或 MCP 操作；七仓扫描没有对应运行事实，不能因 Microsoft 品牌而预装。[S12] |

这支持 `do_not_install.additional-general-purpose-skills`，但应把 Trending 视为时点发现源，而不是长期排名或质量证明。

### 3.2 一个真实但应暂缓的 skill 候选

- GitHub Monthly Trending 当前页面中的 `bradautomates/claude-video` 提供 `watch` skill：用 `yt-dlp` / `ffmpeg` 做场景抽帧、去重和时间窗处理，并把字幕或 Whisper 转录与画面一起交给模型分析。[S13][S16]
- 这不是现有 `transcribe` 的简单重复；后者主要解决音频转录，`watch` 对公众号/知乎视频素材拆解、教学动画验收和录屏故障分析有真实增量。
- **AI 推荐：下一轮在内容或教学动画项目做 project-scoped pilot，不直接加入本轮全局 recommendations。** 当前七仓扫描没有视频理解运行依赖；首次使用还要验证 Windows 下 `ffmpeg`、`yt-dlp`、以 Bash/Read 表述的指令兼容性，以及 Whisper fallback 的 API key 边界。

因此“没有任何其他增量技能”会过强；准确表述应是“没有其他候选满足本轮全局安装门槛”。这不改变本轮四类 dry-run 数量。

### 3.3 GitHub Monthly Trending 的供应链线索

- `DeusData/codebase-memory-mcp` 位于当月页面，且本机已经安装，不是缺口。[S13][S14]
- `NVIDIA/SkillSpector` 与 skills-manager 的供应链治理高度相关：官方仓库提供静态扫描、JSON/SARIF、baseline、稳定 exit code，并可选提供 MCP server。[S15]
- **AI 推荐：把 SkillSpector 作为后续 CLI 门禁候选单独评估，不作为本轮常驻 MCP 新增。** 理由是 CLI 更适合 install/update gate，新增 MCP 会反向扩大默认工具面；同时该项目较新，需先在 Windows 对当前 102 份投影做误报率、耗时、离线行为和回滚验证。
- Monthly Trending 的其他项目多为完整应用、代理平台或泛化工具，不是可直接映射到本轮 `skill`/`MCP` 安装项；Trending 本身不足以支持新增。

因此 `mcp_new_servers=[]` 和仅新增一个官方 skill 的保守结论仍然成立。SkillSpector 是后续独立工程项，不应偷偷塞进本次 dry-run。

## 4. 对 `recommendations.json` 的最终判断

| dry-run 类别 | 数量 | 判断 |
|---|---:|---|
| 技能新增 | 1 | 正确：`[1] microsoft-code-reference` 有官方来源、已存在的 MCP 依赖和三个 .NET 目标仓证据。 |
| 技能卸载 | 0 | 正确：跨根同名冲突尚未完成逐项选主与回滚，不能按名称自动删除。 |
| MCP 新增 | 0 | 正确：当前缺口是 profile/工具白名单，不是更多常驻 MCP。 |
| MCP 卸载 | 0 | 有条件正确：`postgres` 必须先迁移；Browser/Playwright 等应先按需关闭，而非直接删除。 |

未发现需要改写本轮四类建议顺序或数量的外部证据。需要在后续任务落地的是“默认关闭 + profile + `enabled_tools`”以及 archived postgres 的替代迁移，不应误算为本轮已完成。

## 5. 一手来源

- [S1] Microsoft, [`microsoft-code-reference` skill（固定 commit）](https://github.com/MicrosoftDocs/mcp/blob/caa3d670bf2814171dba4f7346ece5080964021e/skills/microsoft-code-reference/SKILL.md)
- [S2] Microsoft, [Microsoft Learn MCP Server](https://github.com/MicrosoftDocs/mcp#readme)
- [S3] MCP Steering Group, [Reference servers warning and archived list](https://github.com/modelcontextprotocol/servers#model-context-protocol-servers)
- [S4] MCP Steering Group, [Archived PostgreSQL server](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/postgres)
- [S5] Microsoft Playwright, [Playwright MCP vs Playwright CLI（固定 commit）](https://github.com/microsoft/playwright-mcp/blob/5f8fc00210b27b4407c375b59cda4838045d429c/README.md#playwright-mcp-vs-playwright-cli)
- [S6] OpenAI, [Plugins](https://learn.chatgpt.com/docs/plugins)
- [S7] OpenAI, [MCP configuration options](https://learn.chatgpt.com/docs/extend/mcp#other-configuration-options)
- [S8] skills.sh, [Trending](https://skills.sh/trending)
- [S9] skills.sh, [`edit-article`](https://skills.sh/mattpocock/skills/edit-article)
- [S10] skills.sh, [`ai-video-generation`](https://skills.sh/101-skills/skills/ai-video-generation)
- [S11] skills.sh, [`hyperframes`](https://skills.sh/heygen-com/hyperframes/hyperframes)
- [S12] skills.sh, [Microsoft `microsoft-foundry`](https://skills.sh/microsoft/azure-skills/microsoft-foundry)
- [S13] GitHub, [Monthly Trending](https://github.com/trending?since=monthly)
- [S14] DeusData, [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp#readme)
- [S15] NVIDIA, [`SkillSpector`](https://github.com/NVIDIA/SkillSpector#readme)
- [S16] Brad Automates, [`claude-video` / `watch` skill](https://github.com/bradautomates/claude-video/tree/main/skills/watch)

## 6. 验证与回滚

- 平台诊断：`codex-cli 0.144.1`；`codex --help` 可见 `mcp`、`plugin`、`doctor` 等入口；`codex mcp list` 成功，无 `platform_na`。
- 网络访问：成功；上述页面在 2026-07-10 均返回 HTTP 200，无 `platform_na`。
- 变更类型：纯研究证据文档，不改 `recommendations.json`、代码、技能、MCP 或 plugin 配置。
- `build/test/contract/hotspot`: `gate_na`；reason = 本子任务只新增研究文档；alternative_verification = URL 实际访问、JSON/本地事实交叉核对与 `git diff --check`；evidence_link = 本文件；expires_at = 下一次实际安装、MCP/profile 或供应链门禁变更。
- 回滚：仅删除本文件；不得回退审查包、imports、audit/MCP 源码或其他工作树改动。
