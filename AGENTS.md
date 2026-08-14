# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.76
**最后更新**: 2026-08-14

## 1. 当前落点与目标归宿
- `skills.ps1` 是 CLI 入口；`skills.json` 是 vendor、import、mapping、target、MCP 与 skill projection 配置真源。
- 本仓管理本地技能/MCP、规则审查、原生技能投影，以及 `rules/global/` 中 Codex/Claude 全局规则唯一源和受控用户目录投影；不接管宿主 runtime、auth、provider、模型、权限、会话或插件缓存。
- 真值分级固定为 `repo_verified -> filesystem_projected -> host_loaded -> live_accepted`；仓库测试、文件相等或旧 receipt 不得冒充更高层验收。

## A. 仓库事实与模块边界
- `build.ps1` 从 `src/` 生成根 `skills.ps1`，并从 `overrides/{custom,patches,resources}` 生成 `agent/`；禁止手改生成物。
- `vendor/`、`imports/`、`agent/` 和 ignored `reports/` 是物化或运行目录；先改 source/config/override，再构建。
- `src/Commands/AuditTargets*.ps1` 生成并消费 `reports/skill-audit/<run-id>/`；运行 receipt 与 recommendations 同目录，不进入 tracked docs。
- `src/Application/RuleEstate*.ps1` 负责只读审查和 reviewed change-set 事务；写入必须有精确 scope、token、receipt 和回滚。
- `rules/global/{codex,claude}/` 是全局规则唯一源；`GlobalRuleProjection` 只投影到明确的用户规则文件，使用 source/target hash、plan token、备份、receipt 与精确回滚。
- `skill_projection` 只管理 inventory、domain catalog、metadata budget 和 native placement；语义选择归宿主，`capability-router` 仅是显式 fallback/policy validator。
- runtime 为 PowerShell 7-only。没有仓外消费者、当前独立失败或可量化净收益的抽象、兼容层、候选清单、遥测、门禁和历史状态库应删除。

## B. 执行与风险边界
- 首次写入前冻结 goal、non-goals、exact write set、最低验证和 stop；只扩展能防止当前真实失败的范围。
- 用户/并发改动先用 `git diff` 分界；不回退、不重排、不混入本次回滚。禁止批量改写第三方 import。
- 更新 vendor/import/MCP 前记录来源、锁定、影响和回滚；宿主/provider/auth/session/plugin/MCP mutation 需要当前明确授权。
- 外置参考真源为 `references/reference-shelf.manifest.json`；只操作其 `D:\CODE\external\skills-manager-references` 路径。克隆/刷新只代表只读参考，不代表采纳、安装或执行。
- 已退役 `D:\CODE-other\governed-ai-coding-runtime` 仅作全局规则历史参考；不得恢复其 runtime、目标仓 registry、跨仓同步或治理控制面。
- 规则/文档不得复制运行状态；Git diff、受影响测试和 ignored runtime receipt 是默认证据，不为普通变更新增 evidence/task/ADR。

## C. 门禁、证据与回滚
- 多层适用时顺序固定为 `build -> test -> contract/invariant -> hotspot`，只跑覆盖当前失败面的最低充分层。
- 文档/规则：`git diff --check` + 受影响 verifier/test。source/config/generated seam：运行一次 `build.ps1`，再跑受影响测试；clean closeout 核对 `skills.ps1` 无漂移。
- 全局规则源/投影：先 `global-rules-plan`，显式 token 应用后运行 `global-rules-check`；文件相等只证明 `repo_verified/filesystem_projected`，fresh host probe 才能证明 `host_loaded`。
- focused closeout 沿用受影响验证；runtime、安全、数据、迁移、公开契约、依赖、打包或跨面风险才运行一次 full gate。
- full：只在 runtime、安全、数据、迁移、公开契约、依赖、打包或跨面风险时运行一次 `scripts/quality/run-local-quality-gates.ps1 -Profile full`；脏树需显式 `-AllowDirtyWorktree`。
- live doctor 只在 release/host health 明确需要时另跑 `skills.ps1 doctor --strict`；不替代 full，也不证明 `host_loaded`。
- 失败按原路径 focused 重验；回滚只撤本次切片，不覆盖无关 import、audit/MCP 或用户资产。

## D. Global Rule -> Repo Action
- Git profile: baseline=`main`; upstream=`origin/main`; closeout=`proportional_focused_or_full`。
- `R1`：归宿只选 `src/config/overrides/rules/docs`；`R2`：小步受影响验证；`R3`：临时 seam 写明删除条件。
- `R4`：宿主/MCP/跨仓写入按 B/C 授权；`R5`：无真实消费者或失败即不扩抽象；`R6`：focused/full 二选一。
- `R7`：保持 config/lock/generated/MCP/audit contract；`R8`：依据、diff、验证和回滚可追溯。
- `S1`：最短真实 CLI 主链；`S2`：状态只在 config/runtime receipt；`S3`：研究达到可逆决定即停。
- `S4`：`references/reference-shelf.manifest.json` 只保留当前 reference set；`S5`：`scripts/verify-reference-governance.ps1` 与 `src/Application/RuleEstate.ps1` fail closed。
- `E4`：focused/full verification output；`E5`：config/lock/reference provenance；`E6`：config/receipt 变化保留兼容与回滚。
