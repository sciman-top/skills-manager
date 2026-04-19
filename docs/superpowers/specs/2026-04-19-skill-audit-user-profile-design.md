# Skill Audit User Profile Integration Design

日期: 2026-04-19

## Goal

在现有目标仓技能审查工作流上，增加一份全局性的“用户基本需求”，并把它变成外层 AI 判断技能保留、卸载、新增的强制依据之一。

新的判断原则必须明确为：

`外层 AI 对技能保留、卸载、新增的判断，必须同时基于“用户基本需求”和“目标仓”；不能只看其一。`

脚本负责存储、校验、生成模板、组织流程和落证。外层 AI 负责把用户长文本需求转成结构化信息，并基于“用户基本需求 + 目标仓”做语义判断。

## Non-Goals

- 第一版不在脚本内内置通用 LLM 调用。
- 第一版不强制某个固定 AI CLI 或模型。
- 第一版不让脚本自行决定技能取舍。
- 第一版不自动卸载技能；卸载建议只进入推荐文件和 dry-run / apply 报告。
- 第一版不把“用户基本需求”拆成每个目标仓各自一份。

## Core Decision

“用户基本需求”采用全局一份，原因如下：

- 它描述的是用户日常工作、长期偏好、限制和常见任务，属于人层面的稳定上下文。
- 目标仓描述的是项目层面的局部上下文，变化频率更高。
- 全局一份需求 + 多个目标仓的组合，正好形成外层 AI 的双输入坐标。
- 这比每个目标仓重复维护一份需求更稳，也更适合菜单化操作。

## Architecture

整体工作流调整为：

1. 用户先维护一份全局“用户基本需求”。
2. 脚本保存用户原始长文本，并允许保存结构化结果与自由文本补充。
3. 用户继续维护目标仓列表。
4. `扫描` 时，脚本同时输出：
   - 用户基本需求原文与结构化信息
   - 目标仓扫描结果
   - 已安装 skills 摘要
   - 给外层 AI 的统一任务说明
5. 外层 AI 必须基于“用户基本需求 + 目标仓”输出推荐。
6. `应用` 继续先 dry-run，只有 `--apply --yes` 才真正改配置和执行门禁。

## Config Shape

`audit-targets.json` 扩展为：

```json
{
  "version": 2,
  "path_base": "skills_manager_root",
  "user_profile": {
    "raw_text": "我是一个长期维护多仓库 AI agent 工作流的工程师，日常会做……",
    "summary": "偏重多 agent 协同、PowerShell 自动化、仓库治理和文档质量。",
    "structured": {
      "primary_work_types": ["automation", "repo-governance", "agent-ops"],
      "preferred_agents": ["codex", "claude", "gemini"],
      "tech_stack": ["powershell", "git", "windows"],
      "common_tasks": ["skill review", "workflow automation", "documentation"],
      "constraints": ["windows-first", "prefer deterministic scripts"],
      "avoidances": ["opaque black-box automation"],
      "decision_preferences": ["evidence-first", "dry-run-before-apply"]
    },
    "last_structured_at": "2026-04-19T18:00:00+08:00",
    "structured_by": "outer-ai"
  },
  "targets": [
    {
      "name": "example-repo",
      "path": "..\\example-repo",
      "enabled": true,
      "tags": [],
      "notes": ""
    }
  ]
}
```

字段规则：

- `version` 升级到 `2`。
- `user_profile.raw_text`：用户原始长文本，必须保留，不可只保留结构化结果。
- `user_profile.summary`：外层 AI 或人工整理的自由文本补充。
- `user_profile.structured`：结构化字段集合，供外层 AI 做稳定判断。
- `last_structured_at`：最近一次结构化时间。
- `structured_by`：结构化来源，例如 `outer-ai`、`manual`。

兼容策略：

- 旧的 `version=1` 配置自动迁移到 `version=2`。
- 对旧配置补一个空的 `user_profile` 对象。
- 在未填写 `user_profile.raw_text` 时，扫描命令给出明确阻断或至少高亮提示，不允许静默继续。

## User Profile Structured Fields

第一版结构化字段固定为：

- `primary_work_types`
- `preferred_agents`
- `tech_stack`
- `common_tasks`
- `constraints`
- `avoidances`
- `decision_preferences`

原则：

- 字段本身采用稳定英文 key，便于外层 AI 和脚本处理。
- 值允许自由文本数组，不做过度枚举。
- 允许缺字段，但脚本要提示结构化不完整。
- 原文始终是最终兜底上下文。

## Commands

保留已有目标仓命令前缀，但把全局需求并入同一入口：

中文命令：

```powershell
./skills.ps1 审查目标 初始化
./skills.ps1 审查目标 需求设置
./skills.ps1 审查目标 需求查看
./skills.ps1 审查目标 需求结构化 --profile <file>
./skills.ps1 审查目标 添加 <name> <path>
./skills.ps1 审查目标 列表
./skills.ps1 审查目标 扫描 [--target <name>] [--out <dir>]
./skills.ps1 审查目标 应用 --recommendations <file> [--apply --yes]
```

英文别名：

```powershell
./skills.ps1 audit-targets init
./skills.ps1 audit-targets profile-set
./skills.ps1 audit-targets profile-show
./skills.ps1 audit-targets profile-structure --profile <file>
./skills.ps1 audit-targets add <name> <path>
./skills.ps1 audit-targets list
./skills.ps1 audit-targets scan [--target <name>] [--out <dir>]
./skills.ps1 audit-targets apply --recommendations <file> [--apply --yes]
```

行为定义：

- `需求设置` / `profile-set`：
  - 交互式录入用户长文本。
  - 脚本只保存 `raw_text`，并清空或保留旧结构化结果需要明确定义。
  - 推荐默认清空旧结构化结果并提示重新结构化，避免旧摘要污染新语义。
