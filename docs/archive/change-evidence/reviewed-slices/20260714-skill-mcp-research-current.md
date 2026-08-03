# 2026-07-14 Skills / MCP 外部研究复核

## 1. 范围、落点与边界

- 审查基线：`reports/skill-audit/20260714-003738-935/`。
- 目标仓：`ClassroomToolkit`、`classroom-answer-toolkit`、`skills-manager`、`k12-question-graph`、`local-ai-dev-orchestrator`、`ai-content-delivery-studio`、`github-toolkit`、`qq-codex-bot`、`vps-ssh-launcher`。
- 用户工作流：Windows/WPF 教师软件、PPT 课件、公众号/知乎内容生产、初中物理 Web/Manim/视频动画，以及多仓代码治理。
- 当前快照：108 个真实技能、8 个受管 MCP；默认启用的 MCP 只有 `microsoft-learn` 与 `openaiDeveloperDocs`，`context7`、`github`、`playwright`、`filesystem`、`postgres`、`codebase-memory-mcp` 均已安装但默认停用。
- 本文只记录研究证据和判断，没有修改 `recommendations.json`、`skills.json`、源码、测试、生成物或宿主配置，也没有安装、删除、启用任何技能/MCP。
- 网络来源访问日期均为 **2026-07-14**。GitHub Trending 与 skills.sh 只用于候选发现，不能单独支持安装或卸载。

## 2. 结论

本轮外部研究支持四类建议均为 **no-op**：不新增技能、不删除技能、不新增 MCP、不删除 MCP。

1. **技能新增为 0 正确。** 四个用户主工作面均已有领域入口、执行器和官方资料层；skills.sh 搜索结果没有证明更强且非重复的增量能力。
2. **技能删除为 0 正确。** PPT、WPF、内容发布、物理动画和浏览器技能存在触发词重叠，但职责分别属于领域路由、文件/GUI 执行、生成引擎、发布或验证。应继续由 profile/选主控制可见性，不能仅凭名称相似卸载。
3. **MCP 新增为 0 正确。** 两个默认启用项已经覆盖 OpenAI/Microsoft 官方资料；其余浏览器、GitHub、代码图谱、文件系统和 PostgreSQL 能力均已有按需配置。没有目标仓事实证明需要新增常驻外部数据面。
4. **MCP 删除为 0 有条件地正确。** PostgreSQL reference server 已归档且 npm 包已 deprecated，但当前配置默认停用，而 `k12-question-graph` 仍有明确的 PostgreSQL 只读诊断场景。正确动作是保留配置、继续默认停用，并在任何重新启用前做固定版本、替代实现、权限和回滚审查；归档状态本身不足以支持立即删除。

## 3. 官方文档与当前能力覆盖

### 3.1 Microsoft / WPF / PPT

Microsoft Learn 的 WPF 官方概览明确：WPF 是只运行于 Windows 的 .NET UI 框架，覆盖 XAML、控件、数据绑定、布局、2D/3D、动画、文档、媒体和排版。Open XML SDK 的 Presentation 文档则提供程序化处理演示文稿的官方入口。

当前快照已安装：

- `custom-windows-wpf-teacher-app`：教师场景、触控/笔、PDF/图片/PPT 展示、双屏、恢复、UI Automation。
- `custom-teacher-courseware-ppt`：初中课堂 PPT/PPTX 教学约束。
- `microsoft-docs` 与 `microsoft-code-reference`：分别承担 Microsoft 概念/配置/最佳实践和代码样例/API 签名核验。
- `pptx`、`powerpoint-automation`、`baoyu-slide-deck`、`slidev` 等文件、GUI 和 Web 演示执行能力。

判断：官方知识面和教师领域路由均已覆盖；skills.sh 中通用 WPF 或风格型 PPT 候选不能提供已证明的增量价值。

来源：

- Microsoft WPF 官方概览：<https://learn.microsoft.com/dotnet/desktop/wpf/overview/>
- Microsoft Open XML SDK Presentations：<https://learn.microsoft.com/office/open-xml/presentation/overview>
- Microsoft Learn MCP：<https://learn.microsoft.com/api/mcp>

### 3.2 OpenAI MCP 安全边界

OpenAI 官方 MCP/Connectors 指南明确要求信任所连接的 MCP server，指出恶意 server 可从模型上下文中外泄敏感数据；官方还建议审核共享数据、保留审批，并通过 `allowed_tools` 收窄工具面。

