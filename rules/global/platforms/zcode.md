## B. ZCode 平台差异
<!-- verified: 2026-10-05 | zcode.z.ai/cn/docs/agents | ZCode / GLM -->
### B.1 加载链
- 任务启动时按顺序拼接 `~/.zcode/AGENTS.md` 与当前 Workspace 根 `AGENTS.md`；Workspace 指令是项目主要来源。不扫描嵌套规则，不展开 import/include，不持续读取 `CLAUDE.md`。
- 用户级 Skill 位于 `~/.zcode/skills/<skill-name>/SKILL.md`；使用当前可见 metadata/native tool，不根据文件存在推断已加载。
- 用户级 MCP 为 `~/.zcode/cli/config.json` 的 `mcp.servers`，工作区为 `<workspace>/.zcode/config.json`；`.agents/mcp.json` 仅在同作用域原生 MCP 为空时后备，不合并。工作区 MCP 会自动连接，打开未知仓库前先审查；配置存在不授权其写入或命令。
- 子智能体的规则注入依版本与配置决定；Explore 默认不注入，不依赖自动继承，委派时显式传递必要约束。子智能体不能再派子智能体。
### B.2 诊断与强制
- 最小诊断用当前 ZCode help 与规则面板；加载核验以新建 Workspace 任务的实际加载为准，无法观察时按 `platform_na` 记录替代证据与复测条件。
- 冷技能路由与 `execution_contract` 分三支见 A.3；本节只声明 ZCode 的承载面：`one_shot` 可按当前可见 Agent 工具委派，显式传入原始请求、验证结果、scope/write set/proof/stop；`multi_turn_user_decision` 一题一轮并等待用户，`parent_user_input` 停在父任务。
- `host_admission_required` 的父代理代替执行边界见 A.3；不得据投影或 receipt 断定子代理已启动。
- ZCode 提供 general-purpose/Explore 子智能体；能否满足 native child lifecycle 须以本次工具返回的身份、启动与终态证据判断。无可用 child 时仅在契约允许下 parent-mediated 并标 `not_observable`，不得伪造子代理成功或把产品能力说成已实测。
- 文件一致只证明 `filesystem_projected`；新建 Workspace 任务核对加载才可称 `host_loaded`，真实任务验收另列。执行模式、安全确认与权限属于宿主控制面，本规则不绕过它们。
- 未经当前任务授权，不重启、停止、杀掉或启动宿主，不修改账号、provider、模型、权限、会话、插件或 MCP；能力不可观察时记录原因、替代验证与复测条件。
### B.3 回退
- 命令或接口不可用、help 与行为不一致、或权限/确认拦截导致失败时，按 `platform_na` 留痕；静态文件一致不升级为 `host_loaded` 或 `live_accepted`。
