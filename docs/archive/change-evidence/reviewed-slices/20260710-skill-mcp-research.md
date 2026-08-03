# 2026-07-10 Skills / MCP / Plugin 外部研究证据

## 1. 目标与边界

- 当前落点：只新增本研究证据文件，不修改 `skills.json`、宿主配置、技能目录或 `reports/` 运行态产物。
- 目标归宿：为本轮 `recommendations.json -> preflight -> dry-run` 提供外部事实依据；最终是否执行仍以本机审查包、源码、dry-run 和门禁结果为准。
- 研究日期：2026-07-10（Asia/Shanghai）。
- 用户主要用途：Windows 初中教师教学办公、PPT 课件、公众号/知乎内容生产、初中物理动画与 Web、`Hermes + ChatGPT Work + GPT-5.6` 组合编码。
- 证据优先级：OpenAI/Microsoft/GitHub/项目维护者官方文档与源码 > 协议维护者资料 > `skills.sh` 和 GitHub Trending 等社区信号。

## 2. 结论摘要

1. **“两个用户技能根同时加载、同名技能不合并”属实。** 当前 Codex 源码仍把 `$CODEX_HOME/skills` 作为兼容旧位置加载，同时加载 `$HOME/.agents/skills`；它只按规范化后的 `SKILL.md` 路径去重，不按 `name` 去重。2026-07-10 本机实测两根分别有 105 / 95 个技能条目，共 200 个条目、116 个唯一名称、81 组同名重复和 84 个冗余条目。[S1][S2][S3]
2. **“6.3 万字符元数据每次完整进入固定上下文”需要修正。** 新版官方文档说明初始技能清单最多占上下文窗口 2%，上下文未知时最多 8,000 字符；技能很多时先缩短描述，仍过多则省略部分技能并告警。总元数据规模仍是重要健康指标，但不能直接等同于每轮实际注入量。[S1]
3. **AI 推荐的“先求并集、再生成去重平台投影”方向正确。** 不应直接删除 `.agents/skills`；应先保存两侧独有项，再按内容哈希和来源优先级解决同名冲突。Codex 官方还支持按精确 `SKILL.md` 路径用 `[[skills.config]] enabled = false` 暂时停用，适合迁移窗口。[S1]
4. **MCP 按用途拆分、默认少开是正确方向。** OpenAI 官方确认 `enabled = false` 可保留配置但停用服务，`enabled_tools` 是工具白名单，`disabled_tools` 在白名单之后生效；单服务默认启动超时 10 秒、工具超时 60 秒。[S4]
   本机实时复核显示 9 个可见 MCP 中只有 `node_repl`、`microsoft-learn`、`openaiDeveloperDocs` 启用；但 `skills.json` 的 8 个受管项均未声明这两个字段，下一次同步仍会恢复默认启用和全工具暴露。故 profile 最终必须落到受管真源，不能只改 live `config.toml`。
5. **但“编码默认必须开 filesystem MCP”不成立。** Codex 和 Hermes 都已有本地终端/文件能力；MCP Steering Group 明确说明其 `filesystem` 等服务器是参考实现，不是生产就绪方案。除非某个宿主确实缺少受控文件工具或需要跨客户端统一接口，否则 Codex 编码 profile 不应再常开 filesystem MCP。[S8][S14]
6. **浏览器能力不应全部常开。** Playwright MCP 项目维护者明确建议编码代理优先 CLI + SKILL，因为 MCP schema 和可访问性树更耗上下文；MCP 更适合需要持续浏览器状态、丰富检查和长循环的任务。当前已安装的 `playwright` 正是 CLI-first 技能，无需再新增另一份 Playwright 技能。[S7]
7. **新增项应非常少。** 本机现有技能已经覆盖 PPT、内容发布、物理动画、WPF、浏览器、代码质量和研究。最终唯一建议新增的是 Microsoft 官方 `microsoft-code-reference`（放入 Windows/.NET profile，并与 Microsoft Learn MCP 配对）；现有 `debug:dotnet` 负责诊断方法，不覆盖官方 API 签名、代码样例和弃用信息检索。其余重点是去重、择优和 profile 化。[S6]