判断：在两个官方文档 MCP 已默认启用、其余服务器已按需停用的前提下，不应仅因候选热度增加常驻 MCP。任何新增都必须先证明目标仓缺口、最小权限和数据边界。

来源：

- OpenAI MCP and Connectors：<https://developers.openai.com/api/docs/guides/tools-connectors-mcp>

## 4. skills.sh / find-skills 结果

在仓库外临时目录执行只读发现命令，避免仓库根 `skills.ps1` 遮蔽 npm CLI：

```text
npx -y skills find "windows wpf teacher"
npx -y skills find "ppt courseware"
npx -y skills find "wechat zhihu publishing"
npx -y skills find "physics animation manim"
```

| 查询 | 主要结果 | 事实 | 判断 |
|---|---|---|---|
| `windows wpf teacher` | `auth0-wpf` 217、`windows-app-developer` 141、`dotnet-wpf-modern` 132 installs | 前者是 Auth0 特定集成，后两者是通用 Windows/WPF 开发 | 目标仓没有 Auth0 缺口；通用能力不超过本地教师 WPF 技能加 Microsoft 官方资料层，不新增 |
| `ppt courseware` | `ian-handdrawn-ppt` 60、`course-forge` 22 installs | 一个偏手绘风格，一个低采用课程生成候选 | 没有证明比现有课堂课件领域技能和多执行器组合更完整，不新增 |
| `wechat zhihu publishing` | `wechat-publisher` 712、`zhihu` 160 等 | 搜索命中平台发布/抓取型候选 | 已有 `custom-creator-publishing`、`baoyu-post-to-wechat`、`md2wechat-lite` 和浏览器发布能力；重复且涉及登录/凭据面，不新增 |
| `physics animation manim` | `manimce-best-practices` 2.7K、`manim` 405 等 | 第一名来自 `adithya-s-k/manim_skill` | 同源 `manimce-best-practices` 与 `manim-composer` 已安装，且有初中物理专用入口；不存在缺口 |

代表性来源：

- <https://skills.sh/auth0/agent-skills/auth0-wpf>
- <https://skills.sh/wshaddix/dotnet-skills/dotnet-wpf-modern>
- <https://skills.sh/helloianneo/ian-handdrawn-ppt/ian-handdrawn-ppt>
- <https://skills.sh/0731coderlee-sudo/wechat-publisher/wechat-publisher>
- <https://skills.sh/acedatacloud/skills/zhihu>
- <https://skills.sh/adithya-s-k/manim_skill/manimce-best-practices>

## 5. PostgreSQL MCP 生命周期判断

### 5.1 上游事实

- `modelcontextprotocol/servers` 当前 README 将 PostgreSQL 列入 **Archived**；主仓同时说明这些 server 是展示 MCP/SDK 的 reference implementations，不是 production-ready solutions。
- `modelcontextprotocol/servers-archived` 仓库本身已设为 archived，描述为“不再维护的 reference MCP servers”。
- PostgreSQL server 的归档 README 说明它只允许 schema inspection 和只读 SQL，查询在 `READ ONLY` transaction 中执行。
- npm registry 当前显示 `@modelcontextprotocol/server-postgres` 最新版本为 `0.6.2`，并明确标记 `Package no longer supported`。

来源：

- MCP reference servers 及 Archived 列表（固定提交）：<https://github.com/modelcontextprotocol/servers/blob/d31124c982401739917fd817c2a59db344529c16/README.md#L37-L48>
- 归档仓：<https://github.com/modelcontextprotocol/servers-archived>
- 归档 PostgreSQL server：<https://github.com/modelcontextprotocol/servers-archived/tree/main/src/postgres>
- npm package：<https://www.npmjs.com/package/@modelcontextprotocol/server-postgres>

### 5.2 目标仓事实

`k12-question-graph` 不是“可能用数据库”的弱关联项目，而是把 PostgreSQL 作为运行事实：

- `AGENTS.md` 明确已有 API/Web/Worker/PostgreSQL/FileStore/backup。
- `ALL_IN_ONE_EXECUTIVE_SPEC.md` 明确 EF Core/Npgsql、PostgreSQL + JSONB + FTS + `pg_trgm`、PostgreSQL job table、`pg_dump`。
- `docs/04_TechnologyStack.md` 明确本地 PostgreSQL、`pg_dump`/`pg_restore`、FTS/`pg_trgm` first 和 PostgreSQL job store。
- 当前审查快照中的 `postgres` MCP 已是 `enabled=false`，工具面只有 `query`，连接字符串由环境变量解析。

