## B. Antigravity 平台差异
<!-- verified: 2026-10-08 | antigravity.google/docs/rules | Antigravity 2.21.1 -->
### B.1 加载链
- 受管全局真源投影到 `~/.gemini/GEMINI.md`；宿主也读取 `~/.gemini/` 及其 `config/` 中的 AGENTS.md/GEMINI.md 和全局 rules，额外文件可能叠加规则，不能仅凭受管文件相等证明整个加载面。
- 宿主原生沿文件目录到 workspace 根读取 `AGENTS.md`/`GEMINI.md`、`.agents/` 同名文件及 `.agents/rules/*.md`；优先直接使用项目 `AGENTS.md`，不为缺少适配器新增副本。已有适配器须含合法 YAML `trigger: always_on`，用 `@[Project contract](../../AGENTS.md)` 内联同一真源；裸 `@../../AGENTS.md` 仅规范化路径引用，不内联内容。仓根 `GEMINI.md` 的 `@AGENTS.md` 保留作 Gemini CLI 兼容引用，不据此证明 Antigravity 已内联。
- 单文件上限 12,000 字符（宿主硬限）；根规则保持短小，低频说明下沉项目文档/skills/hooks/rules/scripts/CI。
- `.agents/rules/*.md` 缺 frontmatter 或 trigger 非 `always_on/model_decision/glob/manual` 会被静默丢弃；model_decision 需 description，glob 需 globs/glob。规则目录只扫描直接子文件；条件规则和显式登记以宿主设置为准，文件存在不等于已加载。
### B.2 诊断与强制
- 最小诊断用当前 Antigravity/CLI help 与规则面板；优先新 workspace 会话核对实际加载，不可观察时按 `platform_na` 记替代证据与复测条件。
- `@` 引用仅限受控、仓库内、可审查的规则承接；禁引凭据、私有状态、网络内容或仓外未审查文件。
- 权限与危险操作用宿主 approval/policy、hooks、checkpoint/restore 或 CI；GEMINI.md 只写行为与验收。
- 改规则后需新会话或宿主 reload/refresh 复核；静态一致最多证明 `repo_verified/filesystem_projected`。
- 未经当前任务授权不重启/停止/杀掉/启动 Antigravity，不改账号、provider、模型、权限、会话或 MCP。
### B.3 回退
- `.agents/rules/` 或 `@` 不可用时保留项目根 `AGENTS.md` 与兼容文件，不把未验证回退路径升级为 `host_loaded`。
