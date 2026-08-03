# 2026-04-22 doctor-update-thresholds-and-acl-backup-path

- 规则 ID：R1 / R2 / R6 / R8
- 风险等级：低
- 当前落点：`src/Commands/Doctor.ps1`、`scripts/git-acl-guard.ps1`、`scripts/fix-git-acl.ps1`
- 目标归宿：
  - `doctor` 对 `update_vendor` / `update_imports` / `update_total` 开启性能阈值告警。
  - Git ACL 备份默认写入 `reports/runtime/acl-backups/`，不再堆积到仓库根。

## 依据

- `doctor --json --strict --threshold-ms 8000` 已能读到 `update_*` 指标，但此前 `Get-PerfThresholdMs()` 对三类更新指标返回 `$null`，导致更新变慢不会进入异常告警。
- 仓库根存在大量 `acl-backup-git-*.txt` 运行态备份文件，说明默认备份路径需要收口。

## 变更

- `src/Commands/Doctor.ps1`
  - `update_vendor` 阈值改为 `60000ms`
  - `update_imports` 阈值改为 `180000ms`
  - `update_total` 阈值改为 `240000ms`
- `scripts/git-acl-guard.ps1`
  - 新增默认 ACL 备份根目录解析函数
  - 默认备份路径改为 `reports/runtime/acl-backups/acl-backup-git-<timestamp>.txt`
- `scripts/fix-git-acl.ps1`
  - 默认 ACL 备份路径改为 `reports/runtime/acl-backups/`
  - 缺失目录时自动创建
- `tests/Unit/DoctorPerf.Tests.ps1`
  - 更新阈值元数据断言
- `tests/Unit/DoctorEnhancements.Tests.ps1`
  - 更新 `update_*` 性能异常断言
- `tests/Unit/GitAclGuard.Tests.ps1`
  - 增加默认 ACL 备份目录断言

## 执行命令

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
./tests/run.ps1
```

## 关键证据

- `./build.ps1`
  - `Build success: D:\CODE\skills-manager\skills.ps1`
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - 通过，且性能摘要中已展示 `update_vendor` / `update_imports` / `update_total`
- `./skills.ps1 构建生效`
  - 通过，构建与目标同步完成
- `./tests/run.ps1`
  - 与本次修改直接相关的 `Doctor*` / `GitAclGuard` 测试通过
  - 全量 Pester 仍有既有失败：`AuditTargets.Tests`、`SkillAudit.Tests`、`MenuStructure.Tests`

## 替代验证 / N/A

- 无

## 回滚

- 回滚代码：
  - 撤销 `src/Commands/Doctor.ps1`
  - 撤销 `scripts/git-acl-guard.ps1`
  - 撤销 `scripts/fix-git-acl.ps1`
  - 撤销对应测试文件
- 回滚行为：
  - `doctor` 不再对 `update_*` 指标发出性能异常告警
  - Git ACL 备份重新写回仓库根
