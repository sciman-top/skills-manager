# 2026-04-22 audittargets-light-split

- 规则 ID：R1 / R2 / R6 / R8
- 风险等级：低
- 当前落点：`src/Commands/AuditTargets.ps1`、`build.ps1`、`tests/Unit/AuditTargets.Tests.ps1`、`tests/Unit/BuildScript.Tests.ps1`
- 目标归宿：
  - 把 `AuditTargets` 的命令入口、bundle 生成、apply/status 从单文件中拆出，降低 `src/Commands/AuditTargets.ps1` 的横向职责密度。
  - 保持 `skills.ps1` 生成结果和用户可见行为不变。

## 依据

- `src/Commands/AuditTargets.ps1` 长期同时承载：
  - 参数解析 / 命令分发
  - scan / discover bundle 生成
  - dry-run / apply / status
- 上一轮修复后功能已稳定，适合先做轻拆分，不改行为，只收敛边界。
- `build.ps1` 与 `BuildScript.Tests.ps1` 仍按旧单文件假设工作，需要一并更新。

## 变更

- `src/Commands/AuditTargets.Bundle.ps1`
  - 承接 `Invoke-AuditTargetsScan`
  - 承接 `Invoke-AuditSkillDiscovery`
- `src/Commands/AuditTargets.Apply.ps1`
  - 承接 `Invoke-AuditRecommendationsApply`
  - 承接 `Invoke-AuditRecommendationsTwoStageApply`
  - 承接 apply token/status 相关函数
- `src/Commands/AuditTargets.Args.ps1`
  - 承接 `Parse-AuditTargetsArgs`
  - 承接 `Invoke-AuditTargetsCommand`
- `src/Commands/AuditTargets.ps1`
  - 删除已拆出的入口层定义，保留共享模型、校验、模板、plan helper
- `build.ps1`
  - 将 3 个新源文件纳入生成顺序
- `tests/Unit/AuditTargets.Tests.ps1`
  - 将运行态摘要文案断言切到 `skills.ps1`，避免测试强绑单一源码文件
- `tests/Unit/BuildScript.Tests.ps1`
  - 从 `build.ps1` 自解析 `$Files` 清单，避免后续源文件拆分时临时工作区漏拷贝

## 执行命令

```powershell
./build.ps1
Invoke-Pester -Script tests/Unit/AuditTargets.Tests.ps1
Invoke-Pester -Script tests/E2E/SkillAudit.Tests.ps1
Invoke-Pester -Script tests/Unit/BuildScript.Tests.ps1
./tests/run.ps1
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

## 关键证据

- 定向验证：
  - `tests/Unit/AuditTargets.Tests.ps1` 通过
  - `tests/E2E/SkillAudit.Tests.ps1` 通过
  - `tests/Unit/BuildScript.Tests.ps1` 通过
- 全量测试：
  - `./tests/run.ps1` 通过
  - `Passed: 262 Failed: 0`
- 项目级门禁：
  - `./build.ps1` 通过
  - `./skills.ps1 发现` 通过
  - `./skills.ps1 doctor --strict --threshold-ms 8000` 通过
  - `./skills.ps1 构建生效` 通过

## 替代验证 / N/A

- 无

## 回滚

- 代码回滚：
  - 删除 `src/Commands/AuditTargets.Bundle.ps1`
  - 删除 `src/Commands/AuditTargets.Apply.ps1`
  - 删除 `src/Commands/AuditTargets.Args.ps1`
  - 回退 `build.ps1`
  - 回退 `src/Commands/AuditTargets.ps1`
  - 回退两处测试更新
- 行为影响：
  - `AuditTargets` 重新回到单文件入口结构
  - `BuildScript.Tests.ps1` 会重新依赖手写源文件清单