### 5.3 判断

**保留配置、默认停用**是当前正确结论，但这是有明确保护条件的保留：

- 不把 archived/deprecated server 当作受支持的生产依赖。
- 不在普通任务中自动启用；需要 schema/数据诊断时才按 profile 显式选择。
- 重新启用前应固定已审计版本，验证只读账户、连接字符串不进入日志、目标库范围和回滚；同时调研受维护替代实现。
- 若后续证明 `psql`/仓库诊断脚本已完全替代 MCP，且经过一个观察期没有调用，再将其列入卸载候选。

立即卸载会丢掉现成的只读诊断入口，却没有已验证替代和迁移证据；立即启用则忽略上游停止维护与供应链风险。当前的“已安装但停用”正好保留能力与风险隔离。

## 6. GitHub Monthly Trending 候选

Monthly Trending 仅用于发现。以下判断均回到项目官方仓库、README 和许可证核对。

### 6.1 `OpenMontage`：不安装

- 官方仓将其定义为完整的 agentic video production system，依赖 Python 3.10+、FFmpeg、Node.js 18+，并内置 Remotion 等渲染链。
- 许可证为 AGPL-3.0。
- 当前已安装 Remotion 系列、Manim、Web 动画和 `custom-junior-physics-animation`；用户需要的是可控的课堂物理动画，不是引入一个包含研究、脚本、素材生成、配音、剪辑、成本和多 provider 的完整视频生产系统。

结论：功能面过大、运行与供应链成本高，并与现有 Remotion/视频栈显著重叠。除非出现现有栈无法完成的完整自动视频制片需求，并单独评估 AGPL 和 provider 数据边界，否则不安装。

来源：

- 官方仓：<https://github.com/calesthio/OpenMontage>
- 固定提交中的 pipelines/tools/skills 与技术栈：<https://github.com/calesthio/OpenMontage/blob/f8d94632ea9bd0057da31904acca1cefecf005dd/README.md#L339-L454>
- 固定提交中的 AGPL 许可证声明：<https://github.com/calesthio/OpenMontage/blob/f8d94632ea9bd0057da31904acca1cefecf005dd/README.md#L743-L745>

### 6.2 `Agent-Reach`：不安装

- 官方仓定位是跨平台互联网阅读/搜索 CLI，主要覆盖 Twitter/X、Reddit、YouTube、GitHub、Bilibili、小红书等。
- README 没有提供知乎或微信公众号发布能力；“WeChat”命中来自联系方式/群聊，不是公众号工作流。
- 许可证为 MIT，但安装器会引入 Python CLI、Node.js、`gh`、`mcporter`、Exa MCP 和 skill；Cookie 平台还明确存在凭据与封号风险，扩大账号和数据权限面。

结论：不能补足用户真正需要的公众号/知乎写作、排版和发布闭环，并与现有浏览器、抓取和内容发布技能重叠，不安装。

来源：

- 官方仓：<https://github.com/Panniantong/Agent-Reach>
- 固定提交中的平台能力表：<https://github.com/Panniantong/Agent-Reach/blob/e825f6740d24c6c315c3b0dc41907e6c87ff39a5/README.md#L73-L89>
- 固定提交中的安装器和读内容边界：<https://github.com/Panniantong/Agent-Reach/blob/e825f6740d24c6c315c3b0dc41907e6c87ff39a5/README.md#L136-L165>
- 固定提交中的 Cookie 风险：<https://github.com/Panniantong/Agent-Reach/blob/e825f6740d24c6c315c3b0dc41907e6c87ff39a5/README.md#L233-L239>

### 6.3 `page-agent`：不安装

- 官方仓定位是嵌入网页的 client-side GUI agent：通过页面内 JavaScript 为自己的 Web 产品增加自然语言操作能力。
- README 明确它面向 client-side web enhancement，不是 server-side automation；Chrome extension 和 MCP server 都是可选项，其中 MCP 标为 Beta。
- 许可证为 MIT。

结论：当前目标仓没有“把自然语言 agent SDK 嵌入产品页面”的明确需求；浏览器操作、Web 测试和已登录发布已有 `agent-browser`、Playwright、Chrome/Computer Use 分层覆盖，不新增 skill/MCP。

来源：