## 3. 官方确认事实

### 3.1 Codex 技能根、同名行为与上下文预算

**事实**

- OpenAI 文档把 `$HOME/.agents/skills` 定义为当前用户级技能位置，仓库级则扫描从 CWD 到仓库根沿途的 `.agents/skills`。[S1]
- 当前 `openai/codex` 源码仍加载 `$CODEX_HOME/skills`，并明确标注为 `Deprecated user skills location ... kept for backward compatibility`；紧接着加载 `$HOME/.agents/skills`。[S2]
- 合并逻辑只用 `path_to_skills_md` 去重；排序优先级为 `Repo -> User -> System -> Admin`，同名但路径不同的技能会保留。[S3]
- 官方单元测试 `keeps_duplicate_names_from_repo_and_user` 和 `keeps_duplicate_names_from_nested_codex_dirs` 将“同名保留两份”作为预期行为。[S2]
- 官方文档直接写明：两个技能共享同一 `name` 时不合并，二者都可能出现在技能选择器。[S1]
- Codex 使用渐进披露：初始只给模型技能的名称、描述和路径，选中技能后才读取完整 `SKILL.md`。初始清单有 2% / 8,000 字符预算；技能过多会缩短描述或省略部分技能。[S1]

**工程判断**

- 81 组重复名称会造成选择器噪声、触发歧义，并增加部分技能因预算被省略的概率，即使不是 6.3 万字符全部注入。按 `SKILL.md` SHA-256 分组，26 组内容完全相同，55 组存在版本或元数据冲突；`openai-docs` 共 4 份，`skill-creator` 共 3 份。
- 对同一物理目录建立多个符号链接/目录联接时，当前源码会规范化路径并按路径去重；但 Windows 权限、旧版本兼容和其他宿主行为仍需本机 dry-run 验证，不能仅凭源码假定跨平台完全一致。
- `skill-creator` 是 Codex 系统内置技能；`openai-docs` 有 OpenAI 官方版本。除非本地副本存在有意维护的差异，否则应保留系统/官方版本并停用用户重复副本。[S1][S5]

### 3.2 MCP 的开关、工具过滤与启动成本

**事实**

- OpenAI 官方配置支持：

  ```toml
  [mcp_servers.example]
  enabled = false
  enabled_tools = ["read", "search"]
  disabled_tools = ["search"] # 在 enabled_tools 后应用
  ```

- `enabled = false` 的语义是“保留配置但禁用服务”；`enabled_tools` 是允许暴露的工具名白名单。[S4]
- 默认 `startup_timeout_sec = 10`，默认 `tool_timeout_sec = 60`；`required = true` 会让已启用服务初始化失败时阻止启动。[S4]
- 插件捆绑的 MCP 也能在 `plugins.<plugin>.mcp_servers.<server>` 下单独控制 `enabled`、`enabled_tools` 和审批模式。[S4]
- GitHub 官方 MCP 支持 toolsets，并明确说明只启用需要的 toolsets 可帮助模型选择工具、减少上下文；还支持 read-only 和 lockdown 模式。[S9]
- Microsoft Learn MCP 只有搜索、抓取、代码样例搜索三项核心工具，并提供 `maxTokenBudget` 参数限制返回量。[S6]

**工程判断**

- 9 个 MCP 与 72 秒诊断耗时之间只有相关性，没有逐服务计时不能证明因果。若多个 stdio 服务缺环境变量并各自接近默认 10 秒启动超时，累计到几十秒是合理推断，但必须以启动日志/逐项探针确认。
- 工具数量少、只读、远程托管的 Docs MCP 通常比本地多工具 stdio 服务更适合常驻；但仍应按用途控制，避免无关工具参与选择。

### 3.3 Plugin 的真实成本边界

**事实**

- Plugin 可以包含技能、App/connector、MCP server、浏览器扩展和 hooks；安装后这些能力会在新任务/新会话中可用。[S5]
- 技能正文仍按渐进披露加载；插件若包含 MCP，可能需要额外设置或认证；hooks 在启用前应审查和信任。[S1][S5]
- 卸载 plugin 会移除该环境中的 bundle，但已连接的 connector 不会自动断开。[S5]

