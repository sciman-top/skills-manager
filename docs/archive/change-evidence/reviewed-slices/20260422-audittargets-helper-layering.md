# 2026-04-22 audittargets-helper-layering

- 规则 ID：R1 / R2 / R6 / R8
- 风险等级：低
- 当前落点：`src/Commands/AuditTargets.ps1`、`build.ps1`
- 目标归宿：
  - 在不改行为的前提下，把 `AuditTargets` 共享 helper 从主文件继续下沉，按 `Template / Snapshot / Plan` 分层。
  - 保持 `skills.ps1` 运行结果和既有测试语义不变。

## 依据

- 上一轮已完成入口层拆分（Args/Bundle/Apply），主文件仍承载大量共享 helper。
- helper 混杂导致后续维护成本高，且测试易与“单文件布局”耦合。

## 变更

- 新增文件：
  - `src/Commands/AuditTargets.Template.ps1`
  - `src/Commands/AuditTargets.Snapshot.ps1`
  - `src/Commands/AuditTargets.Plan.ps1`
- `build.ps1`
  - 将以上 3 个新文件加入拼装顺序，并放在 `AuditTargets.Bundle.ps1` / `AuditTargets.Apply.ps1` 之前。
- `src/Commands/AuditTargets.ps1`
  - 移除已下沉函数，仅保留主流程与未下沉共享函数。

## 下沉函数分组

- Template：
  - `New-AuditSourceStrategy`
  - `Test-AuditJsonProperty`
  - `Assert-AuditBundleFileContent`
  - `Assert-AuditBundleRequiredFiles`
  - `New-AuditRecommendationsTemplate`
- Snapshot：
  - `Get-SkillMetadataFromFile`
  - `Resolve-InstalledSkillLocalPath`
  - `Get-InstalledSkillFacts`
  - `Get-AuditFingerprintFromVendorFromPairs`
  - `Get-AuditFingerprintFromSkillFacts`
  - `Get-AuditLiveInstalledState`
  - `New-AuditInstalledFactsFallbackCfg`
  - `Get-AuditInstalledSnapshotState`
  - `New-AuditInstalledSnapshotFallbackState`
- Plan：
  - `Ensure-AuditArrayProperty`
  - `Normalize-AuditSources`
  - `Assert-AuditRequiredBooleanTrue`
  - `Assert-AuditReasonPair`
  - `Assert-AuditRecommendationItem`
  - `Assert-AuditRemovalCandidate`
  - `Load-AuditRecommendations`
  - `New-AuditInstallPlan`
  - `Get-AuditApplyReportPath`
  - `Get-AuditItemsStatusCount`
  - `New-AuditChangedCounts`
  - `Write-AuditRecommendationSummary`
  - `Resolve-AuditSelection`
  - `Remove-AuditSelectedInstalledSkills`
  - `Ensure-AuditNewManualImportsMapped`

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

- 定向测试全部通过：
  - `tests/Unit/AuditTargets.Tests.ps1`
  - `tests/E2E/SkillAudit.Tests.ps1`
  - `tests/Unit/BuildScript.Tests.ps1`
- 全量测试通过：
  - `./tests/run.ps1`
  - `Passed: 262 Failed: 0`
- 项目级硬门禁通过：
  - `./build.ps1`
  - `./skills.ps1 发现`
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
  - `./skills.ps1 构建生效`

## 替代验证 / N/A

- 无

## 回滚

- 删除新文件：
  - `src/Commands/AuditTargets.Template.ps1`
  - `src/Commands/AuditTargets.Snapshot.ps1`
  - `src/Commands/AuditTargets.Plan.ps1`
- 回退：
  - `build.ps1`
  - `src/Commands/AuditTargets.ps1`
