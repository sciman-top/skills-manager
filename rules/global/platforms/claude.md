## B. Claude 平台差异
<!-- verified: 2026-10-05 | code.claude.com/docs/en/memory | Claude Code -->
### B.1 加载链
- 用户规则根由 `CLAUDE_CONFIG_DIR` 决定，未设置时为 `~/.claude`，文件为 `CLAUDE.md`；项目规则可位于仓库根 `CLAUDE.md` 或 `.claude/CLAUDE.md`，个人项目偏好放 gitignored `CLAUDE.local.md`。
- Claude 会把适用规则加入上下文；多个文件通常是拼接关系，不应依赖确定性 override 来隐藏上层内容。settings 的优先级与 memory 加载语义是不同机制。
- 项目 `CLAUDE.md` 用首行 `@AGENTS.md` 承接共用项目契约；import 相对包含它的文件解析，最多递归四跳，组织拆分不节省 context。
- `.claude/rules/` 无 `paths` 的规则常驻；带 `paths` 的规则通常由相关文件 Read 触发。关键安全规则不得只放在延迟触发规则中。
- 内置 Explore/Plan 子代理不自动继承完整 `CLAUDE.md` 上下文；委派时显式传递任务所需约束，或使用已验证的自定义 agent 配置。
- `--bare` 会跳过 hooks、plugin sync、auto memory 和 `CLAUDE.md` 自动发现等普通 customization，但仍可显式 `/skill-name`；`--safe-mode` 禁用普通 customization，但 managed policy 仍适用。两者都不能充当正常规则已加载的证据。
- Claude Code cloud/Web 会读取仓内项目规则和 server-managed settings，但不加载本机 `~/.claude/CLAUDE.md`；普通 Claude Web/Desktop profile/preferences 也不得假定与本机用户文件同源。
### B.2 诊断与强制
- 最小诊断：`claude --version`、`claude --help`；交互场景用 `/context`、`/memory` 核对加载，用 `/status`、`/permissions`、`/hooks` 核对强制来源；终端 `claude doctor` 只读诊断，交互 `/doctor` 可能在确认后修复，不能混用。
- 扩展命令/hook/matcher 以当前 help/schema 为准；`InstructionsLoaded` 可补加载证据。
- Claude 先用可见 native Skill/tool；仅点名不可见技能或判定可见覆盖不足且确需专门工作流时，才将完整请求+≤2 domain hint 交给 `capability-router` 一次；宿主选候选，router 只校验 closure/contract。
- 校验后按 root contract，用当前可用 Agent 承载 `one_shot` 或 `multi_turn_user_decision`；后者一题一轮等同一 child，`parent_user_input` 停父任务。无 child 仅可 parent-mediated/`not_observable`，禁摘要或伪造 child。
- 禁止通过搜索 vendor/import/agent 绕过冷技能校验。`host_admission_required`：读已验证闭包，父代理核对操作/授权后 parent-mediated 执行；仍未知、冲突或未授权才停，禁伪造 runner admission。
- `CLAUDE.md` 不是权限配置；敏感文件阻断、工具限制、sandbox、环境变量与强制动作放入用户/项目 `.claude/settings.json`、managed settings、permissions、hooks、MCP、仓库脚本或 CI。
- path rules 与 permissions 的 matcher 语义不同，不能互相替代；deny/allow 必须用正反例实测。
- Claude 内建 Bash sandbox 不支持 native Windows，只支持 macOS、Linux 与 WSL2；native Windows 按 `platform_na` 留痕，并以 permissions、`PreToolUse`、外部隔离和 CI 补位。
- bypass permissions 不提供 prompt-injection 防护，也不取消 R4/R8；只在明确授权或外部隔离边界内使用。
- 修改 auth、provider、MCP 或权限前，先区分登录链路、执行权限、模型能力与仓库代码问题。
- 未经当前任务明确确认，不得重启、停止、杀掉或自动拉起 Claude Code / Claude Desktop / `claude` 进程；先做文件级投影、dry-run、连通性探针与回滚证据。
### B.3 回退
- 命令缺失、help 与行为不一致、workspace trust/import approval 或非交互限制导致失败时，按 `platform_na` 留痕；`claude -p` 会跳过 trust 对话且可能静默忽略无效 settings，不能单独证明授权或规则生效。