**工程判断**

- “启用 10 个 plugin 必然产生固定的巨大上下文成本”没有官方定量依据。成本取决于 bundle 内技能数量、是否启动 MCP、暴露多少 schema、是否加载 connector/App 工具及 hooks。
- 因此应优化“实际暴露的技能/MCP/工具”，而不是仅按 plugin 数量粗暴卸载。对包含高价值 Office 系统技能的 plugin，保留安装通常比删除合理；对捆绑 MCP，则用服务/工具级开关收窄。

## 4. 面向本机用途的技能选择

### 4.1 PPT 与教师课件

OpenAI 官方推荐的 PowerPoint 流程是使用内置 `$slides` 系统技能创建/编辑 PPTX，配合 `$imagegen` 生成视觉素材；交付前渲染检查溢出、重叠和字体替换，并尽量保持文字、简单图表和布局元素可编辑。[S12]

**AI 推荐**

- 默认组合只保留两层：
  - 领域层：`custom-teacher-courseware-ppt`，负责初中教学目标、内容组织、课堂节奏和学科约束。
  - 执行层：OpenAI/ChatGPT 的 `slides`/Presentations/PowerPoint 系统能力 + `imagegen`，负责可编辑 PPTX、渲染和视觉验证。
- `baoyu-slide-deck` 只在“输出整页图片式演示稿”时启用。
- `guizang-ppt-skill`、`slidev` 只在明确要求 Web/HTML 演示时启用。
- `ppt-master` 只在需要 SVG/复杂矢量资产时启用。
- `python-pptx`、`powerpoint-automation`、第三方 `pptx` 不进入默认清单；仅在现有工程依赖、批处理脚本或系统 slides 无法完成特定任务时作为后备。
- 不再新增泛化 PPT 技能。当前问题不是缺技能，而是同类执行器过多。

### 4.2 公众号、知乎写作、素材、排版与配图

Baoyu 项目维护者明确建议不要全量安装 20+ 技能，并给出公众号最小集合：`baoyu-cover-image`、`baoyu-article-illustrator`、`baoyu-post-to-wechat`；`baoyu-format-markdown` 仅在原稿需要先结构化时使用。`post-to-wechat` 已包含 Markdown 到微信 HTML 的转换，不需要再单独安装转换技能。[S10]

**AI 推荐**

- 默认内容 profile：`custom-creator-publishing` 作为编排层，配 `copy-editing` 或 `copywriting` 二选一，再按阶段调用 Baoyu 最小集合。
- `content-strategy` 只用于选题/栏目规划，不与逐篇写作技能同时隐式触发。
- `baoyu-format-markdown`、`baoyu-url-to-markdown`、`baoyu-compress-image`、`baoyu-infographic` 都是阶段性工具，保留但按需，不放默认触发集合。
- `md2wechat-lite` 与 `baoyu-post-to-wechat` 存在明显发布链重叠。默认择优 `baoyu-post-to-wechat`；只有既有自动化依赖 `md2wx` 或需要纯本地确定性转换时保留 `md2wechat-lite`。
- 知乎没有必要新增来源不明的发布 MCP。需要使用已登录账号时，按任务启用 Chrome，并把最终发布视为外部写操作，保留人工确认。

### 4.3 初中物理动画、Web 与视频

Manim Community 官方定位是精确的解释型动画引擎；Remotion 适合 React 视频；交互式网页则继续使用现有 Web 技能和浏览器验证。[S11]

**AI 推荐**

- 编排层：保留 `custom-junior-physics-animation`。
- 交互 Web：`vite` + `frontend-ui-engineering` + `ui-animation`；需要数据/轨迹可视化时加 `d3-viz`；验证使用现有 `playwright` CLI-first 技能。
- Manim 视频：`manim-composer` + `manimce-best-practices` 仅在 Manim 任务启用，二者分别承担生成流程与框架约束，属于互补而非简单重复。
- React 视频：仅任务明确选择 Remotion 时启用 `remotion-best-practices`。
- Three.js 等库的当前文档由 Context7 按需拉取即可，不必为每个库常驻一个技能。
- 不新增通用“物理动画”技能；现有自定义领域技能已承担该职责。

