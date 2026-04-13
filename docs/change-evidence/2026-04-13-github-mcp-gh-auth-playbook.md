# 2026-04-13 GitHub MCP (gh auth 路线)排障复盘

## 背景与目标
- 现象：`claude mcp list` 中 `github` 持续 `Failed to connect`。
- 目标：沉淀一份可复用的排障路径，避免后续重复走弯路。

## 关键事实
- 同一台机器上，`github-toolkit` 通过 `gh auth` 可正常访问 GitHub API。
- 环境变量中的 `GITHUB_PERSONAL_ACCESS_TOKEN` 对 `https://api.github.com/user` 返回 `401`。
- `401` 出现在普通 GitHub API 与 Copilot MCP API 同时成立时，根因是 token 本身不可用，而不是 MCP 配置格式问题。

## 本次踩坑
- 误把“`github_pat` 前缀存在”当作 token 可用证据。
- 误把“在另一个项目里能用”当作“对 Copilot MCP 也一定可用”。
- 在 `401` 状态下反复调权限（Read/Write）属于低价值操作。

## 正确方法（固定顺序）
1. 先验证 token 是否能访问 GitHub 基础 API（不是先看 MCP）。
2. 再验证 Copilot MCP 端点。
3. 最后才做客户端配置与同步。

## 一步到位诊断命令
```powershell
$h=@{ Authorization = "Bearer $env:GITHUB_PERSONAL_ACCESS_TOKEN" }
Invoke-WebRequest 'https://api.github.com/user' -Headers $h -Method Get
Invoke-WebRequest 'https://api.github.com/rate_limit' -Headers $h -Method Get
Invoke-WebRequest 'https://api.githubcopilot.com/mcp/' -Headers $h -Method Get
```

判定规则：
- `api.github.com/user` 为 `401`：token 本身无效/过期/被策略拒绝。
- `api.github.com/user` 为 `200` 且 MCP 报错：再看 MCP URL、传输协议、客户端注册方式。

## 推荐路线（本仓）
- 优先使用 `gh auth` 登录态作为可信凭据来源。
- GitHub MCP URL 统一使用：`https://api.githubcopilot.com/mcp/`。
- 不以“权限堆高（Read and write 全开）”作为主要排障手段。

## 最小验证闭环
```powershell
gh auth status
gh api user --jq ".login"
claude mcp list
```

期望：
- `gh api user` 返回用户名。
- `claude mcp list` 中 `github` 显示 `Connected`。

## 自动化执行的附加坑（2026-04-13 新增）
- 在非交互终端（无 TTY）里，`claude/codex/gemini mcp list` 可能报：
  - `stdout is not a terminal`
  - `Input must be provided either through stdin`
- 这些报错不一定代表 MCP 真不可用，而是 CLI 交互模型限制。
- 本仓当前策略：
  1. `同步MCP` 后先做跨 CLI 校验与自动重试。
  2. 若检测到非交互终端限制，则走回退判定（不误判为 MCP 配置失败）。
  3. 在交互终端中仍建议人工执行一次 `claude mcp list` 作为最终可视确认。

## Codex 专项坑（2026-04-14）
- 现象：`codex mcp list` 看起来已配置，但进入 Codex CLI 仍提示：
  - `The github MCP server is not logged in`
  - `MCP startup incomplete (failed: github)`
- 根因：
  1. Codex GitHub MCP 不走 OAuth 登录流程，`codex mcp login github` 不是正确修复路径。
  2. Codex 需要 `bearer_token_env_var = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"`。
  3. 若该变量里是不可用于 Copilot MCP 的 token（常见为 `github_pat...`），会在启动期报未登录/鉴权失败。
- 正确修复顺序：
  1. `~/.codex/config.toml` 中 github 段必须使用 `bearer_token_env_var = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"`。
  2. 用 `gh auth token` 获取当前可用 token（通常前缀 `gho_`）。
  3. 将用户级 `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN` 更新为该 token，并重开终端会话。
- 快速判定：
```powershell
$u=[Environment]::GetEnvironmentVariable('CODEX_GITHUB_PERSONAL_ACCESS_TOKEN','User')
$u.Substring(0,4)  # 期望 gho_
```
- 结论：
  - `github_pat...` 在此场景常见为 `401`；
  - `gho_...` 才是本机 `gh auth` 路线下对 `api.githubcopilot.com/mcp/` 的有效凭据。

## 回滚点
- 若新配置不可用，可回滚 `skills.json` 中 GitHub MCP URL 到上一版本并重新 `./skills.ps1 同步MCP`。
