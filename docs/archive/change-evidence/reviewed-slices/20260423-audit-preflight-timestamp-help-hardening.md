# 2026-04-23 审查目标链路加固（preflight + timestamp + help）

- rule_id: R1,R2,R6,R8
- risk_level: medium
- scope:
  - src/Commands/AuditTargets.ps1
  - src/Commands/AuditTargets.Apply.ps1
  - src/Commands/AuditTargets.Args.ps1
  - skills.ps1 (build 产物)

## 依据
- 旧 run 的 user-profile.json 存在 `last_structured_at` 为空未被 preflight 阶段明确提示。
- 时间戳在 JSON 反序列化后可能变为 `DateTime`，再次字符串化会漂移为区域格式。
- `审查目标 --help/帮助` 缺失，命令体验不一致。

## 变更
- 新增 `Convert-AuditTimestampToIso`，统一输出 ISO8601。
- `Import-AuditUserProfileStructured` 导入时间戳时统一标准化。
- `Get-AuditUserProfileOutput` 写 run 包时统一输出 ISO8601。
- `Invoke-AuditRecommendationsPreflight` 新增 `user-profile.json` 完整性校验并落入 `preflight-report.json`。
- `审查目标` 增加 `help/--help/-h/帮助` 子命令。

## 执行命令
- `./build.ps1`
- `./skills.ps1 审查目标 help`
- `./skills.ps1 审查目标 --help`
- `./skills.ps1 审查目标 帮助`
- `./skills.ps1 审查目标 预检 --run-id 20260422-234243-000`
- `./skills.ps1 审查目标 扫描 --target skills-manager`
- `./skills.ps1 发现`
- `./skills.ps1 doctor --strict --threshold-ms 8000`
- `./skills.ps1 构建生效`

## 关键证据
- preflight 现在会显示：`user_profile_invalid：user-profile.last_structured_at 无效 ...`
- 新 run `reports/skill-audit/20260423-010109-789/user-profile.json` 中 `last_structured_at` 为 ISO8601。
- `审查目标 help/--help/帮助` 均输出子命令帮助。
- 硬门禁顺序全通过：build -> 发现 -> doctor(strict) -> 构建生效。

## 回滚
1. `git checkout -- src/Commands/AuditTargets.ps1 src/Commands/AuditTargets.Apply.ps1 src/Commands/AuditTargets.Args.ps1 skills.ps1`
2. 删除新增证据文件：`docs/change-evidence/20260423-audit-preflight-timestamp-help-hardening.md`
