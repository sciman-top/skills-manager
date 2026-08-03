# 2026-04-13 Codex GitHub MCP 启动保护

## 变更归宿
- source/project/skills-manager/*
- 目标：避免 `github` MCP 被同步进 Codex 配置后导致启动提示 `The github MCP server is not logged in`.

## 依据 -> 命令 -> 证据 -> 回滚
- 依据：
  - 本机 `codex mcp list` 显示 `github` MCP 为 `enabled`，但 `codex mcp login github` 在当前客户端版本下不可用。
  - `./skills.ps1 同步MCP` 先前会把 `github` 写入 `~/.codex/config.toml`，触发 Codex 启动告警。
- 命令：
  - `./build.ps1`
  - `./skills.ps1 发现`
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
  - `./skills.ps1 构建生效`
  - `./skills.ps1 同步MCP`
- 证据：
  - `src/Commands/Mcp.ps1` 的 `Build-CodexConfigToml` 过滤了 `github` MCP，不再写入 Codex 配置。
  - `tests/Unit/Core.Tests.ps1` 增加了回归测试，覆盖 `github` 被跳过而 `microsoft-learn` 仍保留的场景。
  - `~/.codex/config.toml` 同步后仅保留 `context7` 与 `microsoft-learn`，不再包含 `github`。
  - `./skills.ps1 doctor --strict --threshold-ms 8000` 通过。
  - `./skills.ps1 构建生效` 通过。
- 回滚：
  - 恢复 `src/Commands/Mcp.ps1` 中的 `github` 过滤逻辑。
  - 恢复 `tests/Unit/Core.Tests.ps1` 中对应回归测试。
  - 重新执行 `./build.ps1` 和 `./skills.ps1 同步MCP`。

## 已知限制
- 当前仍保留 `github` MCP 在 `skills.json` 中，供其它客户端或后续可用认证路径使用。
- `./skills.ps1 同步MCP` 仍会尝试原生命令路径注册 `github` 到 Claude 侧，并输出一次可忽略的头格式警告；本次修复只针对 Codex 启动链路。
