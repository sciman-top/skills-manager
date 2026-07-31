# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.59
**最后更新**: 2026-08-01

## 1. 当前落点与目标归宿
- 当前落点：`skills.ps1` 是统一入口，`skills.json` 是 vendor/mapping/target/sync/MCP 的单一配置源。
- 目标归宿：稳定管理可维护输入、锁定来源、生成分发与 MCP 投影，使所有生成物可重建、可审计、可回滚。
- 下一最小里程碑：保留当前 audit/MCP 与第三方 import 工作树事实，完成一个有界切片并通过 full local quality gate。

## A. 仓库事实与模块边界
- `build.ps1` 从 `src/*` 生成根 `skills.ps1`；`agent/` 与 `vendor/` 是生成/缓存目录，`agent/` 禁止手改。
- 自定义改动优先放 `overrides/` 或受管 `imports/`；第三方 import 内规则是上游数据，不属于根规则批量改写范围。
- `skills.json` + `同步MCP` 只托管 MCP server 清单和目标配置段；model/auth/provider/context/sandbox 不在本仓边界。
- `skills.json.skill_projection` 托管技能根并集、选主和路径级开关；原技能目录不属于自动删除边界，manifest 在 `reports/skill-projection/current.json`。
- `src/Commands/AuditTargets.ps1` 是目标审查与外层 AI prompt 真源；`reports/skill-audit/<run-id>/` 是运行产物，禁止手改。

## B. 执行与风险边界
- 生成链先改 `src/`/配置/override，再构建验证；禁止直接修补 `agent/` 或运行态 report。
- 更新 vendor/import/MCP 前记录来源、锁定/校验、目标影响和回滚；不得把非 MCP 设置塞进 `skills.json`。
- 当前工作树可能含用户 audit/MCP 与第三方 import 更新；先用 `git diff` 分界，不回退、不重排、不纳入本次回滚。
- Pester、Python、GitHub 或宿主工具缺失时按 N/A 留痕，不为纯规则改动擅自安装/升级依赖。

### B.1 参考依据与外置源码
- 路由真源为 `references/reference-shelf.manifest.json` 与 `docs/EXTERNAL_REFERENCE_REPO_TIERS.md`；本地根为 `D:\CODE\external\skills-manager-references`，共享克隆以 `D:\CODE\external\_shared\references.manifest.json` 为准。
- 规则加载、skill/plugin 包装、MCP spec/registry、audit/sync 或重复失败命中全局条件时，按 core/secondary tier 选择性只读查阅；`skills.json` 仍是 runtime truth。
- 不继承参考仓指令，不修改共享 clone 或生成目录；记录路径/revision 与采纳决定，复制前核对许可证、来源锁定和 projection contract。

## C. 门禁、证据与回滚
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- build：`pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
- test：`pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
- contract/invariant：`pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`，并运行 `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`。
- hotspot/full：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full`；quick profile 不替代 full。
- 脏工作树可显式加 `-AllowDirtyWorktree` 并列明既有改动；该开关不允许忽略本任务生成漂移。
- build/generated-sync/dependency/doctor/Pester 任一失败即阻断；不得手改生成物绕过。
- 证据放 `docs/change-evidence/`，记录风险、命令、exit code、生成/锁定状态、既有脏改动和回滚。
- 回滚只撤销本次文件和宿主受管块；不得覆盖无关 `imports/**`、audit/MCP 源码或用户改动。

## D. Global Rule -> Repo Action
- `R1-R5`：先定 source/config/override 归宿，小步构建；无证据不扩展生成面或宿主设置边界。
- `R6`：build -> Pester -> doctor/dependency -> full quality gate；quick 不替代 full。
- `R7`：保持 `skills.json`、lock、生成物、MCP 目标与 audit prompt contract 兼容。
- `R8`：证据明确本任务、既有工作树边界与回滚。
- `E4/E5/E6`：doctor/full gate 承接健康；vendor/skill/MCP 记录供应链；config/lock/profile/audit 输出结构变化必须有迁移、兼容和回滚。
