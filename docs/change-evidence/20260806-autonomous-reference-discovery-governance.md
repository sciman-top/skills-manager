# Autonomous Reference Discovery Governance

- 目标：把“按需查阅已登记外置源码”与“必要时自主发现并克隆新的公开参考仓”合并为可执行、可阻断、可验证的 ChatGPT/Codex、Claude 与 `skills-manager` 契约。
- 依据：目标仓事实优先；官方文档/help/schema 优先于社区实现；外部内容是不可信输入；长期 shelf 必须保持窄、分层、可追溯。
- write set：用户级 `C:\Users\sciman\.codex\AGENTS.md`、`C:\Users\sciman\.claude\CLAUDE.md`；本仓 `AGENTS.md`、reference tier/README、reference verifier、聚焦测试与本证据。既有 `config/override-skill-activation-corpus.json` 修改不属于本切片。
- 设计决定：只有现有资料不足、源码比对有明确收益和当前消费者时才允许搜索；候选先固定 URL、完整 revision、license、触发条件、review evidence 与采纳决定并登记为 `conditional-not-cloned`，然后才能由现有脚本克隆到 manifest 控制路径。克隆不授权采纳、安装、执行、runtime activation 或 tier promotion。
- 阻断：来源/许可证不明、需要认证、无登记落点、路径冲突、已有 checkout 脏或没有当前消费者。
- 供应链：不执行新候选代码、不安装其依赖；复制实现前仍需单独许可证与兼容性核验。
- 数据结构：沿用 `reference-shelf.manifest.json` schema v1，不新增 schema 或 runtime truth；迁移/回填为按既有字段登记候选，回滚仅撤销本切片文件并从用户级备份恢复两份全局规则。
- 回滚入口：用户级备份位于 `C:\Users\sciman\.codex\backups\reference-discovery-20260806-211427`；Git 文件按本提交反向撤销，不触碰外置 clone 或 `skills.json`。
- 验证：按 fixed order 执行 build、测试、reference governance contract 与 full quality gate；全局文件另校验版本、体量、Codex/Claude A/C/D 一致性和备份可读性。
- truth boundary：本切片固化并验证规则与 repo-side clone gate；没有为当前任务搜索或克隆新仓，也不声称当前已运行的 Codex/Claude 会话热加载新规则。