- `需求查看` / `profile-show`：
  - 展示当前原文、summary 和 structured 摘要。
- `需求结构化 --profile <file>` / `profile-structure --profile <file>`：
  - 脚本从外部 JSON 或 Markdown/JSON 文件导入结构化结果。
  - 不在脚本中直接调用 AI。
- `扫描`：
  - 若没有 `raw_text`，阻断并提示先设置需求。
  - 若有原文但没有结构化结果，不阻断，但输出高优先级 warning。

## Menu Integration

当前菜单只有顶层技能管理项，没有“审查目标”入口。第一版菜单整合采用单入口 + 二级菜单：

新增顶层项：

- `17) 审查目标（用户基本需求 / 目标仓 / 扫描 / 应用）`

进入后显示二级菜单：

- `1) 设置用户基本需求`
- `2) 查看用户基本需求`
- `3) 导入结构化需求`
- `4) 添加目标仓`
- `5) 列出目标仓`
- `6) 生成审查包`
- `7) 应用 recommendations（dry-run）`
- `8) 应用 recommendations（--apply --yes）`
- `0) 返回`

这样做的原因：

- 比让用户在主菜单手输整段子命令更直观。
- 不需要为每个功能额外占满顶层菜单编号。
- 仍复用已有 `Invoke-AuditTargetsCommand` 作为底层实现。

## Scan Outputs

在原有扫描产物基础上，新增：

- `reports/skill-audit/<run-id>/user-profile.json`

内容包括：

- `raw_text`
- `summary`
- `structured`
- `last_structured_at`
- `structured_by`

`ai-brief.md` 必须新增明确约束：

- 外层 AI 判断技能取舍时，必须同时参考 `user-profile.json` 和目标仓扫描结果。
- 如果 recommendation 未体现“用户基本需求”和“目标仓”的双重依据，则视为不完整推荐。
- 卸载建议、新增建议、保留建议都必须说明两类依据分别是什么。

## Recommendations Schema Changes

`recommendations.json` 扩展字段：

```json
{
  "schema_version": 2,
  "run_id": "20260419-180000",
  "target": "example-repo",
  "decision_basis": {
    "user_profile_used": true,
    "target_scan_used": true,
    "summary": "Recommendations are based on the user's daily workflow constraints and the target repo's detected stack."
  },
  "new_skills": [],
  "overlap_findings": [],
  "removal_candidates": [],
  "do_not_install": []
}
```

新增规则：

- `schema_version` 升级到 `2`。
- `decision_basis.user_profile_used` 必须为 `true`。
- `decision_basis.target_scan_used` 必须为 `true`。
- `decision_basis.summary` 必须非空。
- `removal_candidates` 为新增报告字段，只做建议，不自动执行卸载。

`new_skills[]`、`overlap_findings[]`、`removal_candidates[]` 的 `reason` 必须同时提及：

- 用户基本需求依据
- 目标仓依据

脚本可做最低限度校验：

- 要求存在 `basis.user_profile` / `basis.target_repo` 之类字段，或统一要求 `reason_user_profile` 与 `reason_target_repo`。

推荐第一版采用更稳定的字段：

```json
{
  "name": "vite",
  "reason_user_profile": "User frequently maintains frontend build workflows and prefers deterministic tooling guidance.",
  "reason_target_repo": "Target repo contains vite.config.ts and package scripts based on Vite."
}
```

## Apply Behavior

`应用` 保持原有原则：

- 默认 dry-run。
- 只有 `--apply --yes` 执行安装。
- `removal_candidates` 不自动执行卸载。
- apply-report 必须把以下内容写清楚：
  - 哪些是新增安装
  - 哪些是建议保留
  - 哪些是建议卸载但未执行

## UX Copy Requirements

帮助文本、README、菜单文案中必须强化写明：

- 用户基本需求是全局性的长期上下文。
- 目标仓是项目级上下文。
- 外层 AI 对技能取舍的判断必须同时基于两者。
- 没有用户基本需求时，不应开始正式审查。

## Tests

需要新增或修改的测试：

- `tests/Unit/AuditTargets.Tests.ps1`
  - 初始化生成 `version=2` 配置
  - 旧版 `version=1` 配置自动补齐 `user_profile`
  - `需求设置` 保存原始长文本
  - `需求结构化` 能导入结构化 JSON
  - `扫描` 在缺少 `raw_text` 时阻断
  - `recommendations schema v2` 校验 `decision_basis`
  - `removal_candidates` 只报告不执行
- `tests/E2E/SkillAudit.Tests.ps1`
  - 从原文需求 + 结构化需求 + 目标仓扫描生成审查包
  - dry-run apply 产出 removal 建议但不删配置

## Verification

项目级硬门禁保持不变：

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

额外建议验证：

```powershell
./skills.ps1 审查目标 需求设置
./skills.ps1 审查目标 需求查看
./skills.ps1 审查目标 扫描 --target <name>
./skills.ps1 审查目标 应用 --recommendations <file>
```

## Risks

- 用户原文更新后，旧结构化结果可能过期。
  缓解：更新 `raw_text` 时默认清空结构化结果并要求重新导入。
- 外层 AI 可能忽略“双依据”规则。
  缓解：recommendations schema 增加 `decision_basis` 与双 reason 字段，并在 brief 中硬性注明。
- 菜单新增二级流程后，帮助文本可能不同步。
  缓解：帮助、README、菜单在同一批次一起修改。

## Rollback

- 删除 `user_profile` 相关字段与命令。
- 保留原来的目标仓扫描与 recommendations apply 基础流程。
- `audit-targets.json` 可兼容读取 `version=2`，回滚时只忽略用户需求字段或执行一次配置降级迁移。