### 4.4 Windows 教师办公软件与 WPF/.NET

Microsoft Learn MCP 是 Microsoft 官方、无密钥的只读文档服务，支持文档搜索、页面抓取和代码样例搜索；其仓库还提供 `microsoft-docs` 与 `microsoft-code-reference` 技能。[S6]

**AI 推荐**

- 保留 `custom-windows-wpf-teacher-app`、`windows-desktop-e2e`、`debug:dotnet` 和一个 .NET 架构技能。
- `dotnet-backend-patterns` 与通用 `architecture-patterns` 不应在所有任务同时隐式触发；WPF 应用以自定义 WPF 技能为入口，后端/API 项目再启用 `dotnet-backend-patterns`。
- **唯一建议新增的技能**：Microsoft 官方 `microsoft-code-reference`，仅加入 Windows/.NET profile，用于 API 查证、样例和弃用信息检索；它与侧重系统化故障诊断的 `debug:dotnet` 职责互补。
- Microsoft Learn MCP 默认关闭，仅 Windows/.NET、PowerShell、Office API 或其他 Microsoft 技术任务启用。

### 4.5 Hermes + ChatGPT Work + GPT-5.6 组合编码

Hermes 官方说明其支持任意模型提供商、原生 tools/toolsets、MCP、`agentskills.io` 标准技能、子代理和 Windows 原生运行。[S14] OpenAI 官方说明 GPT-5.6 Sol 面向复杂分析/编码/研究，Terra 是日常平衡默认，Luna 面向轻量和高吞吐；模型选择、上下文、工具、检索和缓存都会影响用量。[S13]

**AI 推荐**

- 把“跨平台技能并集”维护在 skills-manager 的可追溯源层，再为 Codex/Hermes 生成各自投影；不要让每个宿主自行复制一套。
- 模型 profile 与工具 profile 分开：模型强弱不能补偿重复技能和过量工具。日常编码用 Terra 类配置，复杂架构/研究切 Sol，批量轻任务切 Luna；这是运行选择，不需要新增技能。
- `local-ai-dev-orchestrator` 编码 profile 保留：`context-engineering`、`planning-and-task-breakdown`、`debugging-and-error-recovery`、`code-review-and-quality`、`verification-before-completion` 等各阶段一个主技能，避免 Superpowers 与 agent-skills-2 的同义流程成对常驻。
- OpenAI 相关开发保留一份官方 `openai-docs`，并配一个官方 OpenAI Docs MCP；不要保留多份 `openai-docs`。[S5]

## 5. MCP 建议矩阵

| MCP | 默认 | 用途 profile | 建议 | 依据 |
|---|---:|---|---|---|
| Context7 | 关或编码默认开 | 编码/Web | 保留；仅 2 个核心工具，适合当前库文档；与 Microsoft/OpenAI 专用 Docs MCP 分工 | [S4][S15] |
| codebase-memory-mcp | 关 | 多项目编码 | 保留；2026-07-10 GitHub monthly trending 中与本机最相关，Windows 本地运行，支持 C#/TS/Python 等；关闭删除/ADR 等非日常工具 | [S16][S17] |
| GitHub | 关 | GitHub 协作 | 保留；用 `enabled_tools` 或服务器 toolsets 收窄到仓库读取、搜索、issue/PR；默认 read-only，写操作按需 | [S9] |
| OpenAI Docs | 关 | OpenAI/Codex/GPT-5.6 | 保留一份官方远程服务；只读、文档专用，并与一份 `openai-docs` 配对 | [S5] |
| Microsoft Learn | 关 | Windows/.NET/PowerShell | 保留；仅相关任务启用，可用 `maxTokenBudget` 限制返回 | [S6] |
| Playwright MCP | 关 | 持续浏览器状态/探索测试 | 默认改用已安装 Playwright CLI 技能；只有需持久状态、丰富检查、长循环时才开 MCP | [S7] |
| Browser / Chrome 类 MCP 或 plugin 工具 | 关 | 浏览/已登录发布 | 一次只选一个：普通浏览优先内置 Browser；依赖现有登录态才用 Chrome；E2E 优先 Playwright CLI | [S5][S7] |
| filesystem | 关 | 特殊跨宿主场景 | Codex 不默认启用；仅宿主缺文件工具或需严格限定目录的统一接口时使用，并验证访问根 | [S8][S14] |
| postgres | 关 | 数据库项目 | 当前保留但不常开。虽然 `@modelcontextprotocol/server-postgres` 已归档，`k12-question-graph` 已记录只读诊断入口，`governed-ai-coding-runtime` 也有真实 PostgreSQL adapter；完成替代实现、凭据边界和回滚验证后再迁移 | [S8] |

