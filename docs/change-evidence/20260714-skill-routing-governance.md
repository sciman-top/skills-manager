# 2026-07-14 Skill 路由与外部能力审查治理

## Goal / Boundary

- 落点：`skills.json`、`config/skill-routing-policy.json`、`src/Commands/SkillRouting.ps1`、审查快照/建议契约及对应测试。
- 目标：保留各工作面已有 skills，用显式 router/executor/validator/operator/workflow/reference 角色和 profile 预算治理语义重叠；system/plugin 能力只读入账，不进入自动卸载面。
- 模式：`observe`。结构错误阻断；强触发和共激活冲突只告警，不自动修改 profile。
- 未执行：没有运行 `技能投影`/`构建生效`/`同步MCP`，没有修改 live `~/.codex/config.toml`，没有执行 recommendations apply，没有操作 Codex/ChatGPT 进程。

## Existing Dirty Worktree Boundary

本轮开始前已存在并保留：

- `references/updates/reference-refresh-latest.md` 与两个 dated reference refresh 文件。
- `src/Commands/AuditTargets.Snapshot.ps1` 中 resource-only override 排除修复及 `tests/Unit/AuditTargets.Tests.ps1` 对应测试。
- 三份旧 audit runtime evidence。它们未被回退、覆盖或纳入本轮回滚。

## Changes

- 新增六组 skill routing policy：development、PPT 课件、中文内容发布、初中物理动画、Windows 教师软件、浏览器自动化。
- 检测 mandatory activation、human gate、persistence/commit、delegation 四类强触发，并报告两组真实共激活冲突。
- 只读解析启用插件及最新可用 cache 版本；plugin ID 使用 Windows-safe 路径段白名单，TOML/trigger regex 使用 1 秒超时。
- 外部 plugin 元数据参与 profile 预算；system skills 已作为 projection 的强制 active 项参与原预算。
- projection manifest 增加 external inventory、实际/有效外部字符预算和 routing report。
- audit bundle 将 `skills` 与只读 `external_skills` 分离；新快照同时记录 skills、MCP、external 三类指纹，旧快照没有 external 指纹时保持兼容。
- `overlap_findings` 支持结构化 router/member roles，并校验 router 必须存在且使用 `role=router`。
- portable 包纳入 `config/`，本地 full quality gate 纳入 `skill-routing`。

代码审查与失败测试发现并修复：

- 可选 `skill_projection.aliases` 缺失时被误判为一条空 alias。
- nested hashtable 的 `external_skill_inventory.plugin_cache_path` 字段存在性未被正确验证。
- hashtable external inventory 不能被运行时清单读取。
- Windows plugin ID 的 `C:` 等非法路径段未被拒绝。
- routing policy 与 recommendations 的 router/member 角色不一致未被阻断。

## Live Read-only Facts

- 受管 skills：108；projection canonical：112；默认 active：21，其中 system active：5。
- 启用 plugin skills：7；plugin 元数据：1330 chars。
- 外部预算 reserve/effective：1700/1700 chars；默认 profile：7150/8000，全部 10 个 profile 均通过。
- duplicate name groups：0。
- routing findings：10，`blocking=false`。
- 共激活冲突：`brainstorming + planning-and-task-breakdown`；`git-workflow-and-versioning + incremental-implementation`。

## Fresh Audit / Dry-run

- run：`reports/skill-audit/20260714-014727-970/`。
- prompt contract：`audit-prompt-v20260714.1`，run/current 匹配。
- 新鲜快照：108 managed skills、12 external skills（5 system + 7 plugin）、8 MCP、9 target repos。
- staleness：skills/MCP/external 全部 `false`；preflight issues 为 0。
- recommendations：skill add 0、skill remove 0、MCP add 0、MCP remove 0；5 组 overlap、7 个 do-not-install observation。
- dry-run：`success=true`、`persisted=false`，全部 changed counts 为 0。

判断：四类 mutation 建议保持 no-op 正确。PostgreSQL reference MCP 已 archived 且 npm deprecated，但当前默认停用，目标仓仍有明确只读诊断需求；在维护中替代、最小权限和回滚尚未验证前，保留停用配置优于立即删除或启用。

## Verification

固定顺序均为 exit 0：

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`：469 Unit / 12 E2E，失败 0。
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`：strict 通过；`apply_targets` 平均值超过 5000ms 仅告警。
4. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`：full 通过。
6. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skill-routing.ps1 -ReportPath reports/skill-routing/current.json`
7. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 审查目标 预检 --recommendations reports\skill-audit\20260714-014727-970\recommendations.json`
8. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 审查目标 应用 --recommendations reports\skill-audit\20260714-014727-970\recommendations.json --dry-run-ack "我知道未落盘"`

## Rollback

仅回滚本证据列出的 routing policy/source/tests/build/quality/portable/audit-contract 改动和本文件；重新运行 `build.ps1` 恢复生成同步。不得回滚 reference refresh、旧 audit evidence 或 resource-only override 修复。
