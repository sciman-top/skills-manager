# 2026-07-10 Skills / MCP / Plugin 审查与 dry-run 证据

## 1. 依据与目标

- 规则：GlobalUser `AGENTS.md v9.55`；项目契约 `AGENTS.md v2.0`。
- 风险等级：中风险分析与低风险代码修复；未执行真实技能/MCP 卸载、宿主配置修改或进程重启。
- 当前落点：`skills-manager` 审查链路、Codex MCP 投影、最终审查包 `reports/skill-audit/20260710-230917-033/`。
- 目标归宿：先生成跨技能根并集与冲突 manifest，再生成去重的平台投影；MCP 用 `enabled` / `enabled_tools` 按用途收窄。

## 2. 关键事实

- Codex：`codex-cli 0.144.1`。
- 技能根：`C:\Users\sciman\.codex\skills` 105 项，`C:\Users\sciman\.agents\skills` 95 项。
- 技能合计：200 个条目、116 个唯一名称、81 组重复名称、84 个冗余条目。
- 内容哈希：26 组相同，55 组冲突；`openai-docs` 4 份，`skill-creator` 3 份。
- 当前投影复核：`.codex\skills` 102 项、`.agents\skills` 88 项，共 190 个条目、113 个唯一名称、77 组重复名称；其中同哈希 25 组、内容冲突 52 组，仍需按 manifest 决策，不能按名称直接删除。
- MCP：当前 Codex 可见 9 个；live 状态仅 `node_repl`、`microsoft-learn`、`openaiDeveloperDocs` 启用，其余 6 个禁用。`skills.json` 管理其中 8 个，但均未声明 `enabled` / `enabled_tools`，所以受管真源与 live 临时开关存在漂移，下一次 `同步MCP` 仍会按默认启用、全工具投影。
- Plugin：实际安装并启用 10 个；Office 四类能力与教师工作流匹配，浏览器/桌面/可视化类应按任务启用。
- 诊断慢不能主要归因于 MCP：本轮先前 `codex doctor --json --summary` 约 64.6 秒，其中 MCP 检查约 5.9 秒，主要时间花在历史 task/rollout 一致性扫描。
- 安全：宿主配置发现明文 provider 凭据风险；本轮未复述、未修改，后续应在宿主真源中迁移到环境变量并轮换。

## 3. 代码修复

- `src/Commands/AuditTargets.ps1`：递归项目事实扫描排除 `.git`、`.runtime`、`.worktrees`、`node_modules`，避免临时运行目录和工作树污染目标仓结论。
- `src/Commands/AuditTargets.Snapshot.ps1`：技能快照加入 `SKILL.md` 内容哈希，稳定指纹覆盖来源、声明元数据、触发摘要与内容；MCP 快照加入有效 `enabled` / `enabled_tools`，且不把机器相关本地路径纳入技能指纹。
- `src/Commands/Mcp.ps1`：Codex 投影保留并校验 `enabled` / `enabled_tools`，等价签名同时包含两者；工具白名单按集合语义去重和排序；GitHub/PostgreSQL 显式禁用时不再探测认证命令或读取凭据，非布尔 `enabled` 在凭据操作前阻断。
- `README.md`：说明上述字段仅投影到 Codex，停用/限权不等于卸载。
- `skills.json`：跟随上游 v1.1 迁移 `to-prd -> to-spec`、`to-issues -> to-tickets`；保留旧 import 缓存键以避免移动已跟踪缓存目录，投影目标改用新官方名称。

## 4. 审查包与建议

- 最终包：`reports/skill-audit/20260710-230917-033/`。
- 路径污染复核：`repo-scans.json` 未出现 `.runtime`、`.worktrees`、`node_modules` 或 `.git` 项目路径。
- `recommendations.json`：技能新增 1、技能卸载 0、MCP 新增 0、MCP 卸载 0。
- 唯一可执行候选：技能新增原序号 `[1] microsoft-code-reference`；三个 .NET/WPF 目标仓需要 Microsoft 官方 API 签名、样例与弃用信息，现有技能没有同等职责。
- `postgres` 当前保留：上游参考实现虽已归档，但 `k12-question-graph` 已记录只读诊断入口，`governed-ai-coding-runtime` 也有真实 PostgreSQL adapter、测试与 Docker 配置；先按数据库 profile 启用，完成替代实现、凭据边界与回滚验证后再迁移。
- 仅报告项：跨根重复、`openai-docs` / `skill-creator` 冲突、PPT 执行栈、浏览器自动化栈、微信发布栈。

## 5. 已执行验证

- `./build.ps1`：通过，生成 `skills.ps1`，generated-sync 一致。
- `Invoke-Pester -Script ./tests/Unit/Core.Tests.ps1 -PassThru`：181/181 通过；覆盖 GitHub/PostgreSQL 禁用与非布尔 `enabled` 的凭据边界。
- `./tests/run.ps1`：Unit 414/414、E2E 12/12，通过且无跳过项。
- `./skills.ps1 审查目标 预检 --recommendations ...`：`success=true`，live/snapshot 技能数 102、MCP 数 8，两类指纹一致。
- `./skills.ps1 审查目标 应用 --recommendations ... --dry-run-ack "我知道未落盘"`：通过，只计划 `DRYRUN install: https://github.com/MicrosoftDocs/mcp.git --skill skills\microsoft-code-reference --ref main --mode manual`，未落盘。
- `./skills.ps1 doctor --strict --threshold-ms 8000` 与 `python ./scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`：exit 0；`build_agent` 超过 8 秒仅为非阻断性能告警。
- `./scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`：exit 0；generated-sync、dependency baseline、doctor JSON contract、Unit 与 E2E 均通过；仓库卫生仅报告本轮未跟踪的运行证据文件。

## 6. 硬门禁与回滚

- 完整门禁顺序：`build -> test -> contract/invariant -> hotspot`；已按项目契约完成。
- 代码回滚：撤销 `README.md`、`src/Commands/Mcp.ps1`、`src/Commands/AuditTargets.ps1`、对应测试及重新生成的 `skills.ps1`。
- 建议包回滚：删除 `reports/skill-audit/20260710-230917-033/recommendations.json`、`preflight-report.json`、`dry-run-summary.json` 和 `apply-report.json`。
- 运行证据回滚：删除本轮对应的 `docs/change-evidence/20260710-audit-runtime-*.md`。
- 配置回滚：本轮没有 apply，也没有修改宿主 MCP 开关；若回滚上游技能改名兼容修复，只反向恢复 `skills.json` 中 `to-spec` / `to-tickets` 对应的两组 mapping/import 字段并重新构建，不覆盖其他配置改动。

## 7. N/A

- `apply`：`gate_na`；reason = 用户未明确确认真实应用，提示词契约禁止自动执行；alternative_verification = preflight + dry-run；evidence_link = 最终包与本文件；expires_at = 用户明确批准 apply 时。
- 进程重启：`platform_na`；reason = 当前任务未授权重启 Codex/Claude；alternative_verification = 文件级投影、CLI 列表、预检与 dry-run；evidence_link = 本文件；expires_at = 用户明确授权且确有需要时。
