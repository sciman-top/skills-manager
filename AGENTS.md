# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.89
**最后更新**: 2026-10-18

## 1. 产品边界与入口
- `skills.ps1` 是唯一 CLI 入口；`skills.json` 是 vendor、import、mapping、target、MCP 与 skill projection 的运行真源。
- 本仓只同步技能、MCP 与规则，不接管模型、provider、auth、会话、权限或插件缓存。
- 项目根 `AGENTS.md` 是各宿主共同的项目规则源；`CLAUDE.md`、`GEMINI.md` 与 `.agents/rules/00-project.md` 只做引用。
- 冻结面（仅真实故障修复，解冻须用户明确授权）见 [PRD §3.1](docs/product/skills-manager-vnext-prd.md)。新增能力前先读该节。
- 真值层级 `repo_verified -> filesystem_projected -> host_loaded -> live_accepted`，低层证据不得外推。

## 2. 构建与生成物
- `build.ps1` 从 `src/` 生成根 `skills.ps1` 与 `skills.lib/`，并从 `rules/global/` 生成五份全局宿主规则。`-Check` 只读核对漂移。禁止手改生成物。
- `vendor/`、`imports/`、`agent/` 与 ignored `reports/` 是物化或运行目录：先改 source、config 或 override，再构建。
- `skills.ps1 构建生效` 会写宿主目录，属于外部投影动作；仓库内开发验证只运行 `build.ps1` 与测试。
- runtime 为 PowerShell 7-only，Windows 优先。

## 3. 执行边界
- 默认由一个主执行者串行完成。子代理委派已获用户常驻授权，但每次委派须限定独立切片、互斥写集、最低证明与停止条件，不并行写同一文件。
- 日常合同为 `Goal / Exact write set / Minimum proof / Stop`。覆盖当前明确需求或真实失败，验收满足即停止。
- 先用 `git diff` 分界用户或并发改动；不回退、不重排、不混入本次提交，不批量改写第三方 import。
- 新增文件、模块、门禁或文档前，须说明当前调用方、替代或删除了什么、最小证明。任一答不上即不做。
- 宿主配置、用户目录、MCP、远端等外部写入须有当前授权、预演和回滚入口。
- 请求指代不清时，先向用户确认目标，不以"最新文件"等启发式自选。
- 外置参考仓（`D:\CODE\external\`）的解锁、锁定与 ACL 流程见 [外置参考仓 Runbook](docs/EXTERNAL_REFERENCE_REPO_TIERS.md)；AI 会话不得自行改 ACL 或重钉基线。
- 元治理测试（ResolveGateProfile、QualityGateAuto、CiWorkflow、TestRunner、BuildScript）冻结：仅真实故障时维护。

## 4. 最低门禁
- 本地默认 `scripts/quality/run-local-quality-gates.ps1 -Profile auto`，选档以 `scripts/quality/resolve-gate-profile.ps1` 为准；集成范围加 `-DiffBase <revision>`。
- 文档或规则：`git diff --check` 加受影响 verifier。
- 源码或配置：`build.ps1` 后跑受影响测试，并核对生成物无漂移。
- 只有 runtime、安全、数据、迁移、公开契约、依赖或打包风险，才在输入冻结后运行一次 `-Profile full`（约 3–5 分钟）。
- 证明覆盖当前独立失败后即停止；不为"更全面"重复同层门禁。
- CI 以 `-CheckGenerated` 只读核对已提交的生成物。
- 生成物 hook（[guard-generated.ps1](.claude/hooks/guard-generated.ps1)、[pre-commit](.githooks/pre-commit)）只是辅助；Bash 写入不受 hook 覆盖，最终裁决是 CI。
- 全局规则文件相等只证明 `filesystem_projected`；`host_loaded` 需要 fresh host probe。

## 5. 收口
- 基线分支 `main`，upstream `origin/main`。远端 ruleset 要求 PR 与 `test` 检查（strict），不要求额外批准人数。合入走：推分支 → PR → CI 绿 → merge。禁止 force push。
- PR 模板要求新增面时填写章程段；CI 只校验占位符，语义由人负责。
- 收口报告写明：验证命令与结果、未验证项，以及 `Removed:` 行（常规修复写 `N/A`）。
- 两台电脑同步见 [双机开发与规则同步 Runbook](docs/runbooks/dual-machine-rule-sync.md)。`fetch` 不会把远端提交整合进工作树。
- 失败沿原路径 focused 重验；回滚只撤本次切片，不覆盖无关 import、audit/MCP 或用户资产。