**不建议新增新的常驻 MCP。** 当前更有价值的是：确保 OpenAI Docs/Microsoft Learn/Context7/GitHub/codebase-memory 各只有一个清晰职责，配置工具白名单并用项目或运行 profile 控制开关。

Codex 官方配置支持用户级 `~/.codex/config.toml`、受信项目的 `.codex/config.toml`，也支持放在 `$CODEX_HOME` 旁的 `profile-name.config.toml` 并由 CLI `--profile profile-name` 选择。[S4] 但这不等于 ChatGPT 桌面端会自动按任务切换 CLI profile。桌面端应使用项目级配置、设置界面或 skills-manager 明确投影；任何“自动 profile 选择”都必须先用本机新任务实测。

## 6. Plugin 建议矩阵

| Plugin/能力 | 建议 |
|---|---|
| Presentations / Documents / Spreadsheets / PDF | 与教师办公高度匹配，保留安装；把各文件类型的官方系统技能作为默认执行器，减少第三方泛化技能 |
| Browser | 保留为普通浏览首选，但不与 Browser Use、Chrome、Playwright MCP 全部常开 |
| Chrome | 保留安装、按需启用，仅用于依赖用户登录态的公众号/知乎等工作流 |
| Browser Use alpha | 若无 Browser 所不具备的可复现需求，优先停用/卸载；alpha 状态和 Browser 重叠使其不适合作默认 |
| Computer Use | 保留安装、按需启用，仅在真实 Windows GUI 操作时暴露；其权限面大于纯文件生成 |
| Visualize | 仅交互式可视化任务启用，不进入普通编码/写作默认 |
| Template Creator | 仅制作可复用模板时启用，不进入日常任务默认 |

这里的“按需”优先落到 plugin 捆绑 MCP 的 `enabled=false`、`enabled_tools`、App/tool 开关和技能 path 开关；只有确认整个 bundle 长期无用时才卸载。[S4][S5]

## 7. 去重投影规则

### 7.1 推荐归宿

- 真源：skills-manager 的 `imports/`、`overrides/`、vendor lock/manifest 等可维护输入层。
- Codex 用户投影：统一投影到 `$HOME/.agents/skills`。
- `$CODEX_HOME/skills`：只保留 Codex 自己的系统缓存和确有旧版兼容要求的入口，不再复制一套第三方用户技能。
- Hermes：从同一真源生成其平台投影，不反向作为真源。

### 7.2 合并判定

1. 同名且内容哈希相同：投影一份，记录所有来源。
2. 同名但内容不同：不得静默覆盖；按 `custom override > 当前官方/系统 > 已锁定上游 > 未锁定社区副本` 选择主版本。
3. 有意维护的 fork：改成带命名空间的唯一 `name`，并在 manifest 记录上游、差异和 owner；不能依赖 Codex 的 scope 顺序“覆盖”，因为同名不会合并。
4. 系统内置 `skill-creator`、官方 `openai-docs`：默认保留系统/官方版本；本地无实质差异的副本停用。
5. 迁移期先用 `[[skills.config]] path=... enabled=false` 停用候选，再经过两轮发现/任务触发复验后清理物理副本。[S1]

### 7.3 最低 manifest 字段

`name / selected_source / selected_path / content_hash / all_sources / decision / reason / conflict_state / target_platforms / rollback_path / checked_at`

这套规则能保住 `.agents/skills` 的独有 13 项和另一侧独有 22 项，同时处理 81 组同名重复。当前统计来自两个根目录的真实 `SKILL.md` frontmatter 与文件哈希，不应把 55 组内容冲突按名称直接删除。

