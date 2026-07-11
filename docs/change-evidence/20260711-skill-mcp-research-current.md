# 2026-07-11 Skills / MCP 独立研究复核

## 1. 范围与基线

- 研究对象：`reports/skill-audit/20260711-011151-210/` 的 `recommendations.json`、`dry-run-summary.json`、`installed-skills.json` 与 `repo-scans.json`。
- 用户画像：PPT 课件、Windows/WPF 教师软件、公众号/知乎内容、初中物理 Web/视频动画。
- 目标仓事实：审查包覆盖 9 个仓库，其中 `ClassroomToolkit`、`classroom-answer-toolkit`、`k12-question-graph`、`ai-content-delivery-studio` 检出 .NET；另有 React/Vite、Python、Playwright、文档/OCR、数据库等工作面。
- 已安装事实：快照含 110 个受管技能与 8 个受管 MCP。PPT、内容发布、Manim/Remotion、浏览器、Windows 桌面测试已有多层能力；MCP 默认只启用 `microsoft-learn` 与 `openaiDeveloperDocs`。
- 访问日期：以下所有网络来源均在 **2026-07-11** 访问。Trending/skills.sh 只用作发现线索，不单独作为安装或删除依据。

## 2. 结论

最新 dry-run 的四类计数为 `新增技能 1 / 删除技能 0 / 新增 MCP 0 / 删除 MCP 0`。结论的方向基本正确，但**不完整**：

1. **`microsoft-code-reference` 新增建议正确，置信度高。** 它是 Microsoft 官方技能，明确用于官方代码样例、API 签名、SDK 错误和弃用模式核验；其依赖的 Learn MCP 三个工具已经启用。审查包锁定的 `caa3d670...` 在访问时仍是上游 `main`，供应链锁定合理。
2. **建议再新增 `microsoft-docs`，置信度高。** 同一官方仓库把它定义为概念、教程、配置、限制/配额和最佳实践入口，和 `microsoft-code-reference` 的“写代码/修代码”职责明确分开。WPF/Windows/.NET 教师软件不仅需要 API 签名，也经常需要平台行为、配置与官方最佳实践；该技能复用现有 `microsoft-learn` MCP，不增加 server 或凭据面。这是最新建议包的实质遗漏。
3. **删除技能为 0 暂时正确。** PPT、内容、动画、浏览器的技能虽然触发词相近，但输出媒介和执行器不同；仅凭元数据重叠不足以安全卸载。应继续依靠 profile/投影选主，而不是批量删原目录。
4. **新增 MCP 为 0 正确。** 现有 Learn/OpenAI 官方文档端点已覆盖高价值实时资料；浏览器、文件系统、GitHub、Postgres、代码图谱均已有按需配置。新增常驻 MCP 会增加工具 schema、权限和运维成本，目前没有目标仓缺口证据。
5. **删除 MCP 为 0 是有条件的正确。** `postgres` 上游参考服务器已经归档，但仍提供只读查询/模式检查；在替代方案、迁移与回滚未验证前，保持配置且默认停用比直接卸载稳妥。Playwright 官方明确建议 coding agent 优先 CLI + skill，因此 MCP 保持默认停用合理。

因此，若 recommendations 必须严格反映本轮研究，建议最终计数应为 **`新增技能 2 / 删除技能 0 / 新增 MCP 0 / 删除 MCP 0`**；第二项新增为 `microsoft-docs`。

## 3. 分领域复核

### 3.1 Windows / WPF / .NET 教师软件

**保留并补强：**

- 保留自定义 `custom-windows-wpf-teacher-app` 作为教师场景路由，保留 `windows-desktop-e2e`/UI Automation 类执行能力。
- 新增 `microsoft-code-reference`：查 API 签名、正式代码样例、SDK 版本差异与弃用信息。
- 新增 `microsoft-docs`：查 WPF/.NET/Windows/M365 概念、配置、教程与最佳实践。
- 不新增 Azure 技能包。skills.sh 当前可发现大量 Microsoft Azure 官方技能，但目标仓没有 Azure 部署/运维事实，按热度安装会扩大固定元数据。

Microsoft 的 WPF 官方概览将 WPF定义为 Windows 桌面 UI 框架，并列出 XAML、控件、数据绑定、布局、2D/3D、动画等能力，直接吻合目标仓；这也说明“通用 .NET 后端技能”不能代替 WPF 官方资料入口。

### 3.2 PPT 课件与教师办公

