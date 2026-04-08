# 2026-04-08 GitHub / Microsoft Learn MCP 安装

## 变更归宿
- source/project/skills-manager/*（本仓）
- 目标：将 GitHub MCP 与 Microsoft Learn MCP 纳入 `skills.json` 源配置，并同步到本机 Codex / Claude / Gemini / Trae 配置。

## 依据 -> 命令 -> 证据 -> 回滚
- 依据：
  - GitHub 官方 MCP 文档与 GitHub MCP Registry 页面。
  - Microsoft Learn 官方 MCP 端点 `https://learn.microsoft.com/api/mcp`。
- 命令：
  - `./skills.ps1 安装MCP github --transport http --url https://api.githubcopilot.com/mcp/readonly`
  - `./skills.ps1 安装MCP github --transport http --url https://api.githubcopilot.com/mcp/readonly --bearer-token-env-var GITHUB_PERSONAL_ACCESS_TOKEN`
  - `./skills.ps1 安装MCP microsoft-learn --transport http --url https://learn.microsoft.com/api/mcp`
  - `codex mcp list`
  - `codex mcp get github --json`
  - `codex mcp login github`
- 证据：
  - `skills.json` 新增 `mcp_servers.github` 与 `mcp_servers.microsoft-learn`。
  - `C:\Users\sciman\.codex\config.toml` 已同步写入两个远端 MCP。
  - `codex mcp list` 显示：
    - `github` -> `https://api.githubcopilot.com/mcp/readonly`，`Auth = Bearer token`
    - `microsoft-learn` -> `https://learn.microsoft.com/api/mcp`
  - `codex mcp get github --json` 显示：
    - `bearer_token_env_var = "GITHUB_PERSONAL_ACCESS_TOKEN"`
  - `codex mcp login github` 失败，报错：
    - `Dynamic registration failed: Dynamic client registration not supported`
  - 当前 GitHub 端点已配置为只读远端 + bearer token 环境变量名；未把 PAT 明文写入仓库或配置文件。
  - 固定门禁结果：
    - build: `./build.ps1` ✅
    - test: `./skills.ps1 发现` ✅
    - contract/invariant: `./skills.ps1 doctor --strict` ⚠️（性能阈值告警：`build_apply_total`）
    - hotspot: `./skills.ps1 构建生效` ✅
- 回滚：
  - 从 `skills.json` 删除 `github` 和 `microsoft-learn` 两个 `mcp_servers` 节点后，重新执行 `./skills.ps1 同步MCP`。
  - 如需清除本机生效配置，删除 `C:\Users\sciman\.codex\config.toml` 中对应 `[mcp_servers.*]` 段后重新同步。

## 已知限制
- GitHub MCP 当前已接入远端只读端点和 token 环境变量名，但本机尚未提供 `GITHUB_PERSONAL_ACCESS_TOKEN` 的值。
- `codex mcp login github` 在当前客户端版本下不可用，原因是动态客户端注册不被支持。
- `doctor --strict` 仍受到历史性能样本影响，`build_apply_total` 超过阈值；这不影响功能配置，但会保留为门禁告警。
- 若后续需要写权限或更完整的 GitHub 工具集，应补充 PAT / 受支持的认证路径，再重新同步。
