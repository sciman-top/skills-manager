## Goal
执行“全仓深度审查与保守加固计划”的已落地批次，优先清除已知失败和高风险鲁棒性缺口，不扩张功能边界。

## Rule IDs
- `R2` 小步闭环
- `R3` 根因优先
- `R6` build -> test -> contract/invariant -> hotspot
- `R8` 依据 -> 命令 -> 证据 -> 回滚
- `E6` 配置与运行态结构兼容验证

## Risk
- 中风险
- 原因：修改了配置读取、git worktree 锁恢复、MCP 输入校验与配置投影路径，但保持 CLI 命令与现有 schema 兼容。

## Basis
- `README.md` / `README.en.md` 与 `tests/Unit/MenuStructure.Tests.ps1` 存在契约漂移，导致既有基线有 1 个单测失败。
- `skills.json` / `skills.lock.json` 使用 `Set-ContentUtf8` 写入，但读取链仍混用原生 `Get-Content -Raw`，存在编码漂移风险。
- `Repair-StaleGitLockInRepo` 仅支持普通仓库 `.git\index.lock`，不支持 git worktree `.git` 文件指向的真实 `gitdir`。
- MCP 远程输入缺少对 URL scheme、header 换行和 bearer token 环境变量名的严格校验。
- 构建缓存占位符与 MCP 投影预期读取路径仍残留原生 `Get-Content -Raw`。

## Changes
- 修复菜单文档契约漂移：
  - `README.md`
  - `README.en.md`
- 统一配置/锁文件 UTF-8 读取：
  - `src/Config.ps1`
  - 新增回归测试 `tests/Unit/ConfigUpdate.Tests.ps1`
- 支持 git worktree 场景下的残留 `index.lock` 自动恢复：
  - `src/Git.ps1`
  - 新增回归测试 `tests/Unit/Core.Tests.ps1`
- 收紧 MCP 远程输入边界：
  - 仅允许绝对 `http/https` URL
  - 拒绝非法 bearer token 环境变量名
  - 拒绝 header/env key/value 中的换行
  - `src/Commands/Mcp.ps1`
  - 新增回归测试 `tests/Unit/Core.Tests.ps1`
- 收口残留原生 Raw 读取路径：
  - `src/Core.ps1`
  - `src/Commands/Mcp.ps1`
  - 新增回归测试 `tests/Unit/BuildCache.Tests.ps1`
  - 新增回归测试 `tests/Unit/Core.Tests.ps1`
- 调整 `manual` import 失效分流语义，与现有失效 mapping 处理保持一致：
  - 根因：`imports/` 中部分手动导入目录在仓库内是 `gitlink` 占位（mode `160000`），当前 worktree 未落地真实技能内容，`构建生效` 之前会把这类 manual 源缺失升级为整次构建失败。
  - 修复：`src/Commands/Install.ps1` 中 `构建Agent` 遇到 `source_valid = $false` 时不再抛失败，而是记录到 `invalidMappings`，与 vendor 失效源统一按“未参与同步 + 提示清理 skills.json”处理。
  - 新增回归测试：`tests/Unit/BuildCache.Tests.ps1`

## Commands
- `.\build.ps1`
- `Import-Module Pester | Out-Null; Invoke-Pester -Script tests\Unit\ConfigUpdate.Tests.ps1 -PassThru -Show Fails`
- `Import-Module Pester | Out-Null; Invoke-Pester -Script tests\Unit\Core.Tests.ps1 -PassThru -Show Fails`
- `Import-Module Pester | Out-Null; Invoke-Pester -Script tests\Unit\BuildCache.Tests.ps1 -PassThru -Show Fails`
- `.\tests\run.ps1`
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
- `.\skills.ps1 构建生效`

## Evidence
- `MenuStructure` 基线已恢复：此前唯一已知失败的文档契约漂移已修复。
- `ConfigUpdate.Tests.ps1` 当前结果：`39 passed, 0 failed`
- `Core.Tests.ps1` 当前结果：`167 passed, 0 failed`
- `BuildCache.Tests.ps1` 当前结果：`25 passed, 0 failed`
- 关键源码扫描结果：`src/` 中已无残留 `Get-Content ... -Raw` 读取路径。
- `tests/run.ps1` 当前结果：`389` 个单元测试通过、`0` 失败；`11` 个 E2E 通过、`0` 失败。
- `./skills.ps1 doctor --strict --threshold-ms 8000` 当前通过。
- `构建生效` 根因已确认为仓库内 manual import gitlink 占位未落地，不是本次硬化引入的新失败。

## Rollback
- 文档回滚：还原 `README.md` 与 `README.en.md` 本次改动。
- 源码回滚：还原 `src/Config.ps1`、`src/Git.ps1`、`src/Core.ps1`、`src/Commands/Mcp.ps1`、`src/Commands/Install.ps1`。
- 测试回滚：还原本次新增回归测试文件片段。
- 生成脚本回滚：源码回滚后重新执行 `.\build.ps1` 生成匹配的 `skills.ps1`。
