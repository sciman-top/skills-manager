## B. Antigravity 平台差异
<!-- verified: 2026-10-05 | antigravity.google/docs/rules-workflows | Antigravity 2.0 -->
### B.1 加载链
- 全局规则 `~/.gemini/GEMINI.md`；工作区规则在 Git 仓库或 workspace 根的 `.agents/rules/`（`.agent/rules/` 仅兼容回退）。
- 本仓项目规则由 `.agents/rules/00-project.md` 以 `@../../AGENTS.md` 承接：相对 `@` 按规则文件所在目录解析，适配文件不是第二份真源；仓根 `GEMINI.md`（同样 `@AGENTS.md`）是**同一项目的兼容承接**，不是独立真源，两者内容必须指向同一 `AGENTS.md`。
- 单文件上限 12,000 字符（宿主硬限）；根规则保持短小，低频说明下沉项目文档/skills/hooks/rules/scripts/CI。
- 规则激活模式（Manual / Always on / Model decision / Glob pattern）以宿主设置为准；文件存在不等于已加载。
### B.2 诊断与强制
- 最小诊断用当前 Antigravity/CLI help 与规则面板；优先新 workspace 会话核对实际加载，不可观察时按 `platform_na` 记替代证据与复测条件。
- `@` 引用仅限受控、仓库内、可审查的规则承接；禁引凭据、私有状态、网络内容或仓外未审查文件。
- 权限与危险操作用宿主 approval/policy、hooks、checkpoint/restore 或 CI；GEMINI.md 只写行为与验收。
- 改规则后需新会话或宿主 reload/refresh 复核；静态一致最多证明 `repo_verified/filesystem_projected`。
- 未经当前任务授权不重启/停止/杀掉/启动 Antigravity，不改账号、provider、模型、权限、会话或 MCP。
### B.3 回退
- `.agents/rules/` 或 `@` 不可用时保留项目根 `AGENTS.md` 与兼容文件，不把未验证回退路径升级为 `host_loaded`。
