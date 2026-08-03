# 2026-04-13 Shared GitHub MCP restore and legacy fetch/filesystem prune

## 变更归宿
- source/project/skills-manager/*
- 目标：把 `github` 恢复为共享 MCP 源配置，并清理 `fetch` / `filesystem` 这类旧的、无意保留的条目。

## 依据 -> 命令 -> 证据 -> 回滚
- 依据：
  - `skills.json` 之前已不再包含 `github`，导致共享 MCP 源配置收缩。
  - Claude 的用户状态文件里仍残留 `fetch`，Trae 项目状态里也有 `fetch`。
  - GitHub 官方文档示例对 PAT 场景使用 `https://api.githubcopilot.com/mcp/readonly`。
- 命令：
  - `./build.ps1`
  - `Invoke-Pester .\tests\Unit\Core.Tests.ps1`
  - `claude mcp list`
  - `Get-Content C:\Users\sciman\.claude.json`
  - `Get-Content C:\Users\sciman\.claude\.mcp.json`
- 证据：
  - `skills.json`：重新加入 `github` MCP，使用 `https://api.githubcopilot.com/mcp/readonly` 与 `Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}`。
  - `src/Commands/Mcp.ps1`：
    - `同步MCP` 对所有目标统一写入共享 MCP。
    - `Get-LegacyMcpServersToPrune` / `Remove-McpServersFromPayload` 用于清理 `fetch` / `filesystem`。
    - Claude native 注册继续保留现有可用服务器，`github` 在 native add 路径上跳过，避免当前客户端路径阻塞。
  - `tests/Unit/Core.Tests.ps1`：
    - 新增 legacy MCP prune 回归测试。
  - `C:\Users\sciman\.claude.json`：`fetch` 已从 `C:/Users/sciman/.trae` 项目状态中清掉，`github` 仍在 top-level shared MCP 中。
  - `C:\Users\sciman\.claude\.mcp.json`：`github` 目前使用 `readonly` URL。
  - `claude mcp list`：在当前可用 token 下，`context7` / `microsoft-learn` / `zai-mcp-server` / `web-search-prime` / `web-reader` / `zread` 可连通，但 `github` 仍显示 `Failed to connect`。
  - `Invoke-Pester .\tests\Unit\Core.Tests.ps1`：`Passed: 118 Failed: 0`。
- 回滚：
  - 从 `skills.json` 删除 `github` MCP。
  - 恢复 `src/Commands/Mcp.ps1` 中 legacy prune 逻辑的回滚点。
  - 重新执行 `./build.ps1` 与 `./skills.ps1 同步MCP`。

## 已知限制
- `github` 仍受当前 GitHub token / MCP 认证路径限制；仓库已恢复共享配置，但 Claude 侧在这台机器上仍未连通。
- `fetch` / `filesystem` 当前仅作为遗留状态清理项处理，不再纳入共享 MCP。
