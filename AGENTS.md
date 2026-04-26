# AGENTS.md — Skills Manager（Codex 项目级）
**项目**: skills-manager  
**适用范围**: 项目级（仓库根）  
**版本**: 3.94
**最后更新**: 2026-04-26

## 1. 阅读指引（必读）
- 本文件承接 `GlobalUser/AGENTS.md v9.43`，仅定义本仓落地动作（WHERE/HOW）。
- 固定结构：`1 / A / B / C / D`。
- 裁决链：`运行事实/代码 > 项目级文件 > 全局文件 > 临时上下文`。
- 自包含约束：执行规则以本文件正文为准，不依赖外部子文档或治理脚本作为前置条件。
- 渐进披露边界：根文件必须保留本仓事实、门禁、阻断、证据和回滚；长 runbook、示例和历史背景可下沉到子文档，但不得成为执行前置条件。
- 精简原则：根文件只写生成边界、真实入口、硬门禁、证据与回滚；长命令说明、审查模板和运行样例放入 `docs/` 或产物证据。

## A. 共性基线（仅本仓）
### A.1 事实边界
- 单一入口：`skills.ps1`；单一配置源：`skills.json`。
- `agent/` 与 `vendor/` 为生成/缓存目录；`agent/` 禁止手改。
- 自定义改动优先放 `overrides/` 或 `imports/`，避免直接改第三方缓存内容。
- `reports/skill-audit/<run-id>/` 下的 `ai-brief.md` / `outer-ai-prompt.md` 属于运行态产物；禁止直接手改，提示词源码在 `src/Commands/AuditTargets.ps1`，默认覆写入口是 `overrides/audit-outer-ai-prompt.md`。

### A.2 执行锚点
- 每次改动先声明：当前落点 -> 目标归宿 -> 验证方式。
- 默认中文沟通、中文解释、中文汇报；代码标识符、命令、日志、报错和协议字段保留英文原文。
- 全局规则给风险、语言、N/A 和门禁语义；本文件给 skills-manager 的生成边界、真实入口、运行态产物边界、证据与回滚入口。
- 小步闭环，优先根因修复；止血补丁必须标明回收时点。
- 每次变更留痕：`依据 -> 命令 -> 证据 -> 回滚`。

### A.3 N/A 分类与字段（项目内）
- `platform_na`：平台能力缺失或命令不支持。
- `gate_na`：门禁步骤客观不可执行（含脚本缺失、纯文档/注释/排版改动）。
- 两类 N/A 均必须记录：`reason`、`alternative_verification`、`evidence_link`、`expires_at`。
- N/A 不得改变门禁顺序：`build -> test -> contract/invariant -> hotspot`。

### A.4 触发式澄清协议（本仓）
- 默认执行：`direct_fix`（先修复、后验证）。
- 触发条件：同一 `issue_id` 连续失败达到阈值（默认 `2`），或现象/期望持续冲突。
- 澄清上限：一次最多 3 个高价值问题；确认后恢复 `direct_fix` 并清零失败计数。
- 留痕字段：`issue_id`、`attempt_count`、`clarification_mode`、`clarification_questions`、`clarification_answers`。

## B. Codex 平台差异（项目内）
### B.1 加载与覆盖
- 目录：`~/.codex`（可由 `CODEX_HOME` 覆盖）。
- 项目链从 Git root 到当前目录逐层加载；同层优先级：`AGENTS.override.md > AGENTS.md > configured fallback`。
- override 仅用于短期排障，结论后必须清理并复测。

### B.2 最小诊断矩阵
- 必做：`codex --version`、`codex --help`。
- 状态检查优先 `codex status`；非交互失败（如 `stdin is not a terminal`）时按 `platform_na` 落证。
- 留痕最低字段：`cmd`、`exit_code`、`key_output`、`timestamp`。

### B.3 平台异常回退
- 命令缺失或行为不一致时，必须记录：`platform_na/gate_na`、原因、替代命令、证据位置。
- `AGENTS.md` 是上下文规则；确定性验证、权限或安全拦截应落到本仓门禁、hooks、CI 或管理脚本。
- 替代命令仅用于补证据，不得改变门禁顺序与阻断语义。

## C. 项目差异（领域与技术）
### C.1 模块职责
- `skills.ps1`：统一命令调度（发现/安装/构建/更新/doctor/MCP）。
- `build.ps1`：从 `src/*` 生成根目录 `skills.ps1`。
- `skills.json`：`vendors/mappings/targets/sync_mode/mcp_servers` 的唯一配置源。
- `overrides/`、`imports/`：可维护输入层；`agent/`：分发产物层。
- `src/Commands/AuditTargets.ps1`：目标仓审查链路与内置外层 AI 提示词源码，负责生成 `ai-brief.md`、`outer-ai-prompt.md` 和 `recommendations.template.json`。

### C.2 门禁命令与顺序（硬门禁）
- build：`./build.ps1`
- test：`./skills.ps1 发现`
- contract/invariant：`./skills.ps1 doctor --strict --threshold-ms 8000`
- hotspot：`./skills.ps1 构建生效`
- fixed order：`build -> test -> contract/invariant -> hotspot`

### C.3 失败分流与阻断
- build 失败：阻断，先修构建脚本与入口拼装错误。
- test 失败：阻断，先修发现链路与映射异常。
- contract/invariant 失败：高风险阻断，禁止发布。
- hotspot 失败：阻断；如无法执行则按 `gate_na` 落证并补替代验证。

### C.4 证据与回滚
- 证据目录：`docs/change-evidence/`（不存在则在本次任务中创建）。
- 建议命名：`YYYYMMDD-topic.md`。
- 最低字段：规则 ID、风险等级、执行命令、关键输出、回滚动作。

### C.5 CI 与本地入口
- 本地门禁以 C.2 命令为准。
- CI 入口以仓库现有配置为准（当前可见：`azure-pipelines.yml`、`.gitlab-ci.yml`、`.github/workflows/ci.yml`、`.github/workflows/locked-restore.yml`）。

### C.6 Git 提交与推送边界（“全部”定义）
- `整理提交全部` 的“全部”仅指：`本次任务相关 + 应被版本管理 + 通过 .gitignore 的文件`。
- 默认不纳入“全部”：IDE/agent 本地配置、临时文件、日志、缓存与本地运行态目录。
- `push` 仅推送既有 commit 历史；文件筛选必须在 `git add/commit` 前完成。

## D. 维护校验清单（项目级）
- 仅落地本仓事实，不复述全局规则正文。
- 与全局职责互补，不重叠、不缺失。
- 协同链完整：`规则 -> 落点 -> 命令 -> 证据 -> 回滚`。
- `Global Rule -> Repo Action`：
  - `E4`: hotspot 以 `./skills.ps1 构建生效` 和 doctor 结果承接生成链路健康。
  - `E5`: skill/vendor/MCP 来源变化必须记录来源、锁定或校验依据；新增依赖前先说明必要性。
  - `E6`: `skills.json`、lock、profile、audit 输出结构变化必须记录兼容性、迁移和回滚。
- 子文档只承载细节，不替代根文件中的硬门禁和项目事实。
- 三文件同构约束：`A/C/D` 必须语义一致，仅 `B` 允许平台差异。
