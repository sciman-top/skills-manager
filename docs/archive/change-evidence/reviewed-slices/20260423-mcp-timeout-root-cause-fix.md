# 2026-04-23 MCP startup timeout 根治修复

## 1) 依据
- issue_id: `mcp-startup-timeout-context7-microsoft-learn-20260423`
- 触发现象：
  - `MCP client for context7 timed out after 30 seconds`
  - `MCP client for microsoft-learn timed out after 30 seconds`
  - `MCP startup incomplete (failed: context7, microsoft-learn)`
- 根因判定：
  1. `skills.ps1 同步MCP` 会重写 `~/.codex/config.toml` 的 `[mcp_servers.*]` 段。
  2. 旧逻辑未透传 `startup_timeout_sec`，导致手工在 `config.toml` 添加的超时配置会被下一次同步覆盖，进而反复回到默认 30 秒。

## 2) 变更
- `skills.json`
  - 为 `context7` 增加 `"startup_timeout_sec": 120`
  - 为 `microsoft-learn` 增加 `"startup_timeout_sec": 120`
- `src/Commands/Mcp.ps1`
  - 新增 `Get-CodexMcpStartupTimeoutSec`（校验并读取可选超时字段）
  - 新增 `Convert-McpServersToCodexConfigMap`（Codex 专用映射，透传 `startup_timeout_sec`）
  - `Build-CodexConfigToml` 改用 `Convert-McpServersToCodexConfigMap`
- `tests/Unit/Core.Tests.ps1`
  - 新增单测：`Writes startup_timeout_sec for codex mcp servers when configured`
- `skills.ps1`
  - 由 `./build.ps1` 重新生成。

## 3) 执行命令与关键输出
- `./build.ps1`
  - `Build success: D:\CODE\skills-manager\skills.ps1`
- `./skills.ps1 发现`
  - 退出码 `0`，发现列表正常输出。
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - 退出码 `0`
  - `Your system is ready for skills-manager.`
- `./skills.ps1 构建生效`
  - 退出码 `0`
  - `=== 构建生效流程完成 ===`
- `Invoke-Pester -Script tests\Unit\Core.Tests.ps1`
  - `Passed: 131 Failed: 0`
- `./skills.ps1 同步MCP`
  - 退出码 `0`
  - `已同步 Codex MCP 配置：C:\Users\sciman\.codex\config.toml`
- `rg -n "startup_timeout_sec" "$env:USERPROFILE\.codex\config.toml"`
  - 命中：
    - `[mcp_servers.context7] ... startup_timeout_sec = 120`
    - `[mcp_servers.microsoft-learn] ... startup_timeout_sec = 120`
- `codex exec "仅回复ok" --json`（多次）
  - 未再出现 `timed out after 30 seconds` / `MCP startup incomplete`。

## 4) 风险分级
- 风险等级：`medium`
- 风险点：
  - 仅影响 Codex MCP 配置生成逻辑，不改动 Claude/Gemini 的 MCP JSON 结构。
  - 若 `startup_timeout_sec` 配置非法（非正整数），会被忽略并记录 WARN。

## 5) 回滚
1. 回滚代码：
   - `git revert <本次提交SHA>`
2. 临时回退配置（不改代码）：
   - 从 `skills.json` 移除两个 `startup_timeout_sec` 字段后执行 `./skills.ps1 同步MCP`
3. 紧急兜底：
   - 手工编辑 `C:\Users\sciman\.codex\config.toml` 的对应 `[mcp_servers.*]` 段，但会在下次 `同步MCP` 时按 `skills.json` 重新覆盖。

