# Skill Audit Targets Design

日期: 2026-04-19

## Goal

在 `skills-manager` 中增加一个目标仓技能审查工作流，让 Codex CLI、Claude Code 等外层 AI 代理可以自主执行本项目脚本，基于目标仓事实、已安装 skills、外部研究结果和人工批准边界，判断哪些 skills 适合目标仓、哪些已安装 skills 存在明显重叠，并在明确授权后安装新增 skills。

脚本负责确定性、可验证、可回滚的工作。外层 AI 负责语义判断、联网研究和最终推荐。

## Non-Goals

- 第一版不在脚本内置通用联网搜索。
- 第一版不让脚本直接调用某个 AI CLI 或固定模型。
- 第一版不自动卸载或裁剪重叠 skills，只报告重叠和保留建议。
- 第一版不修改 `agent/` 生成产物目录的手工内容。
- 第一版不改变现有 `skills.json` 对 `vendors`、`imports`、`mappings`、`targets`、`mcp_servers` 的职责。

## Current Landing And Target Home

- 当前落点: `D:\OneDrive\CODE\skills-manager`
- 目标归宿: 新增目标仓技能审查命令、目标仓配置文件、审查报告和推荐应用流程。
- 主要配置归宿: 新文件 `audit-targets.json`
- 安装配置归宿: 继续使用现有 `skills.json`，通过既有 `add`、`构建生效`、`doctor` 流程更新和验证。

## Architecture

整体采用 AI-orchestrated CLI workflow。

1. `skills.ps1` 读取 `audit-targets.json`。
2. 脚本扫描目标仓，生成机器可读审查包。
3. 脚本生成 `ai-brief.md` 和 `recommendations.template.json`，交给外层 AI。
4. 外层 AI 自行搜索官方文档、优秀社区项目、最佳实践、`skills.sh`、GitHub Trending、`find-skills` 等来源。
5. 外层 AI 写入 `recommendations.json`。
6. 脚本读取推荐文件，先 dry-run 校验和展示计划。
7. 只有传入 `--apply --yes` 时，脚本才安装新增 skills。
8. 安装后脚本运行本仓门禁命令并写入执行报告。

脚本不需要理解所有语义判断，只要求推荐文件满足稳定契约。

## Files

新增长期配置:

- `audit-targets.json`

新增运行报告:

- `reports/skill-audit/<run-id>/repo-scan.json`
- `reports/skill-audit/<run-id>/installed-skills.json`
- `reports/skill-audit/<run-id>/ai-brief.md`
- `reports/skill-audit/<run-id>/recommendations.template.json`
- `reports/skill-audit/<run-id>/recommendations.json`
- `reports/skill-audit/<run-id>/apply-report.json`

新增变更证据:

- `docs/change-evidence/YYYYMMDD-skill-audit.md`

新增或修改代码:

- `src/Version.ps1`: 增加命令枚举。
- `src/Main.ps1`: 增加命令分发。
- `src/Commands/AuditTargets.ps1`: 新增目标仓审查命令实现；第一版的路径解析、目标配置读写、推荐校验 helper 默认也放在此文件内，避免提前扩大通用模块边界。
- `build.ps1`: 保持现有拼装机制，若其自动拼装 `src/Commands/*.ps1` 则无需改动。
- `tests/Unit/AuditTargets.Tests.ps1`: 新增单元测试。
- `tests/E2E/SkillAudit.Tests.ps1`: 新增本地测试仓模拟端到端流程。

## Target Config Schema

`audit-targets.json`:

