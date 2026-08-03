# 2026-07-06 widen filesystem MCP root to D:\CODE

## Goal

- 当前落点: `D:\CODE\skills-manager`
- 目标归宿: 把本仓托管的 `filesystem` MCP 默认 allowed root 从 `D:\CODE\skills-manager` 调整为 `D:\CODE`，并同步到 live Codex MCP 配置。
- 验证方式: 先按项目硬门禁执行 `build -> test -> contract/invariant -> hotspot`，再执行 `.\skills.ps1 同步MCP` 和 live MCP 实测。

## Risk

- 风险等级: 中
- 原因: `filesystem` MCP 访问面从单仓扩展到工作区根目录，live 同步会写入用户级 `C:\Users\sciman\.codex\config.toml`。
- 风险处理:
  - 只调整受托管的 `filesystem` MCP 一项，不扩展其他 MCP 权限。
  - 同步后用 `codex mcp list` 和实际 MCP 调用确认 live 限定目录已切到 `D:\CODE`。

## Commands

```powershell
.\build.ps1
.\skills.ps1 发现
.\skills.ps1 doctor --strict --threshold-ms 8000
.\skills.ps1 构建生效
Invoke-Pester -Path .\tests\Unit\Core.Tests.ps1
.\skills.ps1 同步MCP
codex mcp list
```

## Key Output

- `skills.json` 中 `filesystem` MCP 的启动参数由 `D:\CODE\skills-manager` 改为 `D:\CODE`。
- `README.md` / `README.en.md` 的安装示例与真源保持一致。
- `tests/Unit/Core.Tests.ps1` 的预期参数同步更新。
- `codex mcp get filesystem` 显示 live Codex MCP 参数已切到 `D:\CODE`。
- 当前对话已加载的 `filesystem` MCP 仍返回 `D:\CODE\skills-manager`，说明本次变更已写入 live 配置，但当前会话未热重载。

## Verification

- `.\build.ps1`: pass
- `.\skills.ps1 发现`: pass，发现 96 个技能
- `.\skills.ps1 doctor --strict --threshold-ms 8000`: pass
- `.\skills.ps1 构建生效`: pass
- `Invoke-Pester -Path .\tests\Unit\Core.Tests.ps1`: 首次失败 1 条（遗漏旧路径断言），修正后重跑 pass，`167 passed, 0 failed`
- `.\skills.ps1 同步MCP`: pass，写入 9 个目标
- `codex mcp get filesystem`: pass，`args ... D:\CODE`
- `codex mcp list`: pass，`filesystem` 为 `enabled`，参数尾部为 `D:\CODE`

## Rollback

```powershell
# 回滚仓内真源
git checkout -- skills.json README.md README.en.md tests/Unit/Core.Tests.ps1 docs/change-evidence/20260706-filesystem-mcp-root-d-code.md

# 若已同步到 live，再把 filesystem MCP 参数改回单仓目录并重新同步
.\skills.ps1 安装MCP filesystem --cmd npx --arg -y --arg @modelcontextprotocol/server-filesystem --arg D:\CODE\skills-manager
.\skills.ps1 同步MCP
```