**不新增、不批量删除。** 当前已有 `pptx`、`custom-teacher-courseware-ppt`、`powerpoint-automation`、`python-pptx`、`baoyu-slide-deck`、Slidev 等。它们分别承担课件教学约束、PPTX 文件编辑、Windows COM/打开中的 PowerPoint、程序化生成、图片式幻灯片和 Web 演示，不能仅按“PPT”关键词判定重复。

skills.sh 当前高位候选仍包括 `anthropics/skills/pptx`，但它已经在快照中；没有发现比现有组合更明确、且有目标仓证据的官方 Office MCP。应优先把教师课件领域入口路由到一个文件级执行器，再按任务选 COM、PPTX 或 Web 演示，而不是继续堆 PPT 技能。

### 3.3 公众号、知乎、文章、素材与配图

**不新增 MCP；保留现有领域栈。** `custom-creator-publishing`、Baoyu 的封面/信息图/图片压缩/公众号发布、marketing skills 与浏览器能力已经覆盖写作、改稿、排版、配图和公众号发布。

GitHub monthly trending 的 `Agent-Reach` 是多平台“搜索/阅读”接入层，README 当前列出 B 站、Twitter、Reddit、Facebook、Instagram、小红书等，但没有给出知乎或微信公众号发布能力；它还会安装多种 CLI、复用登录态并可接入 Exa MCP。对本画像而言增量不明确、权限面更大，**不建议安装**。

### 3.4 初中物理动画、Web 与视频

**不新增。** 当前自定义物理动画入口已经能路由 Web/SVG/Manim，且已安装 ManimCE、Remotion、UI animation、D3、Playwright 等执行与验证技能。Manim 官方定位是程序化解释性动画引擎；Remotion/HyperFrames 都属于程序化视频/动画执行器，继续叠加会加重路由冲突。

skills.sh 的 `HyperFrames` 能将 HTML/CSS/媒体和可寻址动画渲染为确定性 MP4，也提供幻灯片技能，但其能力与现有 Remotion + Web 动画 + Slidev 明显重叠；在出现“现有栈无法满足的确定性 HTML-to-MP4”真实任务前，**不安装**。`watch` 的视频理解能力可在明确出现课堂视频拆解/转录需求时做项目级试点，不应全局安装。

## 4. 重叠、删除与供应链判断

### 4.1 不支持立即删除的项目

- `Playwright MCP` 与 Playwright CLI/skill：择优策略应是 coding agent 默认 CLI/skill，探索式、持久会话才启用 MCP；这是 profile 选择，不是必须卸载。
- `postgres MCP`：上游已归档，但服务声明只读；在 `k12-question-graph` 的只读诊断用途仍存在时，默认停用并保留回滚入口优于直接删除。
- PPT、内容、Manim/Remotion、浏览器各栈：领域入口与执行器分层，不能把相似描述当成内容等价。
- 跨根同名技能：审查包已记录 86 个同名组，只有 24 个目录哈希完全相同，62 个内容不同；继续用投影唯一选主，不依据名字删除源目录。

### 4.2 新发现的源生命周期风险

受管快照仍从 `https://github.com/openai/skills.git` 投影 `openai-docs`、`playwright`、`screenshot`、`security-best-practices`、`transcribe`。该官方仓库 README 当前明确标记 **deprecated**，并要求转向 `openai/plugins` 和 Codex 插件构建文档。

这暂不构成“立即删除 5 个技能”的充分依据，因为当前 Codex 运行时仍可能内置等价系统技能，而且 `openai/plugins` 未提供逐项一一对应的迁移路径。正确动作是单独建立**源迁移观察项**：核验宿主内置/插件版本、内容哈希、触发和回滚后，再移除旧 vendor 源。最新 recommendations 的“删除 0”仍可成立，但 `source_observations` 应记录这一风险。

### 4.3 SkillSpector

GitHub monthly trending 的 NVIDIA `SkillSpector` 是值得继续评估的供应链门禁。官方 README 支持 CLI、JSON/Markdown/SARIF 和无 LLM 扫描，也另有 MCP 模式。对 `skills-manager` 而言，**优先 CLI/CI 试点而不是新增常驻 MCP**，因为静态审查是确定性 gate，且需要先测误报率、耗时、Windows 行为和离线性。最新包的“不安装 SkillSpector MCP”判断正确。

## 5. 逐项建议清单

