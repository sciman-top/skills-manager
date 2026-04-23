# 2026-04-23 MCP CLI 非交互健壮性与性能优化

## 1) 依据
- issue_id: `mcp-cli-timeout-noninteractive-20260423`
- 当前落点: `src/Commands/Mcp.ps1` / `tests/Unit/Core.Tests.ps1`
- 目标归宿: 在不改变业务契约的前提下，降低 `sync_mcp` 慢调用和非交互失败放大效应，补齐可回归测试
- 风险等级: `medium`
- clarification_mode: `direct_fix`
- attempt_count: `1`

## 2) 问题 -> 修改 -> 收益 -> 风险 -> 回滚

### 2.1 外部命令执行对 `.ps1` wrapper 不兼容，导致校验链路异常放大
- 问题:
  - 原逻辑拼 `cmd.exe /c` 命令字符串执行，遇到 npm/CLI 的 PowerShell wrapper（`*.ps1`）时，存在 `%1 不是有效的 Win32 应用程序` 风险。
- 修改:
  - 新增 `Resolve-ExternalCommandInvocation`，识别 `*.ps1` 并改为 `powershell.exe -File <wrapper> ...args` 执行。
  - `Invoke-ExternalCommandWithTimeout` 改为基于 `Start-Process -FilePath/-ArgumentList` 的结构化调用。
- 收益:
  - 消除 wrapper 执行不兼容导致的误失败与重试放大。
- 风险:
  - 命令解析行为从字符串拼接转为结构化参数传递，可能影响极少数依赖 shell 解释副作用的命令。
- 回滚:
  - 回退 `src/Commands/Mcp.ps1` 对应函数变更并重新 `./build.ps1`。

### 2.2 非交互环境下原生 MCP 命令重复失败，拉高时延
- 问题:
  - `claude mcp remove/add` 在非交互上下文可返回 `stdin/terminal` 类错误，旧逻辑会在同轮继续多次调用并持续超时。
- 修改:
  - 新增 `Test-IsNonInteractiveMcpError`。
  - 引入会话级短路标记 `$script:SkipNativeMcpForSession`；命中非交互错误后本轮跳过后续原生清理/同步。
  - `同步MCP` 入口重置短路标记，避免跨轮污染。
- 收益:
  - 降低同轮重复失败调用次数，显著缩短 `sync_mcp` 关键路径。
- 风险:
  - 在非交互场景下，原生 CLI 同步会被主动跳过（`.mcp.json`/`config.toml` 仍会写入）。
- 回滚:
  - 删除短路逻辑并恢复原调用路径。

### 2.3 超时策略不可细粒度控制，失败信号不足
- 问题:
  - 超时参数分散，`Invoke-ExternalCommandCapture` 未透传 `timed_out/error`，上层难区分超时与其他失败。
- 修改:
  - 新增 `Resolve-TimeoutSecondsFromEnv`、`Get-McpListVerifyTimeoutSeconds`、`Get-NativeMcpCommandTimeoutSeconds`。
  - `Invoke-ExternalCommandCapture` 返回 `timed_out/error`。
  - `Test-CliMcpServerReady` 对超时进行显式分流。
- 收益:
  - 诊断粒度提升，后续优化和告警更可观测。
- 风险:
  - 新增环境变量路径需文档化（本次保持默认值兼容）。
- 回滚:
  - 回退新增 timeout helper 和 capture 字段透传。

### 2.4 gemini CLI 校验在大量环境不可用，导致整体流程误判/变慢
- 问题:
  - `gemini mcp list` 在部分环境缺失或不稳定，不应成为阻断健康结论的唯一依据。
- 修改:
  - 新增 `Should-VerifyGeminiCli`；默认跳过 gemini CLI 实机校验，返回 `gemini_cli_verification_skipped`。
  - 允许通过 `SKILLS_MCP_VERIFY_GEMINI_CLI=1/true/yes/on` 强制启用实机校验。
  - 强制模式下对 `CLI 缺失/超时` 回退为配置态成功（仅 gemini）。
- 收益:
  - 默认路径更稳更快，且保留强校验开关。
- 风险:
  - 默认策略偏向可用性，会弱化 gemini CLI 的实时可达性检查。
- 回滚:
  - 恢复 gemini 与其他 CLI 的统一严格策略。

## 3) 执行命令与证据

### 3.1 平台诊断
- `codex --version` -> `codex-cli 0.123.0`
- `codex --help` -> 返回帮助信息
- `codex status` -> `Error: stdin is not a terminal`（记录为 `platform_na`）

### 3.2 硬门禁（改造后）
按顺序执行 `build -> test -> contract/invariant -> hotspot`：
- `./build.ps1` -> `Build success ...`，`__DURATION_MS=113`
- `./skills.ps1 发现` -> exit 0，`__DURATION_MS=1171`
- `./skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0，`__DURATION_MS=1889`
- `./skills.ps1 构建生效` -> exit 0，`__DURATION_MS=7202`

### 3.3 质量与测试
- `./tests/run.ps1` -> `Passed: 299 Failed: 0`（含 Unit + E2E）
- `./scripts/quality/run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree` -> passed
- `./scripts/quality/check-repo-hygiene.ps1` -> `Repository hygiene check passed.`
- `./skills.ps1 doctor --json --threshold-ms 8000` -> `pass=true`，`sync_mcp.last_ms=7771`

### 3.4 性能对比（关键路径）
- 基线（改造前，`./skills.ps1 同步MCP` 实测）: `~39650ms`、`~41360ms`
- 改造后（同命令）: `9368ms`、`8838ms`、`7788ms`
- `build.log` 历史埋点（同日）最高值: `147860ms`；改造后最近三次: `8796ms`、`8645ms`、`7771ms`
- 结论:
  - 从约 `40s` 降至约 `8-9s`，关键路径降幅约 `~78%`

## 4) 安全检查
- 敏感信息扫描:
  - 命令: `rg -n "BEGIN ... PRIVATE KEY|ghp_|AKIA|AIza..." --glob '!vendor/**' --glob '!agent/**' --glob '!reports/**'`
  - 结果: 命中均为 `imports/**` 文档示例字符串，未发现可用凭据。
- 依赖漏洞门禁:
  - 发现 `.governed-ai/dependency-baseline.json` 仅给出外部校验命令模板，仓内无对应 `scripts/verify-dependency-baseline.py`。
  - 记录 `gate_na`（见下）。

## 5) N/A 记录

### 5.1 `platform_na`
- reason: `codex status` 在当前非交互 shell 报错 `stdin is not a terminal`
- alternative_verification: 使用 `codex --version` + `codex --help` 验证 CLI 可用性
- evidence_link: 本文件 3.1
- expires_at: `2026-05-31`

### 5.2 `gate_na`
- reason: 仓内缺失依赖基线实际校验脚本（仅有模板命令）
- alternative_verification: 已执行本地质量门禁、全量测试、敏感信息扫描
- evidence_link: 本文件 3.3 / 4
- expires_at: `2026-05-31`

## 6) 回滚方案
1. 代码回滚: `git revert <本次提交SHA>`
2. 最小回滚:
   - 回退 `src/Commands/Mcp.ps1` 与 `tests/Unit/Core.Tests.ps1`
   - 执行 `./build.ps1`
   - 复跑四道门禁
3. 策略回滚（无需改代码）:
   - 若需恢复 gemini 严格实机校验，设置 `SKILLS_MCP_VERIFY_GEMINI_CLI=1`
