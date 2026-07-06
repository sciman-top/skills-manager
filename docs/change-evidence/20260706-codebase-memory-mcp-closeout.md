# 20260706 codebase-memory-mcp closeout

- 规则 ID: R6 / R8 / E5
- 风险等级: low
- 当前落点: `skills-manager` 审查包 apply 后的 MCP 配置与单测收口
- 目标归宿: `codebase-memory-mcp` 在仓库配置、Codex 实际配置、单测与硬门禁中保持一致

## 变更

- 修正 `tests/Unit/Core.Tests.ps1` 中 `codebase-memory-mcp` 的 Codex TOML 断言：
  - 首个 `$exe` 改为字面量，避免 PowerShell 在构造测试字符串时提前插值为空串。
  - 路径断言改为更稳的模式，匹配 TOML 转义后的真实输出。
- 保持 `skills.json` 中 `codebase-memory-mcp` 使用 `pwsh` 包装器：
  - 先尝试 `%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`
  - 回退 `Get-Command codebase-memory-mcp`
  - 缺失时明确报错并退出

## 执行命令

- `Invoke-Pester -Path .\tests\Unit\Core.Tests.ps1`
- `./build.ps1`
- `./skills.ps1 发现`
- `./skills.ps1 doctor --strict --threshold-ms 8000`
- `./skills.ps1 构建生效`
- `codex mcp get codebase-memory-mcp`
- `C:\Users\sciman\AppData\Local\Programs\codebase-memory-mcp\codebase-memory-mcp.exe --version`

## 关键输出

- Pester: `Tests Passed: 168, Failed: 0`
- build: `Build success: D:\CODE\skills-manager\skills.ps1`
- discover: 新增技能可见，合计 `107` 条
- doctor: `skills.json` 合约通过，`Mappings: 95`
- hotspot: 构建生效通过，Agent 输出 `100`
- codex mcp get: `command: pwsh`
- binary version: `codebase-memory-mcp 0.8.1`

## 回滚

- 若需回滚本次验证层修正：撤销 `tests/Unit/Core.Tests.ps1` 中 `codebase-memory-mcp` 相关断言改动。
- 若需回滚 MCP 接入：从 `skills.json` 删除 `codebase-memory-mcp` 服务器定义与新增技能映射/导入后，重新执行 `./build.ps1`、`./skills.ps1 构建生效`、`./skills.ps1 同步MCP`。
