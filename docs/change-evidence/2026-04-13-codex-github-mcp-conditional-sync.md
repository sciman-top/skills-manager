# 2026-04-13 Codex GitHub MCP 条件同步与 Claude 原生命令 header 修复

## 变更归宿
- source/project/skills-manager/*
- 目标：让 `github` MCP 在 Codex 中按配置共享同步；同时让 Claude 原生命令同步使用可接受的 HTTP header 格式。

## 依据 -> 命令 -> 证据 -> 回滚
- 依据：
  - 源配置 `skills.json` 已包含 `context7` / `github` / `microsoft-learn`。
  - 之前 `Build-CodexConfigToml` 固定跳过 `github`，导致 Codex 少一个共享 MCP。
  - `claude mcp list`/`同步MCP` 的原生命令链对 `-H` header 格式敏感，`Authorization=...` 会报格式错误。
- 命令：
  - `./build.ps1`
  - `Invoke-Pester .\tests\Unit\Core.Tests.ps1`
  - `./skills.ps1 发现`
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
  - `./skills.ps1 构建生效`
  - `./skills.ps1 同步MCP`
  - `codex mcp list`
  - `claude mcp list`
- 证据：
  - `src/Commands/Mcp.ps1`：Codex GitHub MCP 改为仅在缺少 `GITHUB_PERSONAL_ACCESS_TOKEN` 时跳过；HTTP header 改为 `-H "Header: value"` 格式。
  - `tests/Unit/Core.Tests.ps1`：新增/更新回归测试，覆盖 `github` 无 token 跳过、有 token 同步，以及 Claude 原生命令 header 格式。
  - `codex mcp list`：现在显示 `context7`、`github`、`microsoft-learn`。
  - `claude mcp list`：仍可看到 `github`，但其健康状态依赖本机认证与 Claude 运行时对该配置的支持。
  - `Invoke-Pester .\tests\Unit\Core.Tests.ps1`：`Passed: 116 Failed: 0`。
- 回滚：
  - 恢复 `src/Commands/Mcp.ps1` 中 Codex 对 `github` 的条件同步逻辑，改回固定跳过。
  - 将 `Get-NativeMcpKeyValueFlags` / `Get-NativeMcpAddArgs` 的 header 分隔符改回原实现。
  - 重新执行 `./build.ps1` 和 `./skills.ps1 同步MCP`。

## 已知限制
- `fetch`、`filesystem` 是否保留，取决于你是否需要跨项目网页抓取或本地文件系统 MCP；它们不是 `E:\CODE` 项目日常必需项。
- `claude` 侧 `github` 仍可能因认证/运行时支持差异出现 health check 失败，需要按 Claude 的 MCP 认证支持再做进一步收敛。
