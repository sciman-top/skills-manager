# 2026-07-07 导入更新自动恢复修复

- Rule IDs: `R1`, `R3`, `R4`, `R6`, `R8`, `E4`, `E6`
- Risk: `medium`
- Current landing: `skills-manager` 的导入更新链路会在脏缓存仓、无共同祖先历史、或 `git clean` 权限拒绝时部分失败
- Target destination: `更新` 与 `weekly-auto-update.ps1` 能自动修复上述缓存仓状态，并完成一次真实更新闭环

## Root Cause

1. `src/Git.ps1:456` 的 `Update-CurrentBranchFromUpstream($false)` 在本地快进失败后仍会落回 merge/pull 语义，导致缓存仓在分叉历史上进入冲突态。
2. `src/Git.ps1:713` / `src/Git.ps1:750` 之前不会在 `reset --hard` 前显式中止 `MERGE_HEAD`、rebase、cherry-pick、revert 等未完成操作，`mcp-cli` 一类缓存仓会带着 merge in progress 继续更新。
3. `src/Config.ps1:43`、`src/Config.ps1:54`、`src/Config.ps1:74` 之前把 merge in progress 的 imports 误判为“需要保留的本地改动”，导致自动清理被跳过。
4. `src/Git.ps1` 之前只从 git 错误输出末尾摘要少量行，`git clean -fd` 的大批量 `Permission denied` 路径无法被完整修复。
5. `skills.json:643-644` 中 `d3-viz` 的 skill 路径与当前导入仓结构漂移，更新后会找不到有效技能目录。

## Changes

- `src/Git.ps1`
  - 新增无共同祖先检测，遇到 `unrelated histories` 时直接 `reset --hard @{u}`。
  - `AllowNetworkFetch=$false` 时仅尝试本地 `merge --ff-only @{u}`；失败则直接强制对齐 upstream，不再回退 `git pull`。
  - 在 `Git-HardResetClean` 前自动执行 `merge/rebase/cherry-pick/revert --abort` 恢复未完成 Git 操作。
  - 聚合全部 `failed to remove` / `Permission denied` 行，允许一次修复多条锁定目录后重试 `git clean`。
- `src/Config.ps1`
  - 新增 in-progress Git 状态检测。
  - `Get-DirtyUpdateTargets` 与 `Get-DirtyManualImportTargets` 不再把 merge in progress 缓存仓当作“用户本地改动”保留。
- `skills.json`
  - 将 `d3-viz` 的路径修正为 `downloaded-skills\\design-frontend\\d3-viz`。
- `tests/Unit/Core.Tests.ps1`
  - 覆盖 `Update-CurrentBranchFromUpstream` 的 ff-only 失败与 unrelated histories 回收行为。
- `tests/Unit/GitLockRecovery.Tests.ps1`
  - 覆盖 `Git-HardResetClean` 在 `MERGE_HEAD` 存在时先 `merge --abort` 再 reset/clean。
- `tests/Unit/ConfigUpdate.Tests.ps1`
  - 覆盖 merge in progress imports 不再被误判为需保留的脏缓存。

## Verification

- 真实更新链路：
  - `./skills.ps1 更新`
  - 结果：成功；`imports/mcp-cli` 不再报 `git pull` 冲突，分叉仓被自动 `reset --hard @{u}` 对齐后完成更新。
- 本仓硬门禁：
  - `./build.ps1`
  - `./skills.ps1 发现`
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
  - `./skills.ps1 构建生效`
  - 结果：全部通过。`doctor --strict` 仅报告非阻断性能告警：`build_agent avg=9612ms`，当前不会导致失败。
- 回归测试：
  - `Invoke-Pester -Path .\tests\Unit\Core.Tests.ps1`
  - `Invoke-Pester -Path .\tests\Unit\GitLockRecovery.Tests.ps1`
  - `Invoke-Pester -Path .\tests\Unit\ConfigUpdate.Tests.ps1`
  - 结果：通过。
- 自动任务闭环：
  - `./scripts/weekly-auto-update.ps1`
  - 结果：成功执行 `更新` 与 `同步MCP`；最终输出 `更新完成：所有技能源已是最新版本。`
- 现场状态复核：
  - `imports/mcp-cli` -> `git status --short --branch` 返回 `## main...origin/main`
  - `MERGE_HEAD` / `rebase-*` / `CHERRY_PICK_HEAD` / `REVERT_HEAD` 全部不存在

## Residual Notes

- 本次验证中仍可见部分 `git sparse-checkout` 的目录删除 warning，但不会再让更新失败；当前表现为可恢复告警而非阻断错误。
- 外层仓 `imports/*` 存在一批上游更新后的已跟踪差异；它们属于真实缓存升级结果，不等同于本次代码修复本身，后续是否提交应单独按变更范围判断。

## Rollback

- 若需撤回本次修复，可恢复以下受版本管理文件到 `HEAD`：
  - `skills.json`
  - `skills.ps1`
  - `src/Git.ps1`
  - `src/Config.ps1`
  - `tests/Unit/Core.Tests.ps1`
  - `tests/Unit/GitLockRecovery.Tests.ps1`
  - `tests/Unit/ConfigUpdate.Tests.ps1`
- 撤回后重新运行：
  - `./build.ps1`
  - `./skills.ps1 发现`
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
  - `./skills.ps1 构建生效`
