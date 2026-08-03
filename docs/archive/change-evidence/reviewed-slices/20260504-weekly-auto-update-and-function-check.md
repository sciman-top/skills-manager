# 2026-05-04 weekly auto update and function check

## 规则与风险
- 规则：R1/R2/R6/R8，项目硬门禁 `build -> test -> contract/invariant -> hotspot`。
- 当前落点：`D:\CODE\skills-manager`。
- 目标归宿：确认 weekly `更新 + 同步MCP` 是否真实定时执行，并修复实跑中发现的更新/MCP 校验问题。
- 风险等级：中。涉及本仓代码、导入 skill 指针，以及本机 Claude 原生 MCP 注册态。

## 定时任务证据
- 任务名：`skills-manager-weekly-update-friday-2000`
- Action：`pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "D:\CODE\skills-manager\scripts\weekly-auto-update.ps1"`
- 脚本动作：依次执行 `skills.ps1 更新` 与 `skills.ps1 同步MCP`。
- 触发器：每周 Friday 20:00，本机时间。
- 手动触发后状态：`LastRunTime=2026/5/4 23:19:43`，`LastTaskResult=0`，`NextRunTime=2026/5/8 20:00:00`，`NumberOfMissedRuns=0`，`State=Ready`。

## 实跑发现
- 直接执行 `scripts/weekly-auto-update.ps1` 成功，耗时约 412.8s；完成 `更新`、`构建生效`、`同步MCP`。
- `同步MCP` 写入 9 个目标：Claude/Codex/Gemini/Trae 的用户级配置、Gemini Antigravity、Codex `config.toml`、项目级 Trae MCP。
- 普通配置态校验通过：Claude/Codex/Gemini 均包含 `context7, github, microsoft-learn, openaiDeveloperDocs, playwright`。
- `Start-ScheduledTask` 手动触发成功，Task Scheduler 返回 `LastTaskResult=0`。
- `更新 -Plan` 初始发现误报；修复后结果为 `total=44, upgrade=0, unchanged=44`。
- 开启 live CLI MCP 校验后发现 Claude 原生 MCP 缺少 `openaiDeveloperDocs`；执行 `SKILLS_MCP_NATIVE_SYNC=1` 后补齐，Claude/Codex/Gemini live 校验全部通过。

## 修复内容
- `src/Commands/Update.ps1`
  - 非 git import cache 不再向上读取父仓库 HEAD；改为读取 `.skills-manager-source.json` 元数据。
  - archive/sparse import 更新后写入 source metadata；真实 git cache 清理该 metadata。
  - `Resolve-RemoteCommit` 优先查精确 `refs/heads/<ref>`，避免 `git ls-remote main` 被 `refs/heads/changeset-release/main` 等后缀匹配误导。
- `src/Commands/Mcp.ps1`
  - 外部命令超时包装器改用 `ProcessStartInfo.ArgumentList`，保证含空格的单个 argv 不被拆分。
  - 修复 Claude native MCP 注册 `Authorization: Bearer ...` header 被拆成多个参数的问题。
- `.gitignore`
  - 忽略 `/imports/**/.skills-manager-source.json`，避免运行态 source metadata 进入版本库。
- `skills.ps1`
  - 已由 `./build.ps1` 重新生成，保持与 `src/*` 同步。

## 验证命令
- `./skills.ps1 更新 -Plan`
  - 关键结果：`计划摘要：total=44, upgrade=0, unchanged=44`
- `./scripts/weekly-auto-update.ps1`
  - 关键结果：`更新` 与 `同步MCP` 均完成，9 个 MCP 目标写入成功。
- `Start-ScheduledTask -TaskName skills-manager-weekly-update-friday-2000`
  - 关键结果：`LastTaskResult=0`
- `$env:SKILLS_MCP_NATIVE_SYNC=1; $env:SKILLS_MCP_VERIFY_LIVE_CLI=1; ./skills.ps1 同步MCP`
  - 关键结果：Claude/Codex/Gemini live MCP 校验全部通过，`attempt=1/6`。
- `./scripts/quality/run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - 关键结果：`Local quality gates passed (quick).`
- `./tests/run.ps1`
  - 关键结果：Unit `354 passed`，E2E `11 passed`。
- `./build.ps1`
  - 关键结果：`Build success: D:\CODE\skills-manager\skills.ps1`
- `./skills.ps1 发现`
  - 关键结果：发现 87 个 skill。
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - 关键结果：`Your system is ready for skills-manager.`
  - 备注：开启 native/live MCP 后 `sync_mcp` 进入性能告警，但 `--strict` 不阻断；如启用 `--strict-perf` 需单独治理。
- `./skills.ps1 构建生效`
  - 关键结果：5 个 skills target junction 均已关联，构建输入未变化时 cache hit。
- `git diff --check`
  - 关键结果：exit 0；仅有 LF/CRLF 工作区提示。

## 回滚
- 本仓代码回滚：`git revert <this-commit>`，然后执行 `./build.ps1` 与本仓硬门禁。
- import 指针回滚：随同该 commit revert，恢复到更新前 gitlink。
- Claude 原生 MCP 回滚：如需撤销本次补齐，可执行 `claude mcp remove openaiDeveloperDocs --scope user`，随后执行不带 native 环境变量的 `./skills.ps1 同步MCP` 恢复配置文件态。
