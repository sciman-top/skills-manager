# 常驻 Git 收口授权

**scope**: GlobalUser Codex/Claude common contract + skills-manager project action
**truth boundary**: filesystem projected; fresh host loading and other repositories' review refresh remain separate

## Goal

- 将反复出现的任务末尾 commit/merge/push/worktree cleanup 请求提升为精简的常驻授权。
- 保持 `common + platform delta + project action`：全局定义 WHAT 与阻断条件，平台 B 保持各自加载/强制差异，项目只补仓库真实门禁、基线与 upstream/PR 策略。

## Basis and decision

- 2026-08-03 当前 Codex manual 的 worktree 文档说明 App managed worktree 默认 detached HEAD，提交、建分支、推送/PR 与自动磁盘清理不是同一生命周期；采纳“显式常驻授权 + fail-closed cleanup”，不假定宿主有自动 merge 开关。
- `rule-estate-audit` 动态发现 `D:\CODE` 下 9 个直接 Git 目标，审查结果为 `covered=99`、`gap=0`、Codex/Claude A/C/D common aligned；因此不向九仓复制通用流程。
- 其余 8 个项目只更新 `全局规则复核` 为 9.62，不复制 common 正文；`github-toolkit`、`physicist_chinese_poster_batch_tool`、`vps-ssh-launcher` 已有的项目规则优化属于本次同一规则治理范围，经 fresh estate audit 后原样保留并随各自 `AGENTS.md` 一并收口，不纳入其他文件。

## Changes

- GlobalUser v9.62：A.2 增加一条常驻 Git 收口授权，R4 接受当前或常驻授权，C.2 要求项目只补 Git 差异。
- Codex 与 Claude 的 A/C/D 保持相同；B 章不加入 Git 共性正文，继续只承接平台差异。
- skills-manager 项目 action 明确 `full -> commit -> main/origin-main -> merged-clean cleanup` 与 fail-closed 条件。
- 其余项目沿用各自既有门禁、证据与回滚 action，只刷新兼容复核标记。

## Verification and rollback

- canonical gate：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full`。
- 补充静态核验：全局 A/C/D hash 对齐、版本/体量、项目 wrapper、fresh `rule-estate-audit`；host loading 不由静态文件写入证明。
- 其余 8 仓仅改规则复核元数据，产品 gate 为 `gate_na`：`reason=rule metadata only`，`alternative_verification=fresh estate audit + exact staged diff + wrapper/static checks`，`evidence_link=本文件`，`expires_at=下次项目规则正文或可执行文件变化`，`recovery_condition=发生该类变化时恢复项目真实门禁`。
- 回滚只撤销本切片对两个 GlobalUser 文件、本仓 `AGENTS.md` 和本证据文件的改动；不得触碰其他仓既有 dirty paths。
