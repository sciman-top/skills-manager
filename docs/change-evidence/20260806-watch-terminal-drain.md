# 守夜终态去活锁与无人值守关机收口

## 变更边界

- 落点：`overrides/custom/watch-interrupted-task/` 的 prompt、状态判定、fleet journal 与 runtime generation；`scripts/hooks/` 的 canonical guard 与 fresh runtime doctor；对应 Pester 回归。
- 目标归宿：shutdown-managed target 在稳定停止时自暂停并请求 supervisor cleanup；supervisor 只删除已验证的 paused target，所有已纳管成员稳定停止后才进入双 tick 关机候选。
- 本切片不执行宿主 automation/hook 投影，不修改 Desktop 数据、automation TOML、session JSONL，不执行 `shutdown.exe`。
- 共享工作树 `D:\CODE\skills-manager` 保持不变；本次验证在隔离 worktree `C:\Users\sciman\.codex\worktrees\watch-safety-repair\skills-manager` 的 `codex/watch-safety-repair` 分支进行。

## 根因与协议收口

旧 scheduled prompt 会在 heartbeat envelope 后再次触发 `$watch-interrupted-task`，使最新输入不再是 heartbeat envelope；supervisor 按 provenance 保护退出，于是旧 automation 周期性重复而没有 reconciliation。canonical target/fleet prompt 现在自包含，scheduled tick 不再调用该 skill。

shutdown-managed 终态采用：

`running/recovering -> stable_stop -> self_paused -> supervisor_deleted`

`needs_input` 与不可恢复失败只保留一次业务通知 receipt；`natural_pause`、`complete` 等稳定停止静默处理。`Get-WatchHeartbeatDisposition.ps1` 使用 `PriorNotifiedReceiptKey` 对相同 `watch-receipt:<sha256>` 确定性去重。recoverable transport failure、活动回合、retry、`peer_busy`、unknown 或不安全外部效果仍保持 ACTIVE。

runtime generation 绑定 prompt digest、hook source/installed hash 与 source commit；arming preflight 在 generation、`/hooks` trust、fresh session probe 或 native automation capability 缺失/漂移时返回 `not_armed` 与 `rollback_required=true`，避免留下永久轮询半成品。

宿主首次 arming preflight 进一步暴露了 Windows EOL 投影漂移：clean-generation 从 Git committed blob 计算，而 target/fleet prompt generator 曾从 CRLF working-tree bytes 计算。同一 clean HEAD 因此会生成不同的 `watch_runtime_generation_id`。prompt generator 与 fleet shutdown disposition 的默认 generation 现统一使用 committed canonical blobs（`Get-WatchRuntimeGenerationId -CommittedOnly`）；新增回归先稳定复现 working tree 为 CRLF、committed blob 为 LF 的失败，再验证 target/fleet generation 与 clean HEAD 完全一致。

fleet journal 保存 generation、已纳管活跃 membership、target identity、stop/notification/cleanup receipt、连续 snapshot 与 shutdown receipt。非活跃历史达到 50 条不单独阻塞；活跃未纳管、不可用 host/source、未知/冲突/活动/重试状态仍 fail-closed。

## 验证记录

以下命令均在上述隔离 worktree 执行：

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
```

结果：`Build success`。

```text
Invoke-Pester -Script tests/Unit/CrossThreadHook.Tests.ps1, tests/Unit/CrossThreadGuardInstall.Tests.ps1, tests/Unit/WatchRuntimeArming.Tests.ps1, tests/Unit/WatchPeerArbitration.Tests.ps1, tests/Unit/WatchInterruptedTask.Tests.ps1, tests/Unit/WatchGuardRuntime.Tests.ps1, tests/Unit/WatchFleetSupervisor.Tests.ps1, tests/Unit/BuildScript.Tests.ps1, tests/Unit/GeneratedSyncScript.Tests.ps1 -PassThru
```

该组合命令在 180 秒外层命令超时前，守夜核心 99 项均逐项显示 passed；因为未取得 Pester 最终退出码，不把该次组合运行单独记为完整通过。随后拆分验证：`BuildScript.Tests.ps1` 为 1 passed、0 failed，`GeneratedSyncScript.Tests.ps1` 为 5 passed、0 failed；generation/EOL 回归由 full gate 中的 `WatchRuntimeArming.Tests.ps1` 7 项覆盖。

`git diff --check` 通过。

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full
```

结果：exit 0；995 unit + 18 E2E（共 1013 项）、generated-sync、skill integrity、reference governance、routing、dependency baseline、config/host/planning/runtime/advisory/doctor contracts 全部通过；summary 为 `Local quality gates passed (full)`，总门禁耗时 `452943ms`。

提交/推送和宿主投影在 full gate 后继续执行；本文件不把 repo-side 验收写成 host-live 验收。

## 运行态边界

现有 supervisor 与仍活跃业务任务的 migration 必须等 repo full gate、hook 安装、`/hooks` exact hash 信任和 fresh session probe 全部通过后进行。每次宿主 mutation 都要用 native receipt 与 fresh metadata 回读验收。真实关机只允许在实际已纳管活跃集合全部稳定停止、连续两个不同 scheduled tick 得到相同非空 snapshot、最终 supervisor delete receipt 存在且 shutdown exit-code receipt 为 0 时执行。
