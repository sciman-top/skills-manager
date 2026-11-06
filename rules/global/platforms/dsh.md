## B. DeepSeek Harness 平台差异
<!-- verified: 2026-11-06 | dsh 内置插件契约 @deepseek-ai/dsh-agent-instructions 与 @deepseek-ai/dsh-skill-filesystem（app.asar 提取）；强制面锚点 dsh-permission-presets / dsh-sandbox-policy / dsh-user-approval / dsh-plan-mode（app.asar 提取）；官方仓 github.com/deepseek-ai/deepseek-harness（developer preview）| DeepSeek Harness -->
### B.1 加载链
- 用户全局链按序加载 `~/.dsh/AGENTS.md` 与共享槽 `~/.agents/AGENTS.md`；两路径由进程策略解析（`$DSH_HOME`/`$DSH_AGENTS_HOME`），行配置不可改。本仓只投影 `~/.dsh/AGENTS.md`，共享槽保持空缺：内容不同的文件不去重会双渲染，宿主专属差异入共享槽会泄漏给其它读取方。
- 项目链自 `.git` 项目根向会话工作目录逐层加载 `AGENTS.md`、`CLAUDE.md` 并叠加 `AGENTS.local.md`、`CLAUDE.local.md`，广度到具体排序；权限或 I/O 失败即中止上溯，不回退祖先根。
- 同组候选 trim 后内容相同的文件只渲染一次；更具体文件优先，预算不足先省略广度文件（user-global 链 harness-home 先于 shared-root 被省略）。
- 用户级技能走 `~/.agents/skills`（既有投影目标，五宿主技能天然流入；不另建 `~/.dsh/skills` 投影以免双载）。技能 frontmatter 支持 `disable-model-invocation` 与 `user-invocable`，非法布尔值整技能丢弃并告警。
- 冷技能路由与 `execution_contract` 分三支见 A.3；本节只声明 DSH 的承载面：用户级技能走 `~/.agents/skills` 共享根，且当前无 verifier 证明 DSH 具备 native custom-agent spawn 面，故 `one_shot`/`multi_turn_user_decision` 默认 parent-mediated 并在汇报中注明实际承载，不冒充 native runner。`disable-model-invocation` 的技能不会进入可见目录，正是需要本条冷路径的对象。
### B.2 预算与诊断
- 指令预算默认 64 KiB/链（user-global 与 project 独立计，单消息至多两倍）；本仓 130 行/16 KiB 保守预算继续生效，不因宿主余量放宽。
- 指令为 durable sourced user/message，可从 `~/.dsh/sessions` 会话日志取证；第一方 read/write/edit 触达更深层目录后注入新适用文件，变更替换、消失出移除通知。
- 文件一致只证明 `filesystem_projected`；dsh 新会话 baseline 出现 `Instructions from: ~/.dsh/AGENTS.md` 来源段才可称 `host_loaded`，真实任务验收另列。
- 最小诊断：`/permission` 核对沙箱与审批预设、`/plan` 核对计划模式；文件级投影、dry-run 与 receipt 属于 `platform_na` 替代证据，不冒充 `host_loaded`。
- `~/.dsh/profiles/desktop/cordis.patch.yml` 是受控配置面（id 定向覆盖/禁用/插入，支持 `!!js` 表达式）；调整指令链行为须走 patch 行并留备份回滚入口。
### B.3 强制面与回退
- dsh 无 hooks 机制；确定性强制面是沙箱模式（`read-only` / `workspace-write` / `danger-full-access`，部署默认 fail-closed `read-only`）与审批策略（`ask` / `never`；`ask` 缺应答器以拒绝方式关闭，仅一次性授权、无 `allow-always`）。`/permission` 预设捆绑两旋钮，`permission` 设置命名空间固定新会话默认。
- `/plan` 计划模式与 `exit_plan_mode` 仅是引导（工具仍全可用）；强制限制必须落在沙箱与审批，不得依赖计划模式本身。
- 命令或接口不可用、插件行为与文档不一致、或权限/确认拦截导致失败时，按 `platform_na` 留痕；不重启、停止或杀掉 dsh 进程，不修改 `~/.dsh` 凭据与网关配置。
