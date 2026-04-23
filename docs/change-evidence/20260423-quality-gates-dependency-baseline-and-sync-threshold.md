# 2026-04-23 质量门禁加固：依赖基线校验 + sync_mcp 回归阈值

## 1) 依据
- issue_id: `quality-gates-dependency-baseline-sync-mcp-threshold-20260423`
- 当前落点:
  - `scripts/verify-dependency-baseline.py`
  - `scripts/quality/check-doctor-json.ps1`
  - `scripts/quality/run-local-quality-gates.ps1`
  - `.github/workflows/ci.yml`
  - `README.md` / `README.en.md`
  - `src/Commands/Utils.ps1`（帮助文本）
- 目标归宿:
  - 关闭依赖基线门禁缺失（补齐可执行脚本并接入本地/CI）
  - 在 CI 增加 `sync_mcp` 性能回归阈值告警/阻断能力
  - 文档化 MCP 与门禁相关环境变量，减少运维歧义

## 2) 问题 -> 修改 -> 收益 -> 风险 -> 回滚

### 2.1 依赖基线门禁只有模板命令，无可执行校验脚本
- 问题:
  - `.governed-ai/dependency-baseline.json` 的 `verify_command` 指向 `scripts/verify-dependency-baseline.py`，但仓内缺脚本实现。
- 修改:
  - 新增 `scripts/verify-dependency-baseline.py`，校验 baseline 文件存在性、字段完整性、时间格式、`verify_command` 合法性、`repo_id` 一致性。
  - `scripts/quality/run-local-quality-gates.ps1` 增加 `dependency-baseline` 门禁。
  - `.github/workflows/ci.yml` 增加 `Verify dependency baseline contract` 步骤。
- 收益:
  - 依赖基线门禁从“声明”变为“可执行”，本地与 CI 一致。
- 风险:
  - 依赖 Python 运行时；若缺失会导致门禁失败。
- 回滚:
  - 回退新增脚本与两处门禁接入改动。

### 2.2 CI 仅检查 doctor JSON 结构，不检查 sync_mcp 性能退化
- 问题:
  - 之前 `check-doctor-json.ps1` 只做契约校验，不能阻断 `sync_mcp` 慢回归。
- 修改:
  - `check-doctor-json.ps1` 新增 `SyncMcpThresholdMs`/`WarnOnly` 参数，并支持环境变量 `SKILLS_SYNC_MCP_THRESHOLD_MS`。
  - CI 的 doctor 校验步骤注入 `SKILLS_SYNC_MCP_THRESHOLD_MS=12000`。
- 收益:
  - CI 可检测并阻断 `sync_mcp` 回归（基于 `last_ms/avg_ms`）。
- 风险:
  - 若阈值过低可能引入噪声失败；当前值设为 `12000ms`。
- 回滚:
  - 移除阈值参数与 CI 环境变量，恢复纯契约校验。

### 2.3 MCP/门禁环境变量未系统文档化
- 问题:
  - 用户难以发现 `SKILLS_MCP_*`、`SKILLS_SYNC_MCP_THRESHOLD_MS` 等运行参数。
- 修改:
  - 更新 `README.md`、`README.en.md`。
  - 更新 `src/Commands/Utils.ps1` 帮助文本（并重建 `skills.ps1`）。
- 收益:
  - 运维与排障成本降低；参数语义对齐代码行为。
- 风险:
  - 文档维护成本略增。
- 回滚:
  - 回退文档与帮助文本改动。

## 3) 执行命令与关键输出

### 3.1 平台诊断
- `codex --version` -> `codex-cli 0.123.0`
- `codex --help` -> 帮助输出正常
- `codex status` -> `Error: stdin is not a terminal`（按 `platform_na` 记录）

### 3.2 关键验证
- `./build.ps1` -> `Build success`
- `python .\scripts\verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`
  - 输出：`dependency baseline verified: ...\.governed-ai\dependency-baseline.json`
- `$env:SKILLS_SYNC_MCP_THRESHOLD_MS='12000'; ./scripts/quality/check-doctor-json.ps1`
  - 输出：`doctor JSON contract check passed (sync_mcp threshold=12000ms).`
- `./scripts/quality/run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - 输出包含：
    - `== dependency-baseline ==`
    - `dependency baseline verified: ...`
    - `Local quality gates passed (quick).`

### 3.3 硬门禁与测试
- `./build.ps1` -> pass (`114ms`)
- `./skills.ps1 发现` -> pass (`1189ms`)
- `./skills.ps1 doctor --strict --threshold-ms 8000` -> pass (`1944ms`)
- `./skills.ps1 构建生效` -> pass (`7290ms`)
- `./tests/run.ps1` -> pass
  - Unit: `Passed: 302 Failed: 0`
  - E2E: `Passed: 10 Failed: 0`

## 4) N/A 记录

### 4.1 `platform_na`
- reason: `codex status` 需要交互终端，当前上下文为非交互 shell（`stdin is not a terminal`）
- alternative_verification: `codex --version` + `codex --help`
- evidence_link: 本文件 3.1
- expires_at: `2026-05-31`

## 5) 回滚动作
1. `git revert <本次提交SHA>`
2. 或最小回滚文件集合：
   - `scripts/verify-dependency-baseline.py`
   - `scripts/quality/check-doctor-json.ps1`
   - `scripts/quality/run-local-quality-gates.ps1`
   - `.github/workflows/ci.yml`
   - `README.md`
   - `README.en.md`
   - `src/Commands/Utils.ps1`
   - `skills.ps1`
