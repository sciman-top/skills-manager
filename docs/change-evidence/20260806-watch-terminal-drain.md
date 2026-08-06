# 守夜终态去活锁与无人值守关机收口

## 变更边界

- 落点：`overrides/custom/watch-interrupted-task/` 的 prompt、状态判定、fleet journal 与 runtime generation；`scripts/hooks/` 的 canonical guard 与 fresh runtime doctor；对应 Pester 回归。
- 目标归宿：shutdown-managed target 在稳定停止时自暂停并请求 supervisor cleanup；supervisor 只删除已验证的 paused target，所有已纳管成员稳定停止后才进入双 tick 关机候选。
- 本切片不执行宿主 automation/hook 投影，不修改 Desktop 数据、automation TOML、session JSONL，不执行 `shutdown.exe`。
- 共享工作树 `D:\CODE\skills-manager` 保持不变；本次验证在隔离 worktree `C:\Users\sciman\.codex\worktrees\watch-terminal-drain\skills-manager` 的 `codex/watch-terminal-drain` 分支进行。

## 根因与协议收口

旧 scheduled prompt 会在 heartbeat envelope 后再次触发 `$watch-interrupted-task`，使最新输入不再是 heartbeat envelope；supervisor 按 provenance 保护退出，于是旧 automation 周期性重复而没有 reconciliation。canonical target/fleet prompt 现在自包含，scheduled tick 不再调用该 skill。

shutdown-managed 终态采用：

`running/recovering -> stable_stop -> self_paused -> supervisor_deleted`

`needs_input` 与不可恢复失败只保留一次业务通知 receipt；`natural_pause`、`complete` 等稳定停止静默处理。`Get-WatchHeartbeatDisposition.ps1` 使用 `PriorNotifiedReceiptKey` 对相同 `watch-receipt:<sha256>` 确定性去重。recoverable transport failure、活动回合、retry、`peer_busy`、unknown 或不安全外部效果仍保持 ACTIVE。

runtime generation 绑定 prompt digest、hook source/installed hash 与 source commit；arming preflight 在 generation、`/hooks` trust、fresh session probe 或 native automation capability 缺失/漂移时返回 `not_armed` 与 `rollback_required=true`，避免留下永久轮询半成品。

fleet journal 保存 generation、已纳管活跃 membership、target identity、stop/notification/cleanup receipt、连续 snapshot 与 shutdown receipt。非活跃历史达到 50 条不单独阻塞；活跃未纳管、不可用 host/source、未知/冲突/活动/重试状态仍 fail-closed。

## 验证记录

以下命令均在上述隔离 worktree 执行：

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
```

结果：`Build success`。

```text
Invoke-Pester -Path tests/Unit/WatchInterruptedTask.Tests.ps1, tests/Unit/WatchFleetSupervisor.Tests.ps1, tests/Unit/WatchRuntimeArming.Tests.ps1 -PassThru
```

结果：47 passed, 0 failed。

```text
Invoke-Pester -Path tests/Unit/CrossThreadHook.Tests.ps1 -PassThru
```

结果：26 passed, 0 failed。

```text
Invoke-Pester -Path tests/Unit/CrossThreadGuardInstall.Tests.ps1, tests/Unit/WatchGuardRuntime.Tests.ps1 -PassThru
```

结果：11 passed, 0 failed。

`git diff --check` 通过。

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

结果：exit 0；完整 unit/E2E、generated-sync、skill integrity、reference governance、routing、dependency baseline、config/host/planning/runtime/advisory/doctor contracts 全部通过；summary 为 `Local quality gates passed (full)`，总门禁耗时 `390304ms`。

提交/推送和宿主投影在 full gate 后继续执行；本文件不把 repo-side 验收写成 host-live 验收。

## 运行态边界

旧 `automation` / `automation-2` 的迁移必须等 repo full gate、hook 安装、`/hooks` exact hash 信任和 fresh session probe 全部通过后进行。每次宿主 mutation 都要用 native receipt 与 fresh metadata 回读验收。真实关机只允许在实际已纳管活跃集合全部稳定停止、连续两个不同 scheduled tick 得到相同非空 snapshot、最终 supervisor delete receipt 存在且 shutdown exit-code receipt 为 0 时执行。