```json
{
  "version": 1,
  "path_base": "skills_manager_root",
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

字段规则:

- `version`: 当前为 `1`。
- `path_base`: 第一版仅支持 `skills_manager_root`，表示相对路径按本仓根目录解析。
- `targets[].name`: 稳定标识，使用本仓现有名称规范化策略。
- `targets[].path`: 保存用户输入，推荐相对路径。
- `targets[].enabled`: 批量扫描时是否启用。
- `targets[].tags`: 可选标签，辅助外层 AI 分组和筛选。
- `targets[].notes`: 可选备注。

路径策略:

- 优先保存相对路径，便于迁移和版本管理。
- 支持绝对路径、`~` 和环境变量。
- 运行时解析出 `resolved_path`。
- `resolved_path` 写入报告，不作为主配置唯一来源。
- 如果目标仓不存在或不是 Git 仓，扫描报告必须记录错误，不静默忽略。

## Commands

中文命令:

```powershell
./skills.ps1 审查目标 初始化
./skills.ps1 审查目标 添加 <name> <path>
./skills.ps1 审查目标 列表
./skills.ps1 审查目标 扫描 [--target <name>] [--out <dir>]
./skills.ps1 审查目标 应用 --recommendations <file> [--apply --yes]
```

英文别名:

```powershell
./skills.ps1 audit-targets init
./skills.ps1 audit-targets add <name> <path>
./skills.ps1 audit-targets list
./skills.ps1 audit-targets scan [--target <name>] [--out <dir>]
./skills.ps1 audit-targets apply --recommendations <file> [--apply --yes]
```

命令行为:

- `初始化`: 创建 `audit-targets.json`，已存在时不覆盖。
- `添加`: 增加或更新目标仓记录，默认 `enabled=true`。
- `列表`: 展示配置目标、路径解析结果、存在性和启用状态。
- `扫描`: 生成审查包，不改 `skills.json`。
- `应用`: 默认 dry-run，只校验推荐文件并展示安装计划。只有 `--apply --yes` 会执行安装。

## Scan Report

`repo-scan.json` 应包含:

- `schema_version`
- `run_id`
- `target.name`
- `target.path`
- `target.resolved_path`
- `target.exists`
- `git.is_repo`
- `git.branch`
- `git.commit`
- `git.dirty`
- `detected.languages`
- `detected.package_managers`
- `detected.frameworks`
- `detected.build_commands`
- `detected.test_commands`
- `detected.agent_rule_files`
- `detected.notable_files`
- `risks`

目标仓扫描应优先读取确定性文件:

- `package.json`
- `pnpm-lock.yaml`
- `yarn.lock`
- `package-lock.json`
- `pyproject.toml`
- `requirements.txt`
- `uv.lock`
- `go.mod`
- `Cargo.toml`
- `*.sln`
- `*.csproj`
- `vite.config.*`
- `next.config.*`
- `playwright.config.*`
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`

## Installed Skills Report

`installed-skills.json` 应包含当前已安装 skills 的事实:

- `name`
- `source_kind`
- `vendor`
- `from`
- `to`
- `repo`
- `ref`
- `skill_path`
- `declared_name`
- `description`
- `trigger_summary`
- `local_path`

描述和触发信息来自 `SKILL.md` frontmatter 与正文前段。脚本只做提取，不做语义裁判。

## AI Brief

`ai-brief.md` 是给外层 AI 的任务说明，至少包含:

- 目标仓扫描摘要。
- 已安装 skills 摘要。
- 要求外层 AI 检查 skills 是否适合目标仓。
- 要求外层 AI 标出明显重叠技能和建议保留项。
- 要求外层 AI 搜索官方文档、优秀社区项目、最佳实践、`skills.sh`、GitHub Trending、`find-skills` 等。
- 要求外层 AI 把结果写入 `recommendations.json`。
- 明确重叠技能只报告，不自动卸载。
- 明确新增安装需要来源、理由、置信度和证据链接。

## Recommendations Schema

`recommendations.json`:

```json
{
  "schema_version": 1,
  "run_id": "20260419-153000",
  "target": "example-repo",
  "new_skills": [
    {
      "name": "vite",
      "reason": "Target repo uses Vite config and package scripts.",
      "install": {
        "repo": "https://github.com/antfu/skills.git",
        "skill": "skills\\vite",
        "ref": "main",
        "mode": "manual"
      },
      "confidence": "high",
      "sources": [
        "https://skills.sh/...",
        "https://github.com/..."
      ]
    }
  ],
  "overlap_findings": [
    {
      "skills": ["frontend-design", "ui-ux-pro-max"],
      "recommendation": "keep_both",
      "reason": "Different trigger scopes; overlap exists but one is implementation-focused and one is UX review-focused."
    }
  ],
  "do_not_install": [
    {
      "name": "example-skill",
      "reason": "Overlaps strongly with an existing skill and source reputation is weak."
    }
  ]
}
```

校验规则:

- `schema_version` 必须为 `1`。
- `run_id` 和 `target` 必须存在。
- `new_skills[].install.repo` 必须通过现有 repo 输入校验。
- `new_skills[].install.skill` 必须是安全相对路径，允许 `.`。
- `new_skills[].install.mode` 仅允许 `manual` 或 `vendor`。
- `confidence` 仅允许 `low`、`medium`、`high`。
- `sources` 至少一项，允许本地证据路径。
- 同一 `repo + skill + mode` 不得重复。
- 已安装的同源同路径 skill 默认跳过并记录。

