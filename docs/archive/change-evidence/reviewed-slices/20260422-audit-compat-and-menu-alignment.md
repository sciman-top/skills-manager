# 2026-04-22 audit-compat-and-menu-alignment

- 规则 ID：R1 / R2 / R6 / R8
- 风险等级：低
- 当前落点：`src/Commands/AuditTargets.ps1`、`src/Commands/Utils.ps1`
- 目标归宿：
  - 修复 `AuditTargets` 既有失败，恢复审查包生成与 recommendations apply 的兼容路径。
  - 让“技能库管理”菜单与测试/帮助文案重新对齐。

## 依据

- 全量 Pester 之前存在既有失败：
  - `tests/Unit/AuditTargets.Tests.ps1`
  - `tests/E2E/SkillAudit.Tests.ps1`
  - `tests/Unit/MenuStructure.Tests.ps1`
- 失败根因分为两类：
  - `AuditTargets` 新增了对 `installed-skills.json` 快照的强依赖，旧测试和部分非 run-dir 调用没有该文件。
  - “技能库管理”菜单第 4 项已改成“清理无效映射”，而菜单测试和帮助文本仍以“打开配置”为准。

## 变更

- `src/Commands/AuditTargets.ps1`
  - 新增空安装快照回退配置：`New-AuditInstalledFactsFallbackCfg`
  - 新增旧调用兼容快照状态：`New-AuditInstalledSnapshotFallbackState`
  - `Invoke-AuditTargetsScan`
    - 读取 `skills.json` 失败时回退为空快照，而不是直接阻断
    - 复用已加载配置计算 live installed state
  - `Invoke-AuditSkillDiscovery`
    - 同步使用空快照回退逻辑
  - `Invoke-AuditRecommendationsApply`
    - `recommendations` 同目录缺少 `installed-skills.json` 时，回退为 live state 快照
    - 保留正式 run-dir 下真实快照优先的行为
- `src/Commands/Utils.ps1`
  - “技能库管理”菜单第 4 项恢复为 `打开配置`
  - 帮助文案同步改回“技能库管理：新增/删除技能库、生成锁文件、打开配置”

## 执行命令

```powershell
./build.ps1
Invoke-Pester -Script tests/Unit/AuditTargets.Tests.ps1
Invoke-Pester -Script tests/E2E/SkillAudit.Tests.ps1
Invoke-Pester -Script tests/Unit/MenuStructure.Tests.ps1
./tests/run.ps1
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

## 关键证据

- 定向测试：
  - `tests/Unit/AuditTargets.Tests.ps1` 通过
  - `tests/E2E/SkillAudit.Tests.ps1` 通过
  - `tests/Unit/MenuStructure.Tests.ps1` 通过
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

- 回滚代码：
  - 撤销 `src/Commands/AuditTargets.ps1`
  - 撤销 `src/Commands/Utils.ps1`
- 回滚行为：
  - recommendations 非 run-dir 调用会重新要求同目录必须存在 `installed-skills.json`
  - 空 `skills.json` 安装事实回退失效
  - 技能库管理菜单第 4 项重新回到当前实现前的分叉状态
