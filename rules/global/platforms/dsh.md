## B. DeepSeek Harness 平台差异
<!-- verified: 2026-11-05 | dsh 内置插件契约 @deepseek-ai/dsh-agent-instructions 与 @deepseek-ai/dsh-skill-filesystem（app.asar 提取）| DeepSeek Harness -->
### B.1 加载链
- 用户全局链按序加载 `~/.dsh/AGENTS.md` 与共享槽 `~/.agents/AGENTS.md`；两路径由进程策略解析（`$DSH_HOME`/`$DSH_AGENTS_HOME`），行配置不可改。本仓只投影 `~/.dsh/AGENTS.md`，共享槽保持空缺：内容不同的文件不去重会双渲染，宿主专属差异入共享槽会泄漏给其它读取方。
- 项目链自 `.git` 项目根向会话工作目录逐层加载 `AGENTS.md`、`CLAUDE.md` 并叠加 `AGENTS.local.md`、`CLAUDE.local.md`，广度到具体排序；权限或 I/O 失败即中止上溯，不回退祖先根。
- 同组候选 trim 后内容相同的文件只渲染一次；更具体文件优先，预算不足先省略广度文件（user-global 链 harness-home 先于 shared-root 被省略）。
- 用户级技能走 `~/.agents/skills`（既有投影目标，五宿主技能天然流入；不另建 `~/.dsh/skills` 投影以免双载）。技能 frontmatter 支持 `disable-model-invocation` 与 `user-invocable`，非法布尔值整技能丢弃并告警。
### B.2 预算与诊断
- 指令预算默认 64 KiB/链（user-global 与 project 独立计，单消息至多两倍）；本仓 130 行/16 KiB 保守预算继续生效，不因宿主余量放宽。
- 指令为 durable sourced user/message，可从 `~/.dsh/sessions` 会话日志取证；第一方 read/write/edit 触达更深层目录后注入新适用文件，变更替换、消失出移除通知。
- 文件一致只证明 `filesystem_projected`；dsh 新会话 baseline 出现 `Instructions from: ~/.dsh/AGENTS.md` 来源段才可称 `host_loaded`，真实任务验收另列。
- `~/.dsh/profiles/desktop/cordis.patch.yml` 是受控配置面（id 定向覆盖/禁用/插入，支持 `!!js` 表达式）；调整指令链行为须走 patch 行并留备份回滚入口。
### B.3 回退
- 命令或接口不可用、插件行为与文档不一致、或权限/确认拦截导致失败时，按 `platform_na` 留痕；不重启、停止或杀掉 dsh 进程，不修改 `~/.dsh` 凭据与网关配置。
