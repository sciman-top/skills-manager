# 2026-04-20 Build Assembly And Sync Guard

- 规则 ID：R1 / R2 / R6 / R8
- 风险等级：Low
- 当前落点：`build.ps1`、`tests/check-generated-sync.ps1`
- 目标归宿：修正构建拼接与生成一致性校验中的确定性边界错误，不改变 CLI 命令、配置语义、数据格式和同步行为

## 依据

- 证据 1：`build.ps1` 将数组 `$Content` 直接传给 `[System.Text.Encoding]::GetBytes()`，PowerShell 会把数组隐式转换为带空格的字符串。
- 证据 2：最小回归测试复现当前输出为 `chunk-0 \r\n chunk-1 ...`，而不是精确的 `chunk-0\r\nchunk-1 ...`。
- 证据 3：`tests/check-generated-sync.ps1` 在 Git 工作树中误判“未检测到 Git 工作树”，因为 `git rev-parse` 经过管道后 `$LASTEXITCODE` 丢失。
- 证据 4：当前脚本只能用 `HEAD` 洁净状态判断同步，开发中已重新生成但尚未提交时也会报“漂移”，缺少显式的开发态放行模式。

## 变更

- `build.ps1`
  - 显式用 `-join ""` 拼接源码片段后再编码，避免隐式数组字符串化插入空格。
- `tests/check-generated-sync.ps1`
  - 在进入管道前保存 `git rev-parse` 的退出码，再据此判断是否处于 Git 工作树。
  - 新增 `-AllowDirtyWorktree` 显式开关：默认仍以 `HEAD` 为基准严格校验；开发态开启后，允许 `skills.ps1` 相对 `HEAD` dirty，但仍先执行 `build.ps1` 并校验本次构建是否刷新了生成产物。
- `tests/Unit/BuildScript.Tests.ps1`
  - 新增构建回归测试，覆盖“无尾换行源文件拼接不得注入空格”。
- `tests/Unit/GeneratedSyncScript.Tests.ps1`
  - 新增脚本回归测试，覆盖“Git 工作树不应被误判为 no-repo”。
  - 新增显式开发态测试，覆盖“dirty worktree 下可放行但默认严格模式仍失败”。
- `.github/workflows/ci.yml`
  - 将 CI 同步校验改为 `.\tests\check-generated-sync.ps1 -StrictNoGit`，确保非 Git 工作树场景在 CI 中显式失败而非静默放过。
- `skills.ps1`
  - 通过 `./build.ps1` 重新生成；变更仅为文件边界处多余空格消失后的生成结果更新。

## 执行命令与关键证据

- `codex --version`
  - `codex-cli 0.121.0`
- `codex --help`
  - 正常输出命令帮助
- `codex status`
  - `platform_na`
  - reason：CLI 在非交互 stdin 下返回 `stdin is not a terminal`
  - alternative_verification：改用 `codex --version`、`codex --help` 与活动规则文件读取确认环境
  - evidence_link：本文件
  - expires_at：`2026-05-20`

- `Import-Module Pester | Out-Null; Invoke-Pester -Script tests/Unit/BuildScript.Tests.ps1`
  - 红灯阶段：失败并显示实际输出包含额外空格
  - 绿灯阶段：`Passed: 1 Failed: 0`

- `Import-Module Pester | Out-Null; Invoke-Pester -Script tests/Unit/GeneratedSyncScript.Tests.ps1`
  - 红灯阶段：`-AllowDirtyWorktree` 用例失败并抛出“检测到生成产物漂移”
  - 绿灯阶段：`Passed: 3 Failed: 0`

- 固定门禁顺序
  - `./build.ps1`
    - `Build success: ...\\skills.ps1`
  - `./skills.ps1 发现`
    - 正常列出 132 项技能
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
    - `Your system is ready for skills-manager.`
  - `./skills.ps1 构建生效`
    - 构建完成 `agent/ (共 91 项技能)`，5 个 target 链接成功

- 额外验证
  - `Get-Content .github/workflows/ci.yml`
    - `Verify generated script sync` 步骤已显式传入 `-StrictNoGit`
  - `./tests/run.ps1`
    - Unit：`Passed: 227 Failed: 0`
    - E2E：`Passed: 9 Failed: 0`
  - `./tests/check-generated-sync.ps1 -StrictNoGit`
    - 返回非零，原因是当前工作树存在本次未提交变更，脚本按设计将 `skills.ps1` dirty 视为“生成产物漂移”
    - alternative_verification：两条新增回归测试均通过；`git diff --unified=0 -- skills.ps1` 仅显示生成文件边界空白调整
  - `./tests/check-generated-sync.ps1 -AllowDirtyWorktree`
    - `Build success: ...\\skills.ps1`
    - `生成产物与当前 src 一致；skills.ps1 相对 HEAD 仍有未提交变更（开发态已放行）。`

## 回滚

1. 还原 `build.ps1`
2. 还原 `tests/check-generated-sync.ps1`
3. 删除 `tests/Unit/BuildScript.Tests.ps1`
4. 删除 `tests/Unit/GeneratedSyncScript.Tests.ps1`
5. 重新执行 `./build.ps1` 回退生成产物 `skills.ps1`
6. 如需回退开发态放行能力，仅还原 `tests/check-generated-sync.ps1` 中 `-AllowDirtyWorktree` 参数与分支逻辑即可，默认严格模式会自动恢复
