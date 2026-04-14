# GEMINI.md — Skills Manager（Gemini 项目级）
**项目**: skills-manager  
**适用范围**: 项目级（仓库根）  
**版本**: 3.85  
**最后更新**: 2026-04-10

## 1. 阅读指引（必读）
- 本文件承接 `GlobalUser/GEMINI.md`，仅定义 Skills Manager 的仓库落地动作（WHERE/HOW）。
- 固定结构：`1 / A / B / C / D`。
- 裁决链：`运行事实/代码 > 项目级文件 > 全局文件 > 临时上下文`。

## A. 共性基线（仅本仓）
### A.1 事实边界
- 单一入口：`skills.ps1`；单一配置源：`skills.json`。
- `agent/` 与 `vendor/` 为生成/缓存目录；`agent/` 禁止手改。
- 自定义改动优先放 `overrides/` 或 `imports/`，避免直接改第三方缓存内容。

### A.2 执行锚点
- 先定归宿再改动：`source/project/skills-manager/*` 为规则唯一归宿。
- 批量改动最小化回归面，优先根因修复，不做无证据预抽象。
- 每次变更留痕：`依据 -> 命令 -> 证据 -> 回滚`。

### A.3 N/A 策略
- `platform_na`：平台能力缺失或命令不支持。
- `gate_na`：仅纯文档/注释/排版或门禁脚本客观缺失时允许。
- 最低字段：`reason`、`alternative_verification`、`evidence_link`、`expires_at`。
- N/A 不得改变门禁顺序：`build -> test -> contract/invariant -> hotspot`。



### A.4 需求/功能/设计主动建议协议（本仓）
- 默认模式：`lite`；每轮主动建议上限 `1-2` 条，优先一句话可执行建议，避免长解释。
- 升级到 `standard` 的触发场景：`需求澄清`、`方案设计`、`架构选型`、`上线前评审`；升级后上限 `2-3` 条。
- 建议主题至少覆盖其一：`风险前置`、`替代方案`、`验收口径`、`最小可行路径（MVP）`。
- 去重规则：同一 `topic_signature` 在冷却窗口内默认不重复建议；仅在需求显著变化或用户追问时重触发。
- 降级规则：用户明确“只执行不建议/不要扩展”时切 `silent`；仅执行主任务。
- 执行边界：建议“可采纳可忽略”，不得改变用户主指令优先级，不得阻断当前任务。
- 策略文件：`.governance/proactive-suggestion-policy.json`（缺失时回退模板内默认值）。
- 建议留痕字段：`proactive_suggestion_mode(silent|lite|standard)`、`suggestion_count`、`suggestion_topics`、`topic_signature`、`dedupe_skipped`、`user_opt_out`。

## B. Gemini 平台差异（项目内）
### B.1 加载与覆盖
- 推荐目录：`~/.gemini`；实际以 CLI 加载结果为准。
- 优先级：`GEMINI.override.md > GEMINI.md > fallback`（平台支持时）。
- override 仅用于短期排障，结论后必须清理并复测。

### B.2 最小诊断矩阵
- 必做：`gemini --version -> gemini --help`。
- 状态/加载链类命令采用“help 探测 -> 有则执行 -> 无则 platform_na 落证”流程。
- 留痕最低字段：`cmd`、`exit_code`、`key_output`、`timestamp`。

### B.3 平台能力剖面
- 状态命令能力不可强制假定存在。
- CLI 未显式展示加载链时，补记 `active_rule_path` 与来源。
- override 能力不可用时，按 `reason + alternative_verification + evidence_link` 落证。

### B.4 平台异常回退
- 命令缺失或行为不一致时，必须记录：`platform_na/gate_na`、原因、替代命令、证据位置。
- 替代命令仅用于补证据，不得改变门禁顺序与阻断语义。

## C. 项目差异（领域与技术）
### C.1 模块职责与归宿
- `skills.ps1`：统一命令调度（发现/安装/构建/更新/doctor/MCP）。
- `build.ps1`：拼装 `src/*` 生成根目录 `skills.ps1`。
- `skills.json`：`vendors/mappings/targets/sync_mode/mcp_servers` 唯一配置源。
- `overrides/`、`imports/`：本地可维护输入层；`agent/`：最终分发产物。

### C.2 门禁命令与顺序（硬门禁）
- build：`./build.ps1`
- test：`./skills.ps1 发现`
- contract/invariant：`./skills.ps1 doctor --strict --threshold-ms 8000`
- hotspot：`./skills.ps1 构建生效`
- fixed order：`build -> test -> contract/invariant -> hotspot`

### C.3 命令存在性与 N/A 回退验证
- precheck：`Get-Command powershell`、`Test-Path ./skills.ps1`、`Test-Path ./build.ps1`。
- `doctor --strict --threshold-ms 8000` 不可执行：标记 contract/invariant=gate_na，执行 `发现 + 构建生效` 并记录契约风险。
- `构建生效` 受环境限制：标记 hotspot=gate_na，至少完成 `build + doctor --strict --threshold-ms 8000` 并记录未覆盖风险。

