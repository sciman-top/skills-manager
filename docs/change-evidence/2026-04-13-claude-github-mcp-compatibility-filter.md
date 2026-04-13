# 2026-04-13 Claude GitHub MCP 兼容性过滤与落盘清理

## 变更归宿
- source/project/skills-manager/*
- 目标：避免 Claude 侧继续持有一个当前认证路径下会 `Failed to connect` 的 `github` MCP，同时保留 `context7` / `microsoft-learn` 等可用共享 MCP。

## 依据 -> 命令 -> 证据 -> 回滚
- 依据：
  - 之前 `./skills.ps1 同步MCP` 会把 `github` 同步到 Claude native 配置和 `.claude/.mcp.json`，但 `claude mcp list` 对该项持续显示失败。
  - 直接连通性测试返回 `401`，说明当前 GitHub MCP 认证路径对本机不可用。
  - `fetch` / `filesystem` 已从 Claude 用户配置移除，不再是当前问题来源。
- 命令：
  - `./build.ps1`
  - `Invoke-Pester .\tests\Unit\Core.Tests.ps1`
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
  - `./skills.ps1 构建生效`
  - `./skills.ps1 同步MCP`
  - `claude mcp list`
  - `Select-String -Path 'C:\Users\sciman\.claude\.mcp.json' -Pattern '"github"'`
  - `Select-String -Path 'C:\Users\sciman\.claude.json' -Pattern '"github"'`
- 证据：
  - `src/Commands/Mcp.ps1`：
    - 新增 `Get-ClaudeCompatibleMcpServers`，将 `github` 从 Claude 兼容同步集合中剔除。
    - 新增 `Remove-McpServersFromPayload`，在 Claude 落盘时清理既有的 `github` 键。
    - `同步MCP` 对 `.claude` 目标和 Claude native 注册改用过滤后的集合。
  - `tests/Unit/Core.Tests.ps1`：
    - 新增 `Get-ClaudeCompatibleMcpServers` 单测。
    - 新增 `Remove-McpServersFromPayload` 单测。
  - `claude mcp list`：当前仅显示 `context7`、`microsoft-learn`、`zai-mcp-server`、`web-search-prime`、`web-reader`、`zread`，不再显示 `github`。
  - `Select-String` 结果：`C:\Users\sciman\.claude\.mcp.json` 与 `C:\Users\sciman\.claude.json` 中已不再命中 `"github"`。
  - `Invoke-Pester .\tests\Unit\Core.Tests.ps1`：`Passed: 118 Failed: 0`。
- 回滚：
  - 恢复 `src/Commands/Mcp.ps1` 中 Claude 兼容过滤与落盘清理逻辑。
  - 重新执行 `./build.ps1`、`./skills.ps1 构建生效`、`./skills.ps1 同步MCP`。

## 已知限制
- `github` 仍保留在 `skills.json` 中，供 Codex 等可用路径按条件同步。
- 如果后续 Claude 的 GitHub MCP 认证路径变得可用，需要再评估是否恢复同步策略，而不是直接默认写回。