## Apply Workflow

默认 dry-run:

```powershell
./skills.ps1 审查目标 应用 --recommendations reports/skill-audit/<run-id>/recommendations.json
```

执行安装:

```powershell
./skills.ps1 审查目标 应用 --recommendations reports/skill-audit/<run-id>/recommendations.json --apply --yes
```

执行步骤:

1. 加载并校验 `recommendations.json`。
2. 对每个 `new_skills` 生成等价安装命令。
3. dry-run 时只展示计划和风险。
4. apply 时逐项调用现有 `Add-ImportFromArgs`，优先复用现有安全校验、clone、路径解析和配置写入逻辑。
5. 安装完成后运行 `构建生效`。
6. 运行 `doctor --strict --threshold-ms 8000`。
7. 写入 `apply-report.json`。
8. 写入 `docs/change-evidence/YYYYMMDD-skill-audit.md`。

失败处理:

- 单项安装失败时记录失败项和错误。
- 默认遇到失败即停止后续安装，避免半自动批量误装扩大影响。
- 已完成的安装不自动回滚，但报告必须给出回滚命令或配置恢复建议。

## Overlap Policy

第一版只报告重叠技能，不自动卸载。

允许的 `overlap_findings[].recommendation`:

- `keep_both`
- `prefer_first`
- `prefer_second`
- `manual_review`

脚本只校验字段和写报告，不执行删除。

## Safety

- 默认不改配置。
- `--apply` 必须配合 `--yes` 才会安装。
- 安装继续使用现有 `Add-ImportFromArgs` 的 repo、ref、skill path 校验。
- 目标仓路径禁止通过相对路径逃逸造成删除或覆盖，因为扫描命令只读目标仓。
- 不把 `resolved_path` 当成可执行删除目标。
- 不修改目标仓内容。
- 不修改 `agent/` 手工内容。

## Tests

单元测试:

- `audit-targets.json` 初始化不覆盖已有文件。
- 添加目标仓时名称规范化、路径保留原始输入。
- 路径解析支持相对路径、绝对路径、`~`、环境变量。
- 扫描不存在路径时生成明确错误。
- 推荐 JSON 缺字段时失败。
- 推荐 JSON 重复安装项时失败。
- dry-run 不修改 `skills.json`。
- apply 必须同时要求 `--apply --yes`。

端到端测试:

- 使用本地临时 Git 仓作为目标仓。
- 使用本地临时 skill repo 作为推荐安装源。
- 执行 scan 生成审查包。
- 写入 recommendations fixture。
- dry-run 不改变配置。
- apply 后 `skills.json` 增加 import/mapping，并可构建到 `agent/`。

本仓门禁:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

## Risks

- 外层 AI 可能推荐低质量或不可信来源。缓解: 推荐文件必须记录 sources，脚本只安装显式推荐，报告中保留证据。
- 推荐 JSON 可能格式错误。缓解: 严格 schema 校验，默认 dry-run。
- 安装过程可能因网络或 Git 失败中断。缓解: 单项失败即停，记录失败原因和已完成项。
- 重叠技能判断具有主观性。缓解: 第一版只报告，不自动卸载。
- `reports/skill-audit/` 可能增长。缓解: 后续可增加清理命令，第一版不自动删除证据。

## Rollback

新增功能回滚:

- 删除新增 `src/Commands/AuditTargets.ps1`。
- 从 `src/Main.ps1` 和 `src/Version.ps1` 移除命令分发和枚举。
- 删除新增测试文件。
- 删除或保留 `audit-targets.json` 和 `reports/skill-audit/`，视是否需要保留审查证据。
- 重新运行 `./build.ps1` 生成 `skills.ps1`。

安装推荐回滚:

- 根据 `apply-report.json` 中记录的安装项，从 `skills.json` 移除对应 `imports` 和 `mappings`。
- 删除对应 `imports/<name>` 缓存目录，若该目录只服务本次安装。
- 运行 `./build.ps1`、`./skills.ps1 构建生效`、`./skills.ps1 doctor --strict --threshold-ms 8000`。

## Approval

本设计已按用户确认的边界编写:

- 目标仓配置使用单独 `audit-targets.json`。
- 安装使用默认 dry-run、`--apply --yes` 执行的混合模式。
- 重叠技能只报告，不自动卸载。
- 脚本不做通用联网搜索。
- 外层 AI 通过 `recommendations.json` 文件把推荐交回脚本。
