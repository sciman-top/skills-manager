# 2026-07-06 Gemini 与 Trae 卸载清理

- Rule IDs: `R1`, `R6`, `R8`, `E4`
- Risk: `medium`
- Current landing: `skills-manager` 本机宿主清理 + 仓库投影真源收口
- Target destination: 停止管理 `Gemini / Trae`，并清除本机与仓库残留，避免后续重新生成

## Repo Changes

- 从 `skills.json` 的 `targets` 中移除：
  - `~/.gemini/skills`
  - `~/.gemini/antigravity/skills/`
  - `~/.trae/skills/`
- 调整 `src/Commands/Mcp.ps1`：
  - 仅当配置中仍存在 `.trae` 目标时，才写项目级 `.trae/mcp.json`
- 更新 `tests/E2E/Workflow.Tests.ps1`：
  - 保留“存在 Trae target 时写项目级 `.trae/mcp.json`”断言
  - 新增“缺少 Trae target 时不写项目级 `.trae/mcp.json`”断言

## Host Cleanup

- 卸载 `Gemini` 全局 npm 包：`npm uninstall -g @google/gemini-cli`
- 删除用户级与程序级残留：
  - `C:\Users\sciman\.gemini`
  - `C:\Users\sciman\.trae`
  - `C:\Users\sciman\AppData\Roaming\Trae`
  - `C:\Users\sciman\AppData\Roaming\Trae CN`
  - `C:\Users\sciman\AppData\Local\Programs\Trae`
  - `C:\Users\sciman\AppData\Local\Programs\Trae CN`
  - `C:\Users\sciman\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Trae`
  - `C:\Users\sciman\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Trae CN`
  - `D:\CODE\skills-manager\.trae`

## Verification

- `./build.ps1`
  - `Build success: D:\CODE\skills-manager\skills.ps1`
- `Invoke-Pester -Path .\tests\E2E\Workflow.Tests.ps1`
  - `Tests Passed: 9, Failed: 0`
- `./skills.ps1 发现`
  - 通过
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - 通过；仅保留 `sync_mcp` 性能告警，不阻断
- `./skills.ps1 构建生效`
  - 通过；`targets=2`
- `./skills.ps1 同步MCP`
  - 仅同步 `Claude / Codex`
  - `已同步 MCP 服务配置到 3 个目标`
- 残留检查：
  - `gemini_command=false`
  - `trae_command=false`
  - `user_gemini_dir=false`
  - `user_trae_dir=false`
  - `program_trae_dir=false`
  - `program_trae_cn_dir=false`
  - `startmenu_trae_dir=false`
  - `startmenu_trae_cn_dir=false`
  - `repo_trae_dir=false`

## Rollback

- Repo rollback:
  - 恢复 `skills.json` 中的 `Gemini / Trae` targets
  - 恢复 `src/Commands/Mcp.ps1` 的项目级 Trae 默认写入逻辑
  - 恢复 `tests/E2E/Workflow.Tests.ps1`
- Host rollback:
  - 重新安装 `@google/gemini-cli`
  - 重新安装 `Trae / Trae CN`
  - 再执行 `./skills.ps1 构建生效`
  - 若需要 MCP 投影，再执行 `./skills.ps1 同步MCP`
