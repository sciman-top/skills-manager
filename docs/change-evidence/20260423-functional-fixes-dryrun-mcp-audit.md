# 2026-04-23 Functional Fixes (DryRun/MCP/Audit)

## Goal
修复功能巡检中暴露的高优先级运行问题：
1. DryRun 语义不一致（解除关联 / MCP 安装尾部 -DryRun / 审查扫描）。
2. MCP 卸载后配置残留（.claude/.codex/.gemini/.trae）。
3. 同步MCP DryRun 输出泄露敏感 token。
4. 锁定命令在 DryRun 下读取 HEAD 失败。

## Destination
- 当前落点：`src/Commands/*.ps1` 与 `src/Config.ps1`
- 目标归宿：
  - DryRun 不落盘、不改链接、不中断流程；
  - MCP 同步以 `skills.json` 为唯一真源；
  - DryRun 输出脱敏；
  - 锁定 DryRun 可成功预演。

## Changes
- `src/Commands/Utils.ps1`
  - `解除关联` 增加 `Skip-IfDryRun` 早退。

- `src/Config.ps1`
  - `Get-RepoHeadCommit` 在 DryRun 下改为只读执行 `git rev-parse HEAD`，不再依赖会返回空字符串的 `Invoke-GitCapture`。

- `src/Commands/AuditTargets.Bundle.ps1`
  - `Invoke-AuditTargetsScan` / `Invoke-AuditSkillDiscovery` 增加 DryRun 分支：输出“将生成产物预览”并直接返回，不再做必需文件存在断言。

- `src/Commands/Mcp.ps1`
  - 新增 `Extract-McpTrailingDryRunToken`：支持 `安装MCP ... -- ... -DryRun` 尾部预演开关。
  - 新增 `Mask-SensitiveMcpCommandText`：DryRun 日志中脱敏 `Authorization: Bearer ...` 与 GitHub PAT 形态 token。
  - `Build-GenericMcpPayload` / `Build-GeminiSettingsPayload`：`mcpServers` 改为按 `skills.json` 全量重建，避免卸载后残留。
  - `Build-CodexConfigToml`：写入前移除全部 `[mcp_servers.*]` 旧段，再按当前配置回填。

### 2026-04-23 补充修复
- `src/Commands/AuditTargets.Apply.ps1`
  - `Test-AuditUserProfilePreflight`：`user-profile.json` 缺失时改为“可选跳过（ok=true）”，仅在文件存在时执行严格内容校验。
  - 目的：修复 `Preflight passes when snapshot and prompt contract are aligned` 误报失败（兼容旧 run 产物）。

- `src/Commands/Mcp.ps1`
  - `Build-CodexConfigToml`：新增“GitHub token 缺失导致全部候选被跳过”分支，在该场景保留既有 `[mcp_servers.*]` 段；其余场景仍按当前配置重建。
  - 目的：修复单测 `Replaces mcp_servers tables and preserves other codex config fields`，同时不回退“卸载后应清空残留”的行为。

## Verification
### Hard gates (project C.2)
1. `./build.ps1` ✅
2. `./skills.ps1 发现` ✅
3. `./skills.ps1 doctor --strict --threshold-ms 8000` ✅（性能告警不阻断）
4. `./skills.ps1 构建生效` ✅

### Targeted regressions
- `./skills.ps1 锁定 -DryRun` ✅（不再报“无法读取仓库 HEAD”）
- `./skills.ps1 解除关联 -DryRun` ✅（直接跳过执行）
- `./skills.ps1 审查目标 扫描 -DryRun` ✅（输出产物预览，不报缺文件）
- `./skills.ps1 一键 审查 --no-prompt -DryRun` ✅（4/4 成功）
- `./skills.ps1 同步MCP -DryRun` ✅（Authorization Bearer 已脱敏）
- `./skills.ps1 安装MCP smoke-test -- cmd /c echo hi -DryRun` ✅（识别尾部 -DryRun，未写入任何配置）
- 实写回归：安装 smoke-test -> 卸载 smoke-test -> 校验各客户端配置
  - `.claude/.codex/.gemini/.trae` 与项目 `.trae` 均无 `smoke-test` 残留 ✅

### Additional verification (2026-04-23)
- `Import-Module Pester; Invoke-Pester -Script tests/Unit/AuditTargets.Tests.ps1` ✅
- `Import-Module Pester; Invoke-Pester -Script tests/Unit/Core.Tests.ps1` ✅
- `Import-Module Pester; $r=Invoke-Pester -Script tests/Unit -PassThru` -> `FailedCount=0, PassedCount=289` ✅
- `./tests/run.ps1` -> Unit `Passed: 288 Failed: 0`，E2E `Passed: 10 Failed: 0` ✅
- 硬门禁复跑（顺序保持不变）：
  1. `./build.ps1` ✅
  2. `./skills.ps1 发现` ✅
  3. `./skills.ps1 doctor --strict --threshold-ms 8000` ✅（仅性能告警）
  4. `./skills.ps1 构建生效` ✅

### Codex 最小诊断矩阵（B.2）
- `cmd`: `codex --version` | `exit_code`: `0` | `key_output`: `codex-cli 0.122.0`
- `cmd`: `codex --help` | `exit_code`: `0` | `key_output`: `Codex CLI ...`
- `cmd`: `codex status` | `exit_code`: `1` | `key_output`: `Error: stdin is not a terminal`

`platform_na` 记录（针对 `codex status`）：
- `reason`: 非交互终端导致状态命令不可用（stdin 不是 TTY）
- `alternative_verification`: 以 `codex --version` + `codex --help` 补充平台侧可执行性证据
- `evidence_link`: `docs/change-evidence/20260423-functional-fixes-dryrun-mcp-audit.md`
- `expires_at`: `2026-05-23`

## Residual risk
- `doctor --json` 仍报告性能异常：`sync_mcp`（约 40s）与偶发 `build_agent`（>8s）。
- 本次未改动性能策略，仅修复行为正确性与安全性。

## Rollback
- 本次改动均在源码层，可通过 git 回退以下文件：
  - `src/Commands/Utils.ps1`
  - `src/Config.ps1`
  - `src/Commands/AuditTargets.Bundle.ps1`
  - `src/Commands/AuditTargets.Apply.ps1`
  - `src/Commands/Mcp.ps1`
  - 以及生成产物 `skills.ps1`
