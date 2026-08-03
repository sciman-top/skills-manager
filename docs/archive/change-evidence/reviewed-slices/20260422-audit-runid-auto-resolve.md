# 2026-04-22 audit run-id auto resolve

## 变更范围
- 将审查流程中的 `<run-id>` 占位符从“直接阻断”调整为“自动解析最近可用 run-id（若存在）”。
- 覆盖入口：
  - `--run-id`
  - `--recommendations` 路径中的 `<run-id>`
  - 预检阶段的 run-id / recommendations 解析

## 依据
- 用户要求先输出适用于 Codex/Claude 的短提示词，再优化代码以支持自动执行。
- 真实阻断原因：占位符 `<run-id>` 在参数解析阶段直接报错，无法自动推进。

## 代码落点
- `src/Commands/AuditTargets.ps1`
  - 新增 `Get-AuditLatestRunId`
  - 新增 `Resolve-AuditRunIdInput`
  - 新增 `Resolve-AuditPathRunIdPlaceholder`
- `src/Commands/AuditTargets.Args.ps1`
  - `--run-id` 改为调用 `Resolve-AuditRunIdInput`
  - `--recommendations` 改为调用 `Resolve-AuditPathRunIdPlaceholder`
- `src/Commands/AuditTargets.Apply.ps1`
  - `Resolve-AuditRecommendationsPathForPreflight` 改为支持 `<run-id>` 自动解析
- `src/Commands/Utils.ps1`
  - 帮助文案更新为“自动解析最近 run”
- `tests/Unit/AuditTargets.Tests.ps1`
  - 新增 `<run-id>` 自动解析相关测试

## 验证命令与结果
- `./build.ps1`：通过
- `Invoke-Pester -Path 'tests/Unit/AuditTargets.Tests.ps1'`：通过（55 passed, 0 failed）
- `./skills.ps1 发现`：通过
- `./skills.ps1 doctor --strict --threshold-ms 8000`：通过
- `./skills.ps1 构建生效`：通过

## 回滚
- 回滚上述文件到变更前版本即可恢复“占位符直接阻断”行为。
