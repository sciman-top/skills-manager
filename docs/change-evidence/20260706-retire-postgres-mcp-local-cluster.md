# 2026-07-06 retire postgres MCP local cluster startup chain

## 规则与风险
- 规则：R1/R2/R3/R6/R8。
- 当前落点：`D:\CODE\skills-manager`，并联动本机脚本 `C:\Users\sciman\Scripts\Start-DevStack.ps1`。
- 目标归宿：退役旧的 `127.0.0.1:55432` PostgreSQL MCP 本地集群启动链，只保留当前主链 `127.0.0.1:5432 / k12_question_graph`。
- 风险等级：中。涉及本机计划任务、启动脚本、wrapper 与本地运行态目录删除。

## 根因与判定
- `skills-manager-mcp-postgres-start` 计划任务本身已经禁用，但并不是唯一启动源。
- 真正的自动拉起入口是本机 `StartDevStackDelayed` 任务；其脚本 `C:\Users\sciman\Scripts\Start-DevStack.ps1` 默认会启动 `skills-manager-mcp-postgres-start.vbs`，继而拉起 `%LOCALAPPDATA%\skills-manager\postgres-mcp\17\start-postgres-mcp.ps1`。
- 当前 `skills-manager` 受管配置已改为读取 `POSTGRES_CONNECTION_STRING`，用户环境变量解析到 `127.0.0.1:5432 / k12_question_graph`；`55432` 旧集群不再是主链依赖。

## 实施变更
- 将 `C:\Users\sciman\Scripts\Start-DevStack.ps1` 中 `StartPostgresMcp` 默认值改为 `false`。
- 将 `C:\Users\sciman\Scripts\Start-DevStack.ps1` 的 `PostgresMCP` 分支改为显式返回 `retired`，不再尝试调用旧 wrapper。
- 注销计划任务 `skills-manager-mcp-postgres-start`。
- 使用 `pg_ctl stop -D %LOCALAPPDATA%\skills-manager\postgres-mcp\17\data -m fast` 停止旧集群。
- 删除 `C:\Users\sciman\AppData\Local\governed-ai-coding-runtime\startup-wrappers\skills-manager-mcp-postgres-start.vbs`。
- 删除 `C:\Users\sciman\AppData\Local\skills-manager\postgres-mcp\17\` 目录。

## 验证命令与关键结果
- `Get-ScheduledTask -TaskName skills-manager-mcp-postgres-start`
  - 结果：任务已不存在。
- `Get-NetTCPConnection -LocalPort 55432 -State Listen`
  - 结果：无监听，`55432` 已关闭。
- `Get-Service postgresql-x64-17` 与 `Get-NetTCPConnection -LocalPort 5432 -State Listen`
  - 结果：服务仍为 `Running`，`5432` 继续监听。
- `C:\Users\sciman\Scripts\Start-DevStack.ps1 -WarmWsl $false -StartOperatorUi $false -StartK12Web $false`
  - 结果：`PostgreSQL already-running`，未重新拉起 `55432`。
- `C:\Users\sciman\Scripts\Start-DevStack.ps1 -WarmWsl $false -StartOperatorUi $false -StartK12Web $false -StartPostgresMcp $true`
  - 结果：`PostgresMCP retired`，不会再访问已删除的旧 wrapper。
- `git diff --check`
  - 结果：通过；仅有既存 CRLF 提示，无 whitespace error。

## Gate N/A
- `gate_na`: 未执行本仓完整 `build -> test -> contract/invariant -> hotspot`。
- `reason`: 本次变更的行为面集中在主机级脚本 `C:\Users\sciman\Scripts\Start-DevStack.ps1`、计划任务与 `%LOCALAPPDATA%` 运行态目录清理；仓库内仅新增证据文件，整仓门禁无法直接证明或回放该主机级启动链退役。
- `alternative_verification`: 已执行计划任务存在性核查、`55432/5432` 端口与服务状态核查、显式运行 `Start-DevStack.ps1` 验证 `PostgresMCP retired`、以及 `git diff --check`。
- `evidence_link`: `docs/change-evidence/20260706-retire-postgres-mcp-local-cluster.md`
- `expires_at`: `2026-08-31`

## 边界
- 仓库中的 `tests/Unit/Core.Tests.ps1` 仍保留 `55432` 示例字符串；它们用于连接串归一化测试，不代表 live 运行依赖。
- 本次未修改 `skills.json`、未变更当前 `POSTGRES_CONNECTION_STRING`，也未动 `5432` 主链数据库实例。

## 回滚
- 如需恢复旧链路：
  - 还原 `C:\Users\sciman\Scripts\Start-DevStack.ps1` 中 `StartPostgresMcp` 默认值与分支逻辑。
  - 重新创建 `C:\Users\sciman\AppData\Local\governed-ai-coding-runtime\startup-wrappers\skills-manager-mcp-postgres-start.vbs` 与 `%LOCALAPPDATA%\skills-manager\postgres-mcp\17\start-postgres-mcp.ps1`。
  - 如数据目录仍需恢复，需从外部备份恢复 `%LOCALAPPDATA%\skills-manager\postgres-mcp\17\`。
  - 重新注册计划任务 `skills-manager-mcp-postgres-start`，或在 `Start-DevStack.ps1` 中再次启用该启动链。
