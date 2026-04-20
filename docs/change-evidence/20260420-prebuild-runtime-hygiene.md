# 20260420-prebuild-runtime-hygiene

- rule_id: R1,R2,R4,R6,R8
- risk_level: low
- scope: `.gitignore`, `scripts/prebuild-check.ps1`, `scripts/cleanup-runtime.ps1`
- current_anchor: `scripts/prebuild-check.ps1`
- target_destination: 让预检可执行、运行态产物可控，不改变现有命令接口与配置语义

## Basis
1. 构建/更新阶段此前长期输出“未找到预检脚本，跳过”，缺少可执行预检入口。
2. 运行态会产出 `docs/runtime-*.txt` 与 `reports/` 内容，造成工作区噪音。

## Changes
1. 新增 `scripts/prebuild-check.ps1`：
   - 检查关键文件存在；
   - 按 `LoadCfg` 兼容规则解析 `skills.json`（支持整行 `//` 注释）；
   - 默认轻量检查，`-Strict` 时扩展关键源码存在性校验；
   - 失败返回 exit 2，供调用方阻断。
2. 新增 `scripts/cleanup-runtime.ps1`：
   - 默认清理 `docs/runtime-adapter-events-sm-*.txt`、`docs/runtime-auto-write-sm-*.txt`；
   - 仅在显式 `-IncludeReports` 时清理 `reports/` 下内容。
3. 更新 `.gitignore`：
   - 新增 `/reports/` 与 `/docs/runtime-*.txt`。

## Commands
1. `./scripts/cleanup-runtime.ps1`
2. `./build.ps1`
3. `./skills.ps1 发现`
4. `./skills.ps1 doctor --strict --threshold-ms 8000`
5. `./skills.ps1 构建生效`
6. `./tests/run.ps1`
7. `codex --version`
8. `codex --help`
9. `codex status`

## Key Output
- cleanup: `Cleanup complete. Removed items: 3`
- gate(build): `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- gate(test): `./skills.ps1 发现` 成功输出技能清单，exit_code=0
- gate(contract/invariant): `Your system is ready for skills-manager.`
- gate(hotspot): 预检脚本被执行并输出 `[prebuild] done`
- tests: Unit `Passed: 223 Failed: 0`，E2E `Passed: 9 Failed: 0`
- codex --version: `codex-cli 0.121.0`
- codex --help: 返回帮助成功，exit_code=0

## N/A
- type: `platform_na`
- item: `codex status`
- reason: 非交互终端，返回 `stdin is not a terminal`
- alternative_verification: `codex --version` + `codex --help` + 全门禁链 + 全量测试
- evidence_link: `docs/change-evidence/20260420-prebuild-runtime-hygiene.md`
- expires_at: `2026-04-27`

- type: `gate_na`
- item: `supply_chain_gate`
- reason: 本次未新增/升级依赖，无供应链输入变化
- alternative_verification: 全量测试 + 门禁链 + diff 审核
- evidence_link: `docs/change-evidence/20260420-prebuild-runtime-hygiene.md`
- expires_at: `2026-04-27`

## Rollback
1. 删除新增文件：`scripts/prebuild-check.ps1`、`scripts/cleanup-runtime.ps1`。
2. 回退 `.gitignore` 的本次新增规则。
3. 复验：`./build.ps1` -> `./skills.ps1 发现` -> `./skills.ps1 doctor --strict --threshold-ms 8000` -> `./skills.ps1 构建生效`。
