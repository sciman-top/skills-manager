# Rule framework contract hardening

**date**: 2026-08-08
**truth boundary**: filesystem projection plus repository verification; fresh host load and live acceptance remain separate
**scope**: global Codex/Claude common contract and `skills-manager` RuleEstate/profile enforcement

## Goal

固化 `global common + host delta + project action > isolated rules` 的协同框架，同时避免根规则持续吸收易过期 Phase、gate、任务计数和 host/live 快照。强化对象是现有 RuleEstate 主链，不建立中央规则真源、后台同步服务、第二套 policy runtime 或 `D:\CODE\external` 根管理器。

## Decisions

- 全局共同段新增两项稳定语义：最薄真实主链优先，以及 stable normative/advisory entrypoint 与 dynamic state 分离。
- 外部研究在足以形成可逆决定时停止；参考组合允许按消费者、替代来源、许可证、风险和维护净收益晋降、退役或删除。
- 项目根只保存 Phase/spec/manifest/evidence 的 fresh-truth 指针，不复制任务计数、gate 或 host/live 快照。
- `RuleEstate` 在当前 2.0 profile 下静态检查 A/C/D parity、B delta 独立、全局 release/预算、项目 `1/A/B/C/D` 和 Claude 首行 wrapper。
- 静态通过只证明 `repo_verified` 范围；不证明规则已被 fresh host 加载、由强制层执行或业务 live acceptance。

## Global rollback basis

- Codex before SHA-256: `11761BAA6E34C2B38C86553A97CB3C7E13D42E506C44FE0463A163CFCFE3A421`
- Claude before SHA-256: `CA0D8EEA011F26FF4CA58E6E79CCC0EC214FB7EAFCB53CC635C2DA73D9F1AEC4`
- Codex after SHA-256: `B36F46C696883156E05C1F514E29B80D9A50B5E0296FA11618BD49AD733170B2`（15,975 bytes / 127 audit lines）。
- Claude after SHA-256: `6ED684F68ED4AD750AE4DF8486A57C1A6F5D4DCD4F16320F5EBB26C9DFEA04F2`（15,579 bytes / 126 audit lines）。
- Codex backup: `C:\Users\sciman\.codex\backups\rules\AGENTS.20260808-1745-v970.md`
- Claude backup: `C:\Users\sciman\.claude\backups\rules\CLAUDE.20260808-1745-v970.md`
- 回滚只恢复上述两份全局文件或本切片明确修改的仓库文件；不得覆盖其他 P6/watch/runtime 工作树变化。

## Verification contract

固定顺序：build -> focused Pester -> RuleEstate live filesystem audit -> planning/reference contracts -> diff check。fresh Codex/Claude session 另行验证，因为当前 turn 不热加载本轮规则且不得重启宿主。

## Verification result

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`：exit 0，生成 `skills.ps1`。
- `Invoke-Pester Core.Tests.ps1, RuleEstate.Tests.ps1, ProductPlanning.Tests.ps1`：235 passed，0 failed；其中 RuleEstate 新增 3 个框架用例，总计 10/10。
- `verify-vnext-planning.ps1`：12 tasks / 11 done / 1 open。
- `verify-reference-governance.ps1`：36 repos / 7 default / 3 patches。
- `verify-lean-ai-delivery-planning.ps1`：11 tasks / 11 done / 0 open。
- fresh `codex debug prompt-input`（Codex CLI 0.146.1）：JSON 可解析，并观察到 global v9.71、project review v9.71、`主链优先`、dynamic-state 分层和项目 fresh-truth 指针。
- Claude Code 2.1.206 的 `--help` 可用；本轮没有启动交互 `/context`/`/memory` 或 provider-backed `claude -p`，因此 Claude `host_loaded=not_run`。
- 真实 workspace estate：9 targets、99 covered、0 gaps；A/C/D aligned、B distinct、global releases aligned、global budgets within profile。唯一 finding 是 `D:\CODE\physicist_chinese_poster_batch_tool\AGENTS.md` 仍复核 9.62；该仓已有 255 项未提交变化，本切片 fail-safe 跳过写入。
- 七个原本干净目标仓只更新 `全局规则复核=9.71` 与日期；逐仓 `git diff --check -- AGENTS.md CLAUDE.md` 和 Claude wrapper 首行检查通过。
- 七仓已分别提交并推送 `origin/main`，最终均为 clean 且 `origin/main...HEAD=0/0`：`ai-content-delivery-studio@a092291`、`classroom-answer-toolkit@d18d9f8`、`ClassroomToolkit@1c27495`、`github-toolkit@af06395`、`k12-question-graph@90296bb`、`qq-codex-bot@d763b274`、`vps-ssh-launcher@c9f2392`。

## Completion boundary

- 全局文件：`filesystem_applied`，Codex fresh CLI=`host_loaded`；当前已运行 App turn 不热加载，Claude host load=`not_run`，live acceptance=`not_run`。
- `skills-manager`：受影响仓库侧验证通过；整棵工作树仍含既有 P6/watch/runtime 改动，不能把本切片写成 full closeout。
- 七个干净目标仓：规则版本投影已静态验证并完成 commit/push；未运行各仓产品 full gate，因为只有规则元数据变化且没有产品代码、依赖或运行态变更。
- `physicist_chinese_poster_batch_tool`：保持未写入，等待其现有工作树先完成归属与收口。

## v9.73 root-minimization compatibility follow-up

After the project root was compressed to the v9.73 contract, three older
verifiers still required verbose historical literals that the new contract
intentionally moved to manifests and lower-frequency documentation. The
AgentWorkflow advisory verifier no longer requires its historical track name
in the root; the PS7 verifier accepts the current concise `runtime 为
PS7-only` contract; reference governance binds the root to the manifest,
refresh entrypoint, no-adoption boundary, owned-root boundary and unknown
license fail-closed guard. Detailed lifecycle tokens remain enforced in the
reference README, tier document and product truth. Focused verification is
230/230 plus all three direct verifiers, preserving enforcement without
re-inflating the root file.

The final concurrent merge introduced the Git-profile seam twice: two
`Get-RuleEstateGitProfileFindings` definitions and two calls in each target
audit. The exact isolated worker reproduced `18/20`, including a false normal
fixture failure and duplicate mismatch findings. The duplicate implementation
and invocation were removed while retaining the stricter branch/ref/tracking
validation. Exact isolated GREEN is `20/20`; build and generated-sync are also
clean.
