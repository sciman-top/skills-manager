# 20260422 local zip lock hardening

## Scope
- 当前落点: `D:\CODE\skills-manager`
- 目标归宿: 修复 `更新 -Plan` 的远端引用解析异常，补齐本地 zip/manual import 的锁定/校验/回放链路，并用回归测试覆盖真实 zip 重放场景。
- 规则 ID: R1, R2, R3, R5, R6, R7, R8
- 风险等级: low

## Findings
- `src/Commands/Update.ps1`
  - `Resolve-RemoteCommit` 使用 `("refs/tags/{0}^{}" -f $targetRef)`，PowerShell 格式化会把 `{}` 视为非法占位符，导致 `./skills.ps1 更新 -Plan` 可直接抛错。
- `src/Config.ps1`
  - 锁文件生成、校验、回放默认把 manual import 当成 git 仓库处理，遇到本地 zip 源时缺少稳定的源校验与回放分支。
  - `Apply-LockToWorkspace` 在 `update_force=false` 下不会重建既有本地 zip 缓存，导致锁定回放不成立。
  - 锁条目读取对 `OrderedDictionary` 兼容不足，影响内存态锁对象读取稳定性。
- `src/Commands/Update.ps1`
  - 并行预取会把非 git manual cache 也纳入任务，产生无效探测与噪音。
- 测试侧
  - 原有 zip 锁回放主要依赖 mock，缺少真实 rooted archive 的端到端回归用例。

## Changes
- `src/Commands/Update.ps1`
  - 过滤非 git cache，避免并行预取对本地 zip/manual 缓存做无效 git 操作。
  - 修正 tag dereference 格式串为 `^{{}}`。
  - 为本地 zip 更新源返回稳定的 `zip:<sha256>` 标识，避免计划模式走 git 远端分支。
- `src/Config.ps1`
  - 扩展 `Get-CfgObjectProperty`，兼容 `IDictionary`/`OrderedDictionary` 锁条目。
  - 新增 local zip 锁元数据分支：`source_kind`、`source_hash`、`workspace_fingerprint`。
  - `Assert-LockMatchesWorkspace` 对本地 zip 改为“源 zip 哈希 + 缓存内容指纹”校验。
  - `Apply-LockToWorkspace` 对本地 zip 回放强制重建缓存，并跳过 git checkout。
- `tests/Unit/ConfigUpdate.Tests.ps1`
  - 新增计划模式格式串回归、zip 远端解析回归、非 git cache 并行预取回归。
- `tests/Unit/Core.Tests.ps1`
  - 新增 local zip 锁元数据、源漂移、mock 回放、rooted archive 真实回放回归。
- `skills.ps1`
  - 由 `./build.ps1` 重新生成。

## Verification
- `codex --version`
  - exit_code: 0
  - key_output: `codex-cli 0.122.0`
- `codex --help`
  - exit_code: 0
  - key_output: help 正常输出
- `codex status`
  - exit_code: 1
  - key_output: `Error: stdin is not a terminal`
  - platform_na: true
  - reason: 当前环境非交互式 TTY。
  - alternative_verification: `codex --version`, `codex --help`, active_rule_path=`D:\CODE\skills-manager\AGENTS.md`
  - evidence_link: this file
  - expires_at: 2026-05-22
- 定向测试
  - cmd: `Invoke-Pester -Script .\tests\Unit\ConfigUpdate.Tests.ps1`
  - exit_code: 0
  - key_output: `Passed: 19 Failed: 0`
  - cmd: `Invoke-Pester -Script .\tests\Unit\Core.Tests.ps1`
  - exit_code: 0
  - key_output: `Passed: 129 Failed: 0`
- 全量测试
  - cmd: `./tests/run.ps1`
  - exit_code: 0
  - key_output: Unit `Passed: 276 Failed: 0`; E2E `Passed: 9 Failed: 0`
- 项目硬门禁（固定顺序）
  - build: `./build.ps1`
    - exit_code: 0
    - key_output: `Build success: D:\CODE\skills-manager\skills.ps1`
  - test: `./skills.ps1 发现`
    - exit_code: 0
    - key_output: 列出 96 项技能
  - contract/invariant: `./skills.ps1 doctor --strict --threshold-ms 8000`
    - exit_code: 0
    - key_output: `Your system is ready for skills-manager.`
  - hotspot: `./skills.ps1 构建生效`
    - exit_code: 0
    - key_output: `构建完成：agent/ (共 89 项技能)`
- 额外回归
  - cmd: `./skills.ps1 更新 -Plan`
  - exit_code: 0
  - key_output: `计划摘要：total=39, upgrade=10, unchanged=29`
- diff hygiene
  - cmd: `git diff --check`
  - exit_code: 0
  - key_output: 无 whitespace error；仅有 LF/CRLF warning

## Rollback
- 受影响文件: `src/Commands/Update.ps1`, `src/Config.ps1`, `tests/Unit/ConfigUpdate.Tests.ps1`, `tests/Unit/Core.Tests.ps1`, `skills.ps1`, 本证据文件。
- 若已提交，使用 `git revert <commit>`。
- 若未提交且明确要求回滚，恢复上述文件到 `HEAD`，再按 `./build.ps1 -> ./skills.ps1 发现 -> ./skills.ps1 doctor --strict --threshold-ms 8000 -> ./skills.ps1 构建生效` 复验。

## Notes
- 未引入新依赖。
- 未修改公开命令名、`skills.json` 配置格式、git import 兼容行为。
- `skills.lock.json` 对 local zip 条目新增 `source_kind/source_hash/workspace_fingerprint` 字段；现版本兼容既有 git 锁条目，但旧版本二进制若不了解 local zip 锁语义，可能无法正确重放这类新条目。
