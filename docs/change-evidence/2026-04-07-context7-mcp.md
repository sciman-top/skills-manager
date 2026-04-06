# 2026-04-07 context7 MCP 集成与参数透传修复

## 变更归宿
- source/project/skills-manager/*（本仓）
- 目标：支持并落盘 `context7`（`npx -y @upstash/context7-mcp`），并修复 `安装MCP ... -- -y ...` 在 PowerShell 下的参数透传失败。

## 依据 -> 命令 -> 证据 -> 回滚
- 依据：用户要求安装 `npx -y @upstash/context7-mcp` 并做自主优化。
- 命令：
  - `./skills.ps1 安装MCP context7 --cmd npx --arg -y --arg @upstash/context7-mcp`
  - `./skills.ps1 安装MCP context7 --cmd npx -- -y @upstash/context7-mcp`
  - `./build.ps1`
  - `./skills.ps1 发现`
  - `./skills.ps1 doctor --strict`
  - `./skills.ps1 构建生效`
- 证据：
  - `skills.json` 已新增 `mcp_servers.context7`，命令为 `npx`，参数为 `-y @upstash/context7-mcp`。
  - CLI 复验：`-- -y ...` 写法现已可执行并同步到各目标配置。
  - 构建成功并完成构建生效。
- 回滚：
  - 从 `skills.json` 删除 `context7` 节点后执行 `./skills.ps1 构建生效`；
  - 若需回退解析行为，恢复 `src/Commands/Mcp.ps1` 与 `tests/Unit/Core.Tests.ps1` 本次改动后重跑 `./build.ps1`。

## 门禁执行结果（固定顺序）
1. build：`./build.ps1` ✅
2. test：`./skills.ps1 发现` ✅
3. contract/invariant：`./skills.ps1 doctor --strict` ❌（GitHub 443 连通性探测失败）
4. hotspot：`./skills.ps1 构建生效` ✅

## N/A 记录
- classification: `platform_na`
- reason: `codex status` 在非交互 shell 下返回 `stdin is not a terminal`
- alternative_verification: 已执行 `codex --version`、`codex --help`
- evidence_link: 本文件 + 终端执行记录
- expires_at: `2026-04-14`

## 触发式澄清留痕
- issue_id: `mcp-install-context7-arg-passthrough`
- attempt_count: `2`
- clarification_mode: `direct_fix`
- clarification_scenario: `bugfix`
- clarification_questions: `[]`
- clarification_answers: `[]`

## 已知风险
- `doctor --strict` 的 GitHub 连通性项受当前网络策略影响未通过；代码侧已通过功能复验（实际 `git ls-remote` 可达、MCP 安装与同步成功）。