## 8. 对初始建议的逐项判断

| 初始判断 | 结论 | 修正 |
|---|---|---|
| 技能重复是明显固定上下文问题 | 基本正确 | 重复会挤占初始技能清单和触发空间；但新版有 2%/8,000 字符预算，不能把 6.3 万总量当成每轮完整注入 |
| 让 skills-manager 生成去重平台投影 | 正确，AI 推荐 | 先并集、哈希、冲突规则和回滚，再投影；不直接删除 `.agents/skills` |
| openai-docs、skill-creator 目录内部重复 | 若本机审查包确认，则应处理 | 优先系统/官方版本；有意 fork 必须重命名和记录差异 |
| MCP 和 plugin 全局启用过多 | 方向正确 | MCP 可直接按服务/工具量化；plugin 不能只按数量判定，要看捆绑的技能、MCP、App 和 hooks |
| 编码默认开 filesystem、context7、codebase-memory、github | 部分正确 | Context7/codebase-memory/GitHub 适合编码 profile；filesystem 对 Codex/Hermes 通常重复，不应默认开 |
| Browser、Chrome、Playwright 不必全开 | 正确 | 普通浏览、已登录会话、E2E 三类需求各选一个；编码优先 Playwright CLI skill |
| postgres 只在数据库任务开 | 正确 | 当前有目标仓真实用途，先保留并按数据库 profile 启用；已归档参考实现不作为长期终态，完成替代、凭据和回滚验证后再迁移 |
| microsoft-learn 只在 .NET 任务开 | 基本正确 | 范围可扩展为 Windows、PowerShell、Office API、Azure 等 Microsoft 技术任务 |
| `enabled=false`、`enabled_tools` 可用 | 官方确认 | `disabled_tools` 在 `enabled_tools` 后应用，需防止白名单后又误禁用 |

## 9. 社区来源的使用方式

- `skills.sh` 的 agent-workflows、design、marketing、testing 和 trending 页面中，与本机相关的高频项目（`find-skills`、Anthropic frontend/canvas、Vercel React/Web 指南、Superpowers、Playwright、Remotion、Supabase）大多已经安装；这支持“先去重、不再扩张”的结论。[S18]
- `skills.sh` API 文档提供 `isDuplicate` 和多供应商安全审计字段，说明社区目录本身也把 fork/复制与供应链审查视为一等问题；新增社区技能应先查原始仓库、内容哈希和审计，而不是只看安装量。[S19]
- 2026-07-10 的 GitHub Monthly Trending 抓取中，`DeusData/codebase-memory-mcp` 位列当月趋势项目；这是保留候选的社区信号，不是可靠性证明。其 README 声称 Windows 单文件、本地处理、14 个工具和多语言图索引；这些性能/质量数字来自项目自身，应在本机 benchmark 后再采信。[S16][S17]
- Trending 是时点快照，会变化；不得把排名写成长期规则。

## 10. 限制、后续验证与回滚

- 本研究没有修改任何宿主配置，也没有执行 plugin/MCP 启停。
- Plugin 的逐项启动时间与 token/schema 体积没有统一官方计量；必须从本机新会话、MCP 启动日志和工具清单采样。
- `skills.sh` 搜索 API 当前要求 Vercel OIDC，研究只使用公开页面和 API 文档，没有把未认证搜索结果当证据。
- GitHub Trending 与第三方 README 属社区/自述证据，只用于候选排序。
- 后续 dry-run 至少应验证：投影前后唯一名称数、同名不同哈希冲突、初始技能清单字符量/省略警告、每个 MCP 启动耗时、暴露工具数、缺失环境变量、profile 切换后的回滚。
- 回滚：删除本证据文件即可；本文件未造成任何运行时状态变更。

## 11. 证据来源

