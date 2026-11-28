## B. Codex 平台差异
<!-- verified: 2026-10-25 | developers.openai.com/codex/guides/agents-md | 本轮工具 schema / codex-cli 0.159.2 -->
### B.1 加载链
- 全局在 `CODEX_HOME`（默认 `~/.codex`）取首个非空的 `AGENTS.override.md > AGENTS.md`；项目从 Git root 到 cwd 逐层按同顺序及 fallback 每层取一个，越近 cwd 越晚生效。
- `project_doc_max_bytes` 默认 32 KiB，约束整条项目规则链；关键规则前置、超限下沉。fallback 只认显式文件名，不假定 `CLAUDE.md` 或未经官方证明的选项有效。
- `AGENTS.override.md` 只作短期排障，结束后删除并用新 run/session 验证；不假定当前会话热加载。
- Personalization、Work Web instructions 与本机 `AGENTS.md` 不等同或自动互投；多文件夹仅 primary 启动任务、Git 与自动发现，secondary 仅读写。
### B.2 诊断与强制
- 最小诊断用 `codex --version`、`codex --help`；当前 help 支持时，用新 run 的 `codex debug prompt-input` 核对注入来源与内容，否则用官方建议的指令摘要探针补证。版本号答复仅证明版本标识可见，不证明全文、项目链或条件规则均已加载；不可观察项按 `platform_na` 留痕。
- 冷技能路由承载面（A.3）：父任务或该宿主选择的原生 agent 负责执行；单轮委派、直接执行或先问用户均按 A.3 由宿主选择。模型、effort 与代理继承当前宿主配置，本仓不写 `~/.codex/agents`，也不指定代理名。
- 子代理并行需满足 A.2 边界且至少两切片可独立验证、并行净收益为正，不建固定模型矩阵或代理层级；参数以当前工具 schema 为准，须有代理身份、启动与完成证据，spawn 失败可串行接管并记 `fallback=serial`。
- 项目层规则仅在 trusted repo 生效。non-managed hook 按哈希 review/trust，变化后重信任；fresh session 只证明默认路径，specialized tools 可绕过。
- `.codex/rules/*.rules` 仍为 experimental；按精确前缀建模，以 `match/not_match` 和当前 `codex execpolicy check` 实测，禁过宽 allowlist。
- Work Web 不继承本机 sandbox/approval；分别核对当前执行环境的文件系统、sandbox 与 approval 边界。never/full-access/bypass 不取消 R4/R8，仅用于明确授权或外部隔离。
- 修改 auth/provider/MCP/权限前区分登录、权限、模型与代码；未经确认不得重启/停止/杀掉/拉起 Codex，只做投影、dry-run、探针与回滚证据。
- Skills 的 `file:` locator 必须原样读取，不猜路径或回退；失败报 locator/错误并停，仅按清单另一明确 locator 重试。
### B.3 回退
- 其余命令或非交互差异按 `platform_na` 留痕；替代证据不改变共同规则和门禁语义。
