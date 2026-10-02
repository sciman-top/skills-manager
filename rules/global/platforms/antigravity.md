## B. Antigravity 平台差异
### B.1 加载链
- 全局规则位于 `~/.gemini/GEMINI.md`；工作区规则位于 Git 仓库或 workspace 根的 `.agents/rules/`，`.agent/rules/` 仅作官方兼容回退。
- 本仓项目规则由 `.agents/rules/00-project.md` 以 `@../../AGENTS.md` 相对引用承接；相对 `@` 路径按规则文件所在目录解析，适配文件不是第二份项目真源。
- 单个规则文件上限为 12,000 字符；根规则保持短小，低频说明下沉到项目文档、skills、hooks、rules、scripts 或 CI。
- 规则激活模式以宿主当前设置为准：Manual、Always on、Model decision 或 Glob pattern；文件存在不等于已被当前会话加载。
### B.2 诊断与强制
- 最小诊断使用当前 Antigravity/CLI help 与规则面板；优先在新 workspace 会话检查实际加载的规则文件，无法观察时按 `platform_na` 记录替代证据与复测条件。
- `@` 引用只用于受控、仓库内、可审查的规则承接；不得引用凭据、用户私有状态、网络返回内容或仓库外未审查文件。
- 权限和危险操作使用宿主 approval/policy、hooks、checkpoint/restore 或 CI；GEMINI.md 只写行为与验收，不伪装成强制执行层。
- 修改规则后需要新会话或宿主提供的 reload/refresh 机制复核；静态文件一致最多证明 `repo_verified/filesystem_projected`，不证明 `host_loaded` 或 `live_accepted`。
- 未经当前任务授权，不重启、停止、杀掉或启动 Antigravity，不修改账号、provider、模型、权限、会话或 MCP；能力不可观察时保留 `platform_na` 边界。
### B.3 回退
- 若 `.agents/rules/` 或 `@` 引用在当前宿主不可用，保留项目根 `AGENTS.md` 与可选 `CLAUDE.md`/`GEMINI.md` 兼容文件，不把未验证的回退路径升级为 Antigravity `host_loaded` 证据。
