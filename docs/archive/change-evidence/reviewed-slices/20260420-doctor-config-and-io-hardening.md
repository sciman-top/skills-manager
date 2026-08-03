# 20260420-doctor-config-and-io-hardening

- rule_id: R1,R2,R3,R6,R8
- risk_level: low
- scope: `src/Commands/Doctor.ps1`, `src/Core.ps1`, `tests/Unit/DoctorCli.Tests.ps1`, `skills.ps1`（build 生成）
- current_anchor: `src/Commands/Doctor.ps1` + `src/Core.ps1`
- target_destination: 在不改变外部命令、配置语义、数据格式的前提下，修复两处已证据化正确性问题

## Basis
1. **契约不一致**：`LoadCfg` 支持 `skills.json` 整行 `//` 注释，`Invoke-Doctor` 直接 `ConvertFrom-Json`，会将同一配置在 doctor 阶段误判为坏配置。
2. **写入行为不稳定**：`Set-ContentUtf8` 在成功路径未清除 `Hidden/System/ReadOnly`，导致隐藏文件写入后仍不可见；`tests/run.ps1` 出现失败：`Set-ContentUtf8 -> Overwrites hidden files`。

## Changes
1. `Invoke-Doctor` 配置检查改为与 `LoadCfg` 一致：先移除整行 `//` 注释，再 `ConvertFrom-Json`。
2. 新增 `Clear-FileWriteBlockAttributes`，并在 `Set-ContentUtf8` 的写前、写后及重试分支统一调用，确保属性归一化一致。
3. 新增 doctor 回归测试：`line-commented skills.json` 在 doctor 中应被识别为有效配置。

## Commands
1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`
5. `Import-Module Pester | Out-Null; Invoke-Pester -Script "tests/Unit/DoctorCli.Tests.ps1" -PassThru`
6. `Import-Module Pester | Out-Null; Invoke-Pester -Script "tests/Unit/SetContentUtf8.Tests.ps1" -PassThru`
7. `./tests/run.ps1`
8. `codex --version`
9. `codex --help`
10. `codex status`

## Key Output
- gate(build): `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- gate(test): `./skills.ps1 发现` 成功输出 132 项技能清单，exit_code=0
- gate(contract/invariant): `Your system is ready for skills-manager.`
- gate(hotspot): `=== 构建生效流程完成 ===`
- doctor 单测: `Passed: 2 Failed: 0`
- Set-ContentUtf8 单测: `Passed: 2 Failed: 0`
- 全量测试: `tests/run.ps1 -> Passed: 223 Failed: 0`（Unit）+ `Passed: 9 Failed: 0`（E2E）
- `codex --version`: `codex-cli 0.121.0`
- `codex --help`: 成功返回命令帮助，exit_code=0

## N/A
- type: `platform_na`
- item: `codex status`
- reason: 非交互终端返回 `stdin is not a terminal`
- alternative_verification: 使用 `codex --version` + `codex --help` + 本次门禁与测试结果补齐诊断证据
- evidence_link: `docs/change-evidence/20260420-doctor-config-and-io-hardening.md`
- expires_at: `2026-04-27`

- type: `gate_na`
- item: `supply_chain_gate`
- reason: 本次未新增/升级依赖，无锁文件与供应链输入变化
- alternative_verification: 全量测试 + 门禁链 + 目标回归单测
- evidence_link: `docs/change-evidence/20260420-doctor-config-and-io-hardening.md`
- expires_at: `2026-04-27`

## Rollback
1. 回退文件：`src/Commands/Doctor.ps1`、`src/Core.ps1`、`tests/Unit/DoctorCli.Tests.ps1`、`skills.ps1`
2. 重新生成：`./build.ps1`
3. 复验：`./skills.ps1 发现` -> `./skills.ps1 doctor --strict --threshold-ms 8000` -> `./skills.ps1 构建生效`