| 候选 | 决定 | 置信度 | 原因 |
|---|---|---:|---|
| `microsoft-code-reference` skill | 新增 | 高 | 官方、提交已锁定、复用已启用 Learn MCP，补足 API/样例/弃用核验。 |
| `microsoft-docs` skill | 新增 | 高 | 官方、与 code-reference 职责互补，覆盖 WPF/Windows/.NET 概念、配置和最佳实践；无新 server。 |
| 其他 Azure 官方 skills | 不新增 | 高 | 没有 Azure 目标仓事实。 |
| Playwright MCP | 保留配置、默认停用 | 高 | 官方建议 coding agent 优先 CLI + skill。 |
| Postgres MCP | 暂保留、默认停用 | 中高 | 上游归档但仍有只读诊断用途；先迁移再卸载。 |
| `Agent-Reach` | 不安装 | 高 | 未提供知乎/公众号发布增量，依赖与登录态权限面较大。 |
| `HyperFrames` | 不安装 | 中高 | HTML-to-video 有价值，但与现有 Remotion/Web/Slidev 重叠，暂无目标仓缺口。 |
| `watch` | 暂不安装 | 中 | 仅在出现课堂视频理解需求后项目级试点。 |
| SkillSpector MCP | 不安装 | 高 | 供应链扫描优先 CLI/CI gate。 |
| `openai/skills` 旧 vendor 源 | 迁移观察，不立即删 | 高 | 官方已弃用；需先映射系统/插件替代品并验证哈希、触发和回滚。 |
| 其他 skills.sh / monthly trending 泛化候选 | 不安装 | 高 | 热度不是需求证据，现有 profile 已覆盖主要工作流。 |

## 6. 来源（均访问于 2026-07-11）

### 官方文档与官方仓库

- Microsoft Learn MCP 官方仓库与工具说明：<https://github.com/MicrosoftDocs/mcp>
- Microsoft Learn MCP `microsoft-code-reference`：<https://github.com/MicrosoftDocs/mcp/blob/caa3d670bf2814171dba4f7346ece5080964021e/skills/microsoft-code-reference/SKILL.md>
- 上述锁定提交：<https://github.com/MicrosoftDocs/mcp/commit/caa3d670bf2814171dba4f7346ece5080964021e>
- Microsoft Learn MCP `microsoft-docs`：<https://github.com/MicrosoftDocs/mcp/blob/main/skills/microsoft-docs/SKILL.md>
- Microsoft WPF 官方概览：<https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/>
- Playwright MCP 官方 README（MCP vs CLI）：<https://github.com/microsoft/playwright-mcp#playwright-mcp-vs-playwright-cli>
- Playwright CLI 官方仓库：<https://github.com/microsoft/playwright-cli>
- MCP reference servers 官方归档说明：<https://github.com/modelcontextprotocol/servers#archived>
- 归档 Postgres MCP：<https://github.com/modelcontextprotocol/servers-archived/tree/main/src/postgres>
- Manim Community 官方仓库：<https://github.com/ManimCommunity/manim>
- Remotion 官方 skills：<https://github.com/remotion-dev/skills>
- OpenAI skills 旧仓库弃用说明：<https://github.com/openai/skills#readme>
- OpenAI Plugins 官方仓库：<https://github.com/openai/plugins>
- OpenAI Codex skills 文档：<https://developers.openai.com/codex/skills>
- OpenAI Codex plugin 构建文档：<https://developers.openai.com/codex/plugins/build>

### 社区候选与发现源

- skills.sh：<https://skills.sh/>
- skills.sh `pptx`：<https://skills.sh/anthropics/skills/pptx>
- skills.sh `playwright-cli`：<https://skills.sh/microsoft/playwright-cli/playwright-cli>
- skills.sh `remotion-best-practices`：<https://skills.sh/remotion-dev/skills/remotion-best-practices>
- GitHub monthly trending：<https://github.com/trending?since=monthly>
- NVIDIA SkillSpector：<https://github.com/NVIDIA/SkillSpector>
- Agent-Reach：<https://github.com/Panniantong/Agent-Reach>
- HyperFrames：<https://github.com/heygen-com/hyperframes>
- Baoyu skills：<https://github.com/JimLiu/baoyu-skills>
- `watch`：<https://github.com/bradautomates/claude-video/tree/main/skills/watch>

## 7. 风险与后续验证

- 本文只形成研究证据，没有修改 `recommendations.json`、`skills.json`、MCP 配置或运行 apply/dry-run。
- `microsoft-docs` 若进入建议，应和 `microsoft-code-reference` 使用同一固定 commit，并经过现有 preflight/dry-run；不要使用浮动 `main`。
- `openai/skills` 迁移应作为独立切片：先证明替代来源、投影主版本和宿主可用性，再删除旧 source；回滚只恢复该 source/lock/投影。
- Postgres MCP 的最终删除需要替代只读诊断路径、凭据处理、迁移和回滚证据。
