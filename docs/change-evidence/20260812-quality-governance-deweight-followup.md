# 质量门禁与治理减重 follow-up

## Goal

- 阻止 `-ReuseCurrentReceipt` miss 隐式升级为 fresh full。
- 将 retired governance 检查移出默认 planning contract。
- 让 Lean Delivery pilot 的动态状态只由 manifest 持有。
- 删除 clean CI 中重复且无当前样本的 doctor threshold 调用。
- 复用 full gate 已完成的初始 build，保留连续构建幂等性证明。

## Truth boundary

- 本切片只改变仓库门禁、测试和规划治理行为，不修改宿主、provider、MCP、skill projection 或 live runtime。
- `tasks/skills-manager-vnext-lean-delivery-pilot.json` 仍是 pilot 状态、owner 与样本的唯一动态真源。
- retired Agent Workflow manifest 和 adoption matrix 仍可由 `verify-vnext-planning.ps1 -HistoricalGovernance` 显式验证，不进入默认 closeout。
- full 是否有效只由 `reports/quality-gates/current.json` 的 exact-current immutable receipt 判定，不复制 receipt 状态到 tracked 文档。

## Changes

- reuse miss 以 exit `76` 和 `action=rerun_with_force_fresh` 快速失败；只有显式 `-ForceFresh` 执行 fresh full。
- generated-sync 接受 `-InitialBuildCompleted`，将 full 中的构建次数从三次降为两次，同时比较前置 build 与后续 build 的哈希。
- planning 默认只验证当前 phase truth；retired governance 改为显式历史模式，并删除 PP-000 逐字措辞锁定。
- plan、PRD、roadmap 与产品索引只链接 pilot manifest，不复制当前状态或样本数；已完成 P6 的 `next_milestone` 置空。
- CI full 后不再重复执行无当前 `sync_mcp` 样本的 `check-doctor-json.ps1 -WarnOnly`。
- 质量脚本测试保留 reuse success、reuse miss、explicit fresh 三条进程边界；参数互斥改为入口静态契约，避免一次低价值子进程启动。

## Focused verification

- affected Pester: `62 passed, 0 failed`。
- current planning: `15 done, 0 open, 0 findings`。
- explicit historical governance: `15 done, 0 open, 0 findings`。
- generated sync: two consecutive builds produced the same tracked bundle; no generated drift。
- `git diff --check`: exit `0`。

## Rollback

- 仅回退本 evidence 所列门禁、测试、CI、planning 与产品文档文件。
- 不回退 `reports/`、宿主状态、imports、MCP、provider 或其他并发/用户改动。