- 官方仓：<https://github.com/alibaba/page-agent>
- 固定提交中的定位、可选 extension 与 Beta MCP：<https://github.com/alibaba/page-agent/blob/fa4664dfa5379e6e91deaf85bc1db2ae14d8e1d7/README.md#L31-L49>
- 固定提交中的 client-side 边界：<https://github.com/alibaba/page-agent/blob/fa4664dfa5379e6e91deaf85bc1db2ae14d8e1d7/README.md#L109-L112>

### 6.4 `knowledge-catalog`：不安装

- GoogleCloudPlatform 官方仓说明它是 Google Cloud Knowledge Catalog（原 Dataplex）的工具和样例；仓库内容本身声明不是 Google 官方产品，许可证为 Apache-2.0。
- 对应 agent skills 仍为 beta，前置要求包括启用 Dataplex API、Google Cloud project、Application Default Credentials，以及 Dataplex/Service Usage IAM roles。
- 9 个目标仓没有 Google Cloud/Dataplex 资产治理事实。

结论：这是特定云产品能力，不是本地题库、教师资料或通用代码知识目录。安装会引入无需求依据的云项目、凭据和 IAM 面，不安装。

来源：

- 官方仓：<https://github.com/GoogleCloudPlatform/knowledge-catalog>
- 固定提交中的 Google Cloud 产品面：<https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/d44368c15e38e7c92481c5992e4f9b5b421a801d/README.md#L1-L10>
- 固定提交中的许可证与 disclaimer：<https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/d44368c15e38e7c92481c5992e4f9b5b421a801d/README.md#L18-L25>
- <https://github.com/gemini-cli-extensions/knowledge-catalog>

## 7. 重叠能力的择优规则

| 工作面 | 首选入口 | 执行/补充 | 不应据此删除的重叠 |
|---|---|---|---|
| WPF 教师软件 | `custom-windows-wpf-teacher-app` | `microsoft-docs`、`microsoft-code-reference`、桌面/UI Automation | 通用 .NET、Windows 自动化分别承担实现与宿主操作 |
| PPT 课件 | `custom-teacher-courseware-ppt` | Presentations/PPTX 文件执行、PowerPoint GUI 自动化、Web deck | 文件生成、打开中的 Office、Web 演示不是同一执行面 |
| 公众号/知乎 | `custom-creator-publishing` | `baoyu-post-to-wechat`、`md2wechat-lite`、Chrome | 写作编排、格式转换、实际发布职责不同 |
| 初中物理动画 | `custom-junior-physics-animation` | Web/SVG、`manim-composer`、`manimce-best-practices`、Remotion | 领域教学设计、场景规划、代码规范、视频渲染不是重复包 |
| 浏览器 | 按任务选择 agent-browser/Playwright/Chrome | MCP 继续默认停用，登录态任务才用用户浏览器 | 不因存在多个控制面就卸载；用 profile 限制同时暴露 |

## 8. 最终建议与后续触发条件

| 类别 | 当前建议 | 原因 |
|---|---:|---|
| 新增技能 | 0 | 领域入口与执行器已覆盖，skills.sh 候选无非重复增量 |
| 删除技能 | 0 | 重叠主要是分层职责，应由 profile/选主管理 |
| 新增 MCP | 0 | 官方文档 MCP 已启用，其余能力已有按需配置，新增会扩大权限和 schema 成本 |
| 删除 MCP | 0 | Postgres 生命周期风险真实，但保留且停用比无迁移直接删除更稳妥 |

需要重新打开建议的触发条件：

- 现有 PPT/Manim/Remotion/WPF/发布栈在真实任务上出现可复现缺口，并且候选能通过两个以上唯一来源证明增量。
- 目标仓正式采用 Google Cloud/Dataplex、页面内 GUI agent 或完整自动视频制片系统。
- Postgres MCP 找到受维护替代并完成只读权限、凭据、Windows 启动、回滚和等价查询验证，或经过观察证明 MCP 已无调用需求。
- 任一候选的许可证、供应链或登录态权限完成独立审查。

## 9. 命令与回滚

只读研究命令包括 `npx -y skills find ...`、GitHub API/官方 README 读取、`npm view @modelcontextprotocol/server-postgres ...`、Microsoft Learn MCP search/fetch、OpenAI Developer Docs MCP search/fetch，以及对审查包/目标仓的 `rg`/JSON 查询。

本次唯一写集是本文。回滚只删除：

```text
docs/change-evidence/20260714-skill-mcp-research-current.md
```