- [S1] OpenAI, [Build skills](https://developers.openai.com/codex/skills)（技能位置、同名不合并、渐进披露、2%/8,000 字符预算、path 级停用）。
- [S2] OpenAI Codex source, [`loader.rs` at `6138909d`](https://github.com/openai/codex/blob/6138909d6ec58b2fbe635ef973e02caecad5a5aa/codex-rs/core-skills/src/loader.rs#L324)；[duplicate-name tests](https://github.com/openai/codex/blob/6138909d6ec58b2fbe635ef973e02caecad5a5aa/codex-rs/core-skills/src/loader_tests.rs#L2396)。
- [S3] OpenAI Codex source, [`root_loader.rs` merge logic](https://github.com/openai/codex/blob/6138909d6ec58b2fbe635ef973e02caecad5a5aa/codex-rs/core-skills/src/root_loader.rs#L93)（按 path 去重、scope/name/path 排序）。
- [S4] OpenAI, [Model Context Protocol](https://learn.chatgpt.com/docs/extend/mcp#other-configuration-options)；[Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)。
- [S5] OpenAI, [Plugins](https://learn.chatgpt.com/docs/plugins)；[OpenAI Docs MCP](https://developers.openai.com/learn/docs-mcp)。
- [S6] Microsoft, [Microsoft Learn MCP](https://github.com/MicrosoftDocs/mcp)；[Microsoft MCP catalog](https://github.com/microsoft/mcp)。
- [S7] Microsoft, [Playwright MCP: MCP vs CLI + Skills](https://github.com/microsoft/playwright-mcp#playwright-mcp-vs-playwright-cli)；[Playwright CLI](https://github.com/microsoft/playwright-cli)。
- [S8] MCP Steering Group, [Reference servers warning and archived servers](https://github.com/modelcontextprotocol/servers#model-context-protocol-servers)。
- [S9] GitHub, [GitHub MCP Server tool configuration](https://github.com/github/github-mcp-server#tool-configuration)；[read-only and lockdown](https://github.com/github/github-mcp-server#read-only-mode)。
- [S10] Jim Liu, [baoyu-skills README](https://github.com/JimLiu/baoyu-skills#readme)（按需安装、公众号最小集合、转换链重叠说明）。
- [S11] Manim Community, [Manim](https://github.com/ManimCommunity/manim#readme)；Remotion, [skills](https://github.com/remotion-dev/skills)。
- [S12] OpenAI, [Generate slide decks](https://learn.chatgpt.com/use-cases/generate-slide-decks)。
- [S13] OpenAI, [Codex pricing / GPT-5.6 workload guidance](https://learn.chatgpt.com/docs/pricing#what-are-the-usage-limits-for-my-plan)。
- [S14] Nous Research, [Hermes Agent](https://github.com/NousResearch/hermes-agent#readme)（providers、tools/toolsets、MCP、Agent Skills、Windows）。
- [S15] Upstash, [Context7](https://github.com/upstash/context7#readme)（CLI+Skills 与 MCP 两种模式、两个核心工具）。
- [S16] GitHub, [Monthly Trending, 2026-07-10 snapshot](https://github.com/trending?since=monthly)。
- [S17] DeusData, [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp#readme)。
- [S18] skills.sh, [Trending](https://skills.sh/trending)、[Agent workflows](https://skills.sh/topic/agent-workflows)、[Design](https://skills.sh/topic/design)、[Marketing](https://skills.sh/topic/marketing)、[Testing](https://skills.sh/topic/testing)。
- [S19] skills.sh, [API Reference](https://skills.sh/docs/api)（`isDuplicate`、curated、audit 字段）。

## 12. N/A 与留痕

- 变更类型：纯研究文档。
- `build`: `gate_na`；reason = 未改代码/配置；alternative_verification = Markdown 内容与 URL 复核；evidence_link = 本文件；expires_at = 不适用。
- `test`: `gate_na`；reason = 未改可执行行为；alternative_verification = 外部一手来源交叉核验；evidence_link = 本文件；expires_at = 不适用。
- `contract/invariant`: `gate_na`；reason = 未改 schema/契约；alternative_verification = 与 Codex 官方源码/文档比对；evidence_link = S1-S5；expires_at = 不适用。
- `hotspot`: `gate_na`；reason = 未修改生成链路；alternative_verification = `git diff --check` 与目标文件存在性检查；evidence_link = 本文件；expires_at = 不适用。
