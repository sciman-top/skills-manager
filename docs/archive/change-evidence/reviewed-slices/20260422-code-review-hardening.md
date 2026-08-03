# 20260422 code review hardening

## Scope
- 当前落点: `D:\CODE\skills-manager`
- 目标归宿: 提升并收敛共享配置契约校验、核心文件操作路径健壮性、doctor 日志摘要性能，并补齐 CI JSON 契约检查，保持 `skills.ps1`/`skills.json` 外部接口与数据格式兼容。
- 规则 ID: R1, R2, R3, R4, R5, R6, R7, R8, E4
- 风险等级: low

## Changes
- `src/Config.ps1`, `src/Commands/Doctor.ps1`: `doctor` 从仅验证 JSON 语法扩展为验证配置契约，新增非法相对路径、缺失字段、非法 mode/transport、缺失 MCP command/url 等阻断；配置契约校验收敛为共享只读函数 `Get-CfgContractErrors`，避免命令层重复实现。
- `src/Commands/Doctor.ps1`: 性能摘要改用 `List[object]` 避免数组反复复制。
- `src/Commands/Doctor.ps1`: `doctor --json` 改为静默探测 Git 版本，避免日志行污染机器可解析 JSON。
- `src/Core.ps1`, `src/Config.ps1`, `src/Commands/Install.ps1`: 关键删除、移动、缓存读取、目录指纹、配置读写改为 `-LiteralPath` 或字面量目录创建，避免路径中 `[]` 等通配符字符被误解析。
- `src/Commands/Install.ps1`: 抽出 `Get-AddImportPlanFromParsedArgs`，把 add/import 参数归一化从安装主流程中分离为纯计划函数，降低主函数职责密度。
- `.github/workflows/ci.yml`, `scripts/quality/check-doctor-json.ps1`, `scripts/quality/run-local-quality-gates.ps1`: 增加可复用的 `doctor --json` 机器可解析契约检查，并接入 GitHub CI；本地 quick gate 默认 CI 严格，可用 `-AllowDirtyWorktree` 验证开发态。
- `scripts/quality/check-repo-hygiene.ps1`: 修正仓库卫生规则，允许项目级 `AGENTS.md`/`CLAUDE.md`/`GEMINI.md` 作为受版本管理的规则文档。
- `tests/Unit/*.Tests.ps1`: 增加 add/import 计划函数、共享配置契约校验、`doctor` 契约失败、通配符字符路径移动/删除、目录指纹读取的回归测试。
- `skills.ps1`: 由 `./build.ps1` 从 `src/` 重新生成。

## Verification
- `codex --version`
  - exit_code: 0
  - key_output: `codex-cli 0.122.0`
- `codex --help`
  - exit_code: 0
  - key_output: help lists `exec`, `review`, `mcp`, `plugin`, `features`
- `codex status`
  - exit_code: 1
  - key_output: `Error: stdin is not a terminal`
  - platform_na: true
  - reason: 当前执行环境不是交互式 TTY，`codex status` 无法读取状态。
  - alternative_verification: `codex --version`, `codex --help`, active_rule_path=`D:\CODE\skills-manager\AGENTS.md`
  - evidence_link: this file
  - expires_at: 2026-05-22
- AST parse
  - cmd: PowerShell Parser.ParseFile over `skills.ps1`, `src/**/*.ps1`, and `scripts/quality/*.ps1`
  - exit_code: 0
  - key_output: `AST_PARSE_OK files=22`
- Targeted tests
  - cmd: `Invoke-Pester -Script tests\Unit\AddImportDefaults.Tests.ps1`
  - exit_code: 0
  - key_output: `Passed: 7 Failed: 0`
  - cmd: `Invoke-Pester -Script tests\Unit\ConfigUpdate.Tests.ps1`
  - exit_code: 0
  - key_output: `Passed: 16 Failed: 0`
  - cmd: `Invoke-Pester -Script tests\Unit\DoctorCli.Tests.ps1`
  - exit_code: 0
  - key_output: `Passed: 4 Failed: 0`