### C.4 失败分流与阻断
- build 失败：阻断，先修构建脚本与入口拼装错误。
- test 失败：阻断，先修发现链路与映射异常。
- contract/invariant 失败：高风险阻断，禁止分发。
- hotspot 失败：阻断；若 gate_na 按 C.3 补齐替代验证与证据。
- 执行器边界：仓内治理脚本只负责门禁编排与失败上下文输出，禁止脚本内模型 CLI 套娃自动修复；修复与重试必须由外层 AI 代理会话执行。

### C.5 构建、生效与回滚
- 构建：`./build.ps1`。
- 生效：`./skills.ps1 构建生效`。
- 最小验证：`./skills.ps1 doctor --strict --threshold-ms 8000`。
- 回滚：恢复 `skills.json` 与 `overrides/` 后重新执行 `构建生效`。

### C.6 同步与目录策略
- `sync_mode=link` 优先；`sync_mode=sync` 作为受限环境回退。
- 若 `skills.json.targets` 含 `.gemini/skills`，必须验证其与 `agent/` 同步状态。

### C.7 目标仓直改回灌策略
- source of truth：`${WORKSPACE_ROOT}/repo-governance-hub/source/project/skills-manager/*`。
- 允许在 `${WORKSPACE_ROOT}/skills-manager` 临时直改试验，但同日必须回灌并留证据。
- 回灌后必须执行：`powershell -File ${WORKSPACE_ROOT}/repo-governance-hub/scripts/install.ps1 -Mode safe`。
- 未完成“回灌 + 复验”前，禁止再次 `sync/install` 覆盖未沉淀改动。

### C.8 CI 与仓内校验入口
- GitHub Actions：`.github/workflows/quality-gates.yml`
- Azure Pipelines：`azure-pipelines.yml`
- GitLab CI：`.gitlab-ci.yml`
- Hooks：`Test-Path .git/hooks/pre-commit`、`Test-Path .git/hooks/pre-push`
- Git 配置：`git config --get commit.template`、`git config --get governance.root`
- 里程碑自动提交：治理闭环在策略允许时可于 `after_backflow`、`after_redistribute_verify`、`cycle_complete` 执行 `git add -A + 中文提交说明`，并在提交后强校验工作区干净；执行前必须先识别并隔离非本次治理改动，避免误纳入提交。
- 模板：`Test-Path docs/change-evidence/template.md`、`Test-Path docs/governance/waiver-template.md`、`Test-Path docs/governance/metrics-template.md`

### C.9 承接映射（Global -> Repo）
- R1：A.2 + C.1 + C.7（归宿先行与回灌闭环）。
- R2/R3：A.2 + C.2 + C.3（小步闭环与根因优先）。
- R4/R6：C.2 + C.3 + C.4（硬门禁、N/A 回退与阻断）。
- R7：A.1 + C.1（边界与兼容保护）。
- R8/E3：A.2 + C.5（证据与回滚可追溯）。
- E4/E5/E6：C.4 + C.6 + C.8（指标、供应链与结构变更配套校验）。
- Global 输出字段 -> Repo 证据字段：`N/A 分类/判定标准 -> A.3`，`门禁语义 -> C.2/C.4`，`证据要求 -> C.5`。

### C.10 Worktree 隔离目录约定
- 默认归宿：`~/.config/superpowers/worktrees/skills-manager/`（项目外全局目录，避免仓内污染）。
- 本仓无现成目录且无更高优先级指令时，外层 AI 代理应直接使用上述默认归宿，不再二次询问。
- 若临时改用仓内 `.worktrees/` 或 `worktrees/`，必须先通过 `git check-ignore` 验证已忽略，未忽略先修复 `.gitignore` 再创建。
- 安全约束：同一任务仅使用一种 worktree 根目录，避免跨目录混用导致证据与回滚路径分裂。

### C.11 Git 提交与推送边界（“全部”定义）
- `整理提交全部` 的“全部”仅指：`本次任务相关 + 应被版本管理 + 通过 tracked-files-policy/.gitignore 的文件`。
- 默认不纳入“全部”：IDE/agent 本地配置、临时文件、日志、备份、调试残留、缓存与本地运行态目录。
- `push` 仅推送已存在的 commit 历史，不再次筛选文件；文件筛选必须在 `git add/commit` 前完成。
- 未跟踪文件仅在被确认为本次任务产物且满足策略时纳入提交；否则保持未跟踪。
- 执行 `git add -A` 前必须先隔离非本次改动，避免误纳入。

### C.12 治理问题优先修复顺序
- 发现与 repo-governance-hub 规则/脚本/配置相关的问题时，必须先在 `${WORKSPACE_ROOT}/repo-governance-hub` 修复 source of truth。
- 修复后按固定顺序复验：`build -> test -> contract/invariant -> hotspot`，确认通过后再在目标仓执行相关命令。
- 禁止带着已知治理问题继续分发、提交或推送。
- 若为临时止血，需在证据中记录回收时点与最终归宿。
## D. 维护校验清单（项目级）
- 仅落地本仓事实，不复述全局规则正文。
- 与全局职责互补，不重叠、不缺失。
- 协同链完整：`规则 -> 落点 -> 命令 -> 证据 -> 回滚`。
- 三文件同构约束：`A/C/D` 必须语义一致，仅 `B` 允许平台差异。
- 升级后同步校验三文件版本、日期、承接映射与门禁命令一致性。
- 平台差异仅在 B 段表达；A/C/D 不承载平台实现细节。





