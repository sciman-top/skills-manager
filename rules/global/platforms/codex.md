## B. Codex 平台差异
<!-- verified: 2026-10-05 | learn.chatgpt.com/docs/agent-configuration | codex-strict-config -->
### B.1 加载链
- 全局在 `CODEX_HOME`（默认 `~/.codex`）取首个非空的 `AGENTS.override.md > AGENTS.md`；项目从 Git root 到 cwd 逐层按同顺序及 fallback 每层取一个，越近 cwd 越晚生效。
- `project_doc_max_bytes` 默认 32 KiB，约束整条项目规则链；关键规则前置、超限下沉。fallback 只认显式文件名，不假定 `CLAUDE.md` 或未经官方证明的选项有效。
- `AGENTS.override.md` 只作短期排障，结束后删除并用新 run/session 验证；不假定当前会话热加载。
- Personalization、Work Web instructions 与本机 `AGENTS.md` 不等同或自动互投；多文件夹仅 primary 启动任务、Git 与自动发现，secondary 仅读写。
### B.2 诊断与强制
- 最小诊断用 `codex --version/help`；加载核验优先新 run 的 `codex debug prompt-input`，必要时再用官方建议的指令摘要探针。扩展命令须由当前 help 证明；不可用按 `platform_na` 记录替代证据/复测条件，日志仅补证。
- 宿主先按可见元数据选技能；仅当用户点名不可见本地技能，或判定可见技能不足且确需专门工作流时，才一次调用 `capability-router`（完整请求、至多两个 domain hint），由宿主在候选中语义选择并精确校验候选与依赖闭包。显式与隐式命中都必须保留 router 的 `execution_contract`：`one_shot` 才可按 admission 交给 `cold-capability-runner`；`parent_user_input` 停在用户输入；`multi_turn_user_decision` 由 `design-griller` 一题一轮、父任务转发并等待同一 child 的用户答案，禁用“结论/停止”降格为单轮摘要；缺失/冲突契约禁止自动执行。提及/讨论技能或语义不确定时不是调用；不得作每请求 middleware。
- 已有共同协议要求的明确委派授权后，至少两个切片可独立验证、write set 互斥且并行净收益为正时才并行。委派只声明完成该切片所需的 scope、write set、proof 与 stop，不建立固定模型矩阵、代理层级或 wave 治理。
- 禁止通过搜索 vendor/import/agent 绕过冷技能校验。`host_admission_required`：读已验证闭包，父代理核对操作/授权后 parent-mediated 执行；仍未知、冲突或未授权才停，禁伪造 runner admission。
- 指定非默认 `agent_type` 时 `fork_turns` 只允许 `"none"` 或正整数，禁止 `"all"`；仅观察到 `started`、有效 child thread id 与终态 `completed` 才可报告子代理成功。spawn 失败可串行接管，但须记 `fallback=serial`。
- 项目层规则仅在 trusted repo 生效。non-managed hook 按哈希 review/trust，变化后重信任；fresh session 只证明默认路径，specialized tools 可绕过。
- `.codex/rules/*.rules` 仍为 experimental；按精确前缀建模，以 `match/not_match` 和当前 `codex execpolicy check` 实测，禁过宽 allowlist。
- Work Web 不继承本机 sandbox/approval；分别核对当前执行环境的文件系统、sandbox 与 approval 边界。never/full-access/bypass 不取消 R4/R8，仅用于明确授权或外部隔离。
- 修改 auth/provider/MCP/权限前区分登录、权限、模型与代码；未经确认不得重启/停止/杀掉/拉起 Codex，只做投影、dry-run、探针与回滚证据。
- Skills 的 `file:` locator 必须原样读取，不猜路径或回退；失败报 locator/错误并停，仅按清单另一明确 locator 重试。
- 模型编排真源 `src/model-orchestration/`；`429/quota/auth` 与 provider 故障**不是**升档信号，按 `nearest lower effort -> 下一 active preset` 重选，仅确认 overload 可兼升一档；禁热切换、别名替换或重放写入，重选须记录失败 tuple 与剩余范围。槽位数 ≠ 并行数（`max_concurrent_threads_per_session`）。
### B.3 回退
- 其余命令或非交互差异按 `platform_na` 留痕；替代证据不改变共同规则和门禁语义。
