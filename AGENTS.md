# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.56
**最后更新**: 2026-07-14

## 1. 当前落点与目标归宿
- 当前落点：`skills.ps1` 是统一入口，`skills.json` 是 vendor/mapping/target/sync/MCP 的单一配置源。
- 目标归宿：稳定管理可维护输入、锁定来源、生成分发与 MCP 投影，所有生成物可重建、可审计、可回滚。
- 下一最小里程碑：保留当前 audit/MCP 工作树事实，完成规则契约整合并通过 full local quality gate。

## A. 仓库事实与模块边界
- `build.ps1` 从 `src/*` 生成根 `skills.ps1`；`agent/` 与 `vendor/` 是生成/缓存目录，`agent/` 禁止手改。
- 自定义改动优先放 `overrides/` 或受管 `imports/`；第三方 import 内的规则文件是上游数据，不属于本仓根规则批量改写范围。
- `skills.json` + `同步MCP` 只托管 MCP server 清单和对应目标配置段；model/auth/provider/context/sandbox 等非 MCP 宿主设置不在本仓边界。
- `skills.json.skill_projection` 托管跨技能根并集、选主和 Codex `[[skills.config]]` 路径级开关；原技能目录不属于自动删除边界，manifest 位于 `reports/skill-projection/current.json`。
- `src/Commands/AuditTargets.ps1` 是目标审查与外层 AI prompt 真源；`reports/skill-audit/<run-id>/ai-brief.md`、`outer-ai-prompt.md` 与 recommendation template 是运行产物，禁止手改。
- 默认 prompt 覆写入口是 `overrides/audit-outer-ai-prompt.md`；锁文件、配置与生成结果必须同源一致。

## B. 执行与风险边界
- 生成链改动先改 `src/`/配置/override，再构建验证；禁止直接修补 `agent/` 或运行态 report。
- 更新 vendor/import/MCP 前记录来源、锁定/校验依据、目标影响和回滚；不得把非 MCP 设置塞进 `skills.json`。
- 当前工作树可能含用户的 audit/MCP 与第三方 import 更新；先按 `git diff` 划分本次与既有改动，不回退、不重排无关内容，也不把无关内容纳入本次回滚。
- Pester、Python、GitHub 或宿主工具缺失时按 N/A 留痕，不为纯规则变更擅自安装/升级依赖。

## C. 门禁、证据与回滚
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- agent-rule contract CI：`.github/workflows/agent-rule-contract.yml` 只验证规则契约，不替代本仓产品门禁。
- build：`pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
- test：`pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
- contract/invariant：`pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`，并运行 `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`。
- hotspot/full：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full`。
- 脏工作树中验证本任务时可显式加 `-AllowDirtyWorktree`，并在证据中列明既有改动；该开关不允许忽略本任务生成漂移。
- quick：同一脚本 `-Profile quick`；不运行完整 Pester，不能替代 full。
- build/generated-sync/dependency/doctor/Pester 任一失败即阻断；不得用手改生成物绕过。
- 证据放入 `docs/change-evidence/`；记录风险、命令、exit code、生成/锁定状态、既有脏改动边界与回滚。
- 回滚只撤销本次证据明确列出的文件和宿主受管块；不得恢复、覆盖无关 `imports/**`、audit/MCP 源码或其他用户改动。

## D. Global Rule -> Repo Action
- `R1-R5`：先定 source/config/override 归宿，小步构建；无证据不扩展生成面或宿主设置边界。
- `R6`：build -> Pester -> doctor/dependency -> full quality gate；quick 不替代 full。
- `R7`：保持 `skills.json`、lock、生成物、MCP 目标与 audit prompt contract 兼容。
- `R8`：证据明确本任务与既有脏工作树边界及回滚。
- `E4`：doctor/full gate 承接健康；`E5`：vendor/skill/MCP 来源记录供应链；`E6`：config/lock/profile/audit 输出结构变化必须有迁移、兼容和回滚。