- Doctor JSON contract
  - cmd: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quality\check-doctor-json.ps1`
  - exit_code: 0
  - key_output: `doctor JSON contract check passed.`
- Local quality gates
  - cmd: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - exit_code: 0
  - key_output: `Local quality gates passed (quick).`
- Repository hygiene
  - cmd: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quality\check-repo-hygiene.ps1`
  - exit_code: 0
  - key_output: `Repository hygiene check passed.`
- Generated sync
  - cmd: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\check-generated-sync.ps1 -AllowDirtyWorktree`
  - exit_code: 0
  - key_output: `生成产物与当前 src 一致；skills.ps1 相对 HEAD 仍有未提交变更（开发态已放行）。`
- Diff whitespace
  - cmd: `git diff --check`
  - exit_code: 0
  - key_output: no whitespace errors; line-ending warnings only.
- Security/config scan
  - cmd: `rg -n "(?i)(api[_-]?key|password|secret|token|bearer|private[_-]?key)" --glob '!agent/**' --glob '!vendor/**' --glob '!imports/**' --glob '!reports/**' .`
  - exit_code: 0
  - key_output: matches are environment variable placeholders, tests using `unit-test-token`, docs, or token-related function names; no plaintext production secret identified.
- Dependency manifest scan
  - cmd: `rg --files -g "package.json" -g "package-lock.json" -g "pnpm-lock.yaml" -g "yarn.lock" -g "requirements.txt" -g "pyproject.toml" -g "go.mod" -g "Cargo.toml" -g "*.csproj" -g "Pipfile" -g "poetry.lock"`
  - exit_code: 0
  - key_output: manifests are under `imports/` third-party skill caches; no root project dependency manifest changed.
- Tracked runtime hygiene
  - cmd: `git ls-files | rg "^(agent|vendor|reports|\\.codex|\\.claude|\\.gemini|\\.trae)/|(^|/)build\\.log$|acl-backup-git-"`
  - exit_code: 1
  - key_output: no tracked runtime/cache/log paths matched.
- Full tests
  - cmd: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
  - exit_code: 0
  - key_output: Unit `Passed: 269 Failed: 0`; E2E `Passed: 9 Failed: 0`.
- Hard gates in fixed order
  - build: `./build.ps1` -> exit_code 0, `Build success: D:\CODE\skills-manager\skills.ps1`
  - test: `./skills.ps1 发现` -> exit_code 0, listed 96 skills.
  - contract/invariant: `./skills.ps1 doctor --strict --threshold-ms 8000` -> exit_code 0, `Your system is ready for skills-manager.`
  - hotspot: `./skills.ps1 构建生效` -> exit_code 0, `构建完成：agent/ (共 89 项技能)` and target links refreshed.

## Rollback
- Revert this change set for tracked files: `.github/workflows/ci.yml`, `skills.ps1`, `scripts/quality/check-repo-hygiene.ps1`, `src/Commands/Doctor.ps1`, `src/Commands/Install.ps1`, `src/Config.ps1`, `src/Core.ps1`, `tests/Unit/AddImportDefaults.Tests.ps1`, `tests/Unit/BuildCache.Tests.ps1`, `tests/Unit/ConfigUpdate.Tests.ps1`, `tests/Unit/Core.Tests.ps1`, `tests/Unit/DoctorCli.Tests.ps1`, plus new files `scripts/quality/check-doctor-json.ps1`, `scripts/quality/run-local-quality-gates.ps1`, and this evidence file.
- If already committed, use `git revert <commit>`.
- If not committed and rollback is explicitly requested, restore the listed files from `HEAD` and rerun the hard gates in the documented order.

## Notes
- No dependency changes.
- No public command names, `skills.json` schema, target path format, or generated skill directory format were changed.
