## B. WorkBuddy 平台差异
<!-- verified: 2026-10-05 | 本机 CODEBUDDY_CONFIG_DIR 实测 | WorkBuddy / CodeBuddy -->
### B.1 加载链
- 用户规则根优先取 `WORKBUDDY_CONFIG_DIR`，其次取兼容变量 `CODEBUDDY_CONFIG_DIR`；均未设置时，已有 `~/.workbuddy-ai` 优先于 `~/.codebuddy`。依次尝试 `CODEBUDDY.md`、`CODEBUDDY.mdc`，取首个成功解析的文件，并加载该根下 `rules/` 中的 `.md`/`.mdc`。
- 项目从 cwd 向上遍历到盘符根之前，再按外层到内层加载；每层分别在目录本身与 `.codebuddy/` 中依次尝试 `CODEBUDDY.md`、`CODEBUDDY.mdc`、`AGENTS.md`、`AGENTS.mdc`，各取首个成功解析项。
- 当前 cwd 的 `.codebuddy/rules/` 与 `CODEBUDDY.local.md`/`CODEBUDDY.local.mdc` 另行加载；个人主目录的 `AGENTS.md` 可能是祖先项目规则，不等同于用户级规则。
- 项目根 `AGENTS.md` 保持唯一项目真源；优先候选存在时先审查遮蔽与 import。静态审查只读取授权仓内候选；祖先、imports、条件规则和加载顺序须由 fresh host evidence 补证。
### B.2 诊断与强制
- 用当前 WorkBuddy/CodeBuddy help、规则面板与脱敏 `InstructionsLoaded` 或 session-start 日志核对真实 root/scope/path；文件相等只证明 `filesystem_projected`。
- 默认仅对已有用户规则或显式指定的 root 制定投影计划；未知 active root 不自动写个人主目录或 personality 文件。
- 权限、工具限制、hooks、sandbox 与仓库脚本负责强制；规则正文不授权账号、provider、MCP、权限、会话或进程修改。宿主重启或停止需要当前任务明确授权。
- 子代理执行须满足共同授权与生命周期证据；宿主能力不可观察时记录原因和替代验证，不假定上下文继承或伪造成功。
### B.3 回退
- 加载模型以当前安装包实现与本机实测为准；解析失败、条件规则、import 或配置根不确定时保留 `platform_na` 与 fresh-session 复测条件，不把静态候选报告升级为 `host_loaded`。
