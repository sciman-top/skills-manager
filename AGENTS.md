# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.77
**最后更新**: 2026-08-25

## 1. 产品边界与入口
- `skills.ps1` 是唯一 CLI entrypoint；`skills.json` 是 vendor、import、mapping、target、MCP 与 skill projection 的 runtime source of truth。项目根 `AGENTS.md` 同时是 Codex、Claude 与 ZCode 的项目级规则源；ZCode 仅读取当前 Workspace 根文件。
- 本仓管理本地技能/MCP、目标仓规则审查、原生技能投影，以及 `rules/global/` 中的全局规则源和受控投影；不接管宿主 runtime、auth、provider、模型、权限、会话或插件缓存。
- 真值层级为 `repo_verified -> filesystem_projected -> host_loaded -> live_accepted`；低层证据不得外推。

## A. 仓库真值与领域不变量
- `build.ps1` 只从 `src/` 生成根 `skills.ps1`；`skills.ps1 构建生效` 才会从 `overrides/{custom,patches,resources}` 物化 `agent/` 并执行受控投影；禁止手改生成物。
- `vendor/`、`imports/`、`agent/` 与 ignored `reports/` 是物化或运行目录；先改 source/config/override，再构建。
- AuditTargets 运行包固定为同一 run 目录内的 `snapshot.json`、`recommendations.json`、`receipt.json`；freshness、target drift、授权、补偿/回滚与真值边界必须 fail closed。
- Rule Estate 写入必须绑定 reviewed input、精确 scope/token/before-hash、receipt 与回滚；全局规则投影必须绑定 source/target hash、plan token、备份与精确回滚。
- runtime 为 PowerShell 7-only。没有真实调用方、当前失败或可量化净收益的抽象、兼容层、候选清单、遥测、门禁与历史状态库应删除。

## B. 执行边界
- 日常合同只冻结 `Goal / Exact write set / Minimum proof / Stop`；仅扩展能防止当前真实失败的范围。
- 先用 `git diff` 分界用户/并发改动；不回退、不重排、不混入本次回滚，禁止批量改写第三方 import。
- 无指代载荷（“这个X”类指代且会话与仓库上下文均无锚点）必须停在 parent_user_input 索要目标；以“最新文件”等启发式自选目标、读取用户个人目录或跨仓文件替代提问，均视为 fail-open。
- 更新 vendor/import/MCP 前记录来源、锁定、影响与回滚；宿主/provider/auth/session/plugin/MCP mutation 需要当前明确授权。
- `references/reference-shelf.manifest.json` 仅服务显式 refresh/verify 的可选只读开发缓存；缺失或未刷新不得阻断普通 build/test/update/projection，也不得自动采纳、安装、执行或影响 runtime projection。
- 规则/文档不复制运行状态；Git diff、受影响测试和 ignored runtime receipt 是默认证据，不为普通变更新增 evidence/task/ADR。

## C. 最低门禁
- 本地收口优先 `run-local-quality-gates.ps1 -Profile auto`（与 CI 共享分类器，含 non-ignored untracked fail-safe，无法判定时选 full）；显式档位仅用于复现或覆盖。
- 多层适用时顺序为 `build -> test -> contract/invariant -> hotspot`，只跑覆盖当前独立失败的最低充分层。
- 文档/规则运行 `git diff --check` 与受影响 verifier/test；source/config/generated seam 运行一次 `build.ps1` 后跑受影响测试，并核对 `skills.ps1` 无生成漂移。
- 只有 runtime、安全、数据、迁移、公开契约、依赖、打包或跨面风险才运行一次 `scripts/quality/run-local-quality-gates.ps1 -Profile full`；脏树显式加 `-AllowDirtyWorktree`。
- 全局规则文件相等最多证明 `repo_verified/filesystem_projected`；`doctor --strict` 不证明 `host_loaded`，后者必须使用 fresh host probe。

## D. 回滚与收口
- Git baseline=`main`，upstream=`origin/main`；默认按 focused 或风险触发的一次 full gate 收口。
- 失败沿原路径 focused 重验；回滚只撤本次切片，不覆盖无关 import、audit/MCP 或用户资产。
- 外置参考仓、宿主投影与 live acceptance 均为显式工作流，不属于普通编码完成条件。
