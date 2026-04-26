# 2026-04-26 代码审查与低风险硬化

## 1) 依据
- 规则 ID: `R1/R2/R6/R8`, `E4/E5`
- 当前落点: `src/Config.ps1`, `src/Commands/Doctor.ps1`, `tests/Unit/*`, generated `skills.ps1`
- 目标归宿: 保持现有命令、配置格式和用户体验不变，修复配置合同误判与 doctor 诊断边界问题
- 风险等级: `low`
- clarification_mode: `direct_fix`

## 2) 问题 -> 修改 -> 收益 -> 风险 -> 回滚
### 2.1 `overrides` 映射在配置合同层可能被误判为不存在的 vendor
- 问题: `Install/Doctor` 已把 `manual` 和 `overrides` 当作保留输入层，但 `Config` 的合同校验、自动修复和断言只内置 `manual`，未来一旦 `skills.json` 中出现 `vendor=overrides` 映射会被误删或阻断。
- 修改: 新增 `New-CfgVendorNameSet`，统一保留 `manual/overrides`，并复用于 `Get-CfgContractErrors`、`Fix-Cfg`、`Assert-Cfg`、doctor 修复和风险扫描。
- 收益: 配置合同、doctor 风险扫描和自动修复口径一致，避免覆盖层映射被误判。
- 风险: 只扩大已存在的保留 vendor 识别范围，不改变普通 vendor 解析。
- 回滚: 回退 `src/Config.ps1`, `src/Commands/Doctor.ps1`, `tests/Unit/ConfigUpdate.Tests.ps1`, 重新 `./build.ps1`。

### 2.2 doctor 性能异常阈值边界与描述不一致
- 问题: 测试描述和用户语义是 `exceeds threshold`，实现用 `-ge`，导致等于阈值也被标为异常。
- 修改: `Get-PerfAnomalyItems` 改为 `last/avg > threshold` 才告警，并补测试。
- 收益: doctor 告警边界与文案、quality gate 阈值判断一致。
- 风险: 等于阈值从告警变为正常；符合现有 `check-doctor-json.ps1` 语义。
- 回滚: 回退 `src/Commands/Doctor.ps1` 与对应测试，重新 `./build.ps1`。

### 2.3 doctor 性能摘要整读日志
- 问题: `doctor` 只需要最近 3 次指标，却整读 `build.log`。
- 修改: 读取性能摘要时使用 `Get-Content -Tail 5000`。
- 收益: 减少日志 IO 和 JSON 解析量，保持最近指标语义。
- 风险: 极端情况下超过 5000 行未出现的旧指标不再进入 doctor 摘要；doctor 语义是最近性能摘要，可接受。
- 回滚: 将 `-Tail 5000` 改回整读，重新 `./build.ps1`。

### 2.4 `sync_mcp` 默认路径重复执行慢速外部探测
- 问题: `同步MCP` 每次都执行原生 `claude mcp remove/add` 和跨 CLI live `mcp list`；在配置已落盘且服务已存在时，这些外部调用多为重复失败或慢速探测，导致一次同步约 19s。
- 修改: 默认只写入各目标配置并做配置态校验；原生 Claude 注册/清理由 `SKILLS_MCP_NATIVE_SYNC=1` 显式启用，跨 CLI live `mcp list` 由 `SKILLS_MCP_VERIFY_LIVE_CLI=1` 显式启用。
- 收益: 默认 `同步MCP` 从约 `19327ms` 降至约 `1992ms/1812ms`，`doctor --json` 中 `sync_mcp` 最近 3 次降至 `avg_ms=1774`, `last_ms=1812`, `anomalies=[]`。
- 风险: 默认路径不再每次实机调用 CLI 探测；需要现场强验证时必须设置显式环境变量。
- 回滚: 移除 `Should-RunNativeMcpSync` / `Should-VerifyLiveMcpCli` 默认跳过逻辑，重新 `./build.ps1`。

## 3) 执行命令与证据
- `codex --version` -> exit 0, `codex-cli 0.125.0`
- `codex --help` -> exit 0, help returned
- `codex status` -> exit 1, `Error: stdin is not a terminal`
- baseline `./build.ps1` -> exit 0, `Build success`
- baseline `./skills.ps1 发现` -> exit 0, 96 skills listed
- baseline `./skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0, pass with non-blocking `sync_mcp` perf warning
- baseline `./skills.ps1 构建生效` -> exit 0, 91 skills built and linked
- targeted PowerShell assertions -> exit 0, `targeted assertions passed`
- final `./build.ps1` -> exit 0, `Build success`
- final `./skills.ps1 发现` -> exit 0, 96 skills listed
- final `./skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0, `Your system is ready for skills-manager`
- final `./skills.ps1 构建生效` -> exit 0, `构建完成：agent/ (共 91 项技能)`
- `./scripts/quality/run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree` -> exit 0, local quick gates passed
- `./skills.ps1 doctor --json` -> exit 0, `pass=true`, `risks=[]`, warning `sync_mcp: last=31004ms avg=15807ms threshold=10000ms`
- secret scan excluding `vendor/agent/imports/reports/build.log*` -> exit 1 with empty output, no matches
- pre-fix measured `./skills.ps1 同步MCP` with `SKILLS_MCP_VERIFY_ATTEMPTS=1` -> about `19327ms`
- post-fix measured default `./skills.ps1 同步MCP` -> about `1992ms`, then about `2066ms` and `2030ms`
- post-fix `./skills.ps1 doctor --json` -> `sync_mcp.avg_ms=1774`, `sync_mcp.last_ms=1812`, `anomalies=[]`

## 4) N/A 记录
### platform_na
- reason: `codex status` requires an interactive terminal in this shell.
- alternative_verification: `codex --version` and `codex --help` both returned successfully.
- evidence_link: section 3
- expires_at: `2026-05-31`

### gate_na
- reason: local Pester module is not installed, so `./tests/run.ps1` cannot execute the Pester suite.
- alternative_verification: targeted assertions plus fixed project gates and quick quality gates passed.
- evidence_link: section 3
- expires_at: `2026-05-31`

## 5) 遗留风险
- 原生 Claude MCP 注册/清理和跨 CLI live `mcp list` 已改为 opt-in；需要现场强验证时设置 `SKILLS_MCP_NATIVE_SYNC=1` 或 `SKILLS_MCP_VERIFY_LIVE_CLI=1` 后运行。
- 工作区在本次开始前已有未提交改动：`.governed-ai/*`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.geminiignore` 等；本次未回退这些既有改动。
