# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.84
**最后更新**: 2026-10-04

## 1. 产品边界与入口
- `skills.ps1` 是技能/MCP 管理的唯一 CLI entrypoint；`skills.json` 是 vendor、import、mapping、target、MCP 与 skill projection 的 runtime source of truth。项目根 `AGENTS.md` 是 Codex、Claude、ZCode、Antigravity 与 WorkBuddy 的共同项目级规则源；Antigravity 通过 `.agents/rules/00-project.md` 的受控 `@../../AGENTS.md` 适配器承接。
- 主 CLI 管理本地技能/MCP、目标仓规则审查、原生技能投影及 `rules/global/` 的受控投影，不接管模型或宿主 runtime。独立的 `src/model-orchestration/` 仅提供显式 preset 配置和受控启动，遵循其局部 `AGENTS.md`，不进入主 CLI 构建链；两者均不接管 auth、provider、权限、会话或插件缓存。
- 真值层级为 `repo_verified -> filesystem_projected -> host_loaded -> live_accepted`；低层证据不得外推。

## A. 仓库真值与领域不变量
- `build.ps1` 从 `src/` 生成根 `skills.ps1`，并从 `rules/global/common.md` 与 `platforms/*.md` 生成五份全局宿主规则；`-Check` 只读核对漂移。`skills.ps1 构建生效` 才会从 `overrides/{custom,patches,resources}` 物化 `agent/` 并执行受控投影；禁止手改生成物。
- `vendor/`、`imports/`、`agent/` 与 ignored `reports/` 是物化或运行目录；先改 source/config/override，再构建。
- 交付物目录契约固定为：`artifacts/deliveries/<version>/{standard-install,portable,source,private-snapshot}/` 是同版本四类交付物；前三项公共包不含 skills/MCP，私用快照仅限可信私有介质；`rescan/<run-id>/` 只是辅助清单，`artifacts/history/<kind>/<version-or-date>/` 是人工历史留存，`artifacts/work/<kind>/<run-id>/` 是临时构建/验证/evidence；`artifacts/` 根层不得放生成文件，正式公共下载以 GitHub Release 为准。
- AuditTargets 运行包固定为同一 run 目录内的 `snapshot.json`、`recommendations.json`、`receipt.json`；freshness、target drift、授权、补偿/回滚与真值边界必须 fail closed。
- Rule Estate 写入必须绑定 reviewed input、精确 scope/token/before-hash、receipt 与回滚；全局规则投影必须绑定 source/target hash、plan token、备份与精确回滚。
- runtime 为 PowerShell 7-only。没有真实调用方、当前失败或可量化净收益的抽象、兼容层、候选清单、遥测、门禁与历史状态库应删除。

## B. 执行边界
- 默认主代理串行完成；子代理须有用户或适用项目/技能规则的明确委派授权，并限定独立切片、互斥 write set、最低证明与 stop；“继续”或要求深入分析不构成授权。
- 日常合同只冻结 `Goal / Exact write set / Minimum proof / Stop`；覆盖当前明确需求或真实失败，验收满足即停止，不把额外优化吸收为任务。
- 先用 `git diff` 分界用户/并发改动；不回退、不重排、不混入本次回滚，禁止批量改写第三方 import。
- 无指代载荷（“这个X”类指代且会话与仓库上下文均无锚点）必须停在 parent_user_input 索要目标；以“最新文件”等启发式自选目标、读取用户个人目录或跨仓文件替代提问，均视为 fail-open。
- 更新 vendor/import/MCP 前记录来源、锁定、影响与回滚；宿主/provider/auth/session/plugin/MCP mutation 需要当前明确授权。
- `references/reference-shelf.manifest.json` 仅服务显式 refresh/verify 的可选只读开发缓存；缺失或未刷新不得阻断普通 build/test/update/projection，也不得自动采纳、安装、执行或影响 runtime projection。
- `D:\CODE\external\` 整根持有 deny-write ACL 硬墙（外层仓基线见 `references/external-readonly-baselines.json`）；写入/构建被拒属预期，解锁仅经 `scripts/lock-external-repos.ps1 -Unlock` 且为用户显式授权动作，AI 会话不得自行改 ACL 或重钉基线。
- 规则/文档不复制运行状态；Git diff、受影响测试和 ignored runtime receipt 是默认证据，不为普通变更新增 evidence/task/ADR。
- 新增功能或 module 必须服务当前明确需求或真实失败，并明确调用方、现有 interface 为何不足、write set、最低充分 proof 与 rollback；需求内必要文件不算额外扩范围，不以未来可能需要增加抽象或治理。准入三问（当前调用方 / 替代或删除了什么 / 最小验证）任一答不上即拒绝，PR 模板同栏。

## C. 最低门禁
- 本地默认 `scripts/quality/run-local-quality-gates.ps1 -Profile auto`，检查 `HEAD` 后编辑（含未跟踪文件）；集成范围显式用 `-DiffBase <revision>`。具体选档以 `scripts/quality/resolve-gate-profile.ps1` 为准；可用 `-TestPath` 追加回归证明，显式 focused 用于已确定范围。
- 多层适用时顺序为 `build -> test -> contract/invariant -> hotspot`，只跑覆盖当前独立失败的最低充分层。
- 文档/规则运行 `git diff --check` 与受影响 verifier/test；source/config/generated seam 运行一次 `build.ps1` 后跑受影响测试，并核对 `skills.ps1` 无生成漂移。
- 只有 runtime、安全、数据、迁移、公开契约、依赖、打包或跨面风险才运行一次 `scripts/quality/run-local-quality-gates.ps1 -Profile full`。本地构建允许未提交生成物；CI 加 `-CheckGenerated` 在测试前只读核对提交的生成物。full 在普通终端/CI 实测 ≈3–5 分钟（分片并行，约 1267 用例）；在 AI 沙箱内因 safe-delete shim 代理每次删除可膨胀到数小时，属环境成本而非代码成本 ⇒ 沙箱内默认走 docs/focused（`-TestPath` 跑受影响文件），full 交 CI。门禁输出 profile/elapsed 作为成本信号，新门禁须声明替代了什么。
- 全局规则文件相等最多证明 `repo_verified/filesystem_projected`；`doctor --strict` 不证明 `host_loaded`，后者必须使用 fresh host probe。
- 证明覆盖当前独立失败后立即停止；不得为了“更全面”重复运行同层门禁或新增旁路审计。

## D. 回滚与收口
- Git baseline=`main`，upstream=`origin/main`；默认按 focused 或风险触发的一次 full gate 收口。远端 ruleset 强制 required checks（`test`，strict）：直推 `main` 会被拒，合入走 推分支 → PR → CI 绿 → merge。
- 失败沿原路径 focused 重验；回滚只撤本次切片，不覆盖无关 import、audit/MCP 或用户资产。
- 收口报告必须含 `Removed:` 行（删除或合并的测试、门禁、文档数）；连续 0 视为只加不减，触发一次减法复核。
- 外置参考仓、宿主投影与 live acceptance 均为显式工作流，不属于普通编码完成条件。
