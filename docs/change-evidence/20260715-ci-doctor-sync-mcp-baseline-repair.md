# CI doctor sync_mcp 基线修复

## 依据与边界

- `issue_id`: `ci-doctor-sync-mcp-missing-sample-20260715`
- 当前落点：GitHub Actions `CI / Verify doctor JSON contract` 在 clean runner 上连续失败，错误为 `doctor --json report misses sync_mcp metric in performance.summary.`
- 目标归宿：继续验证 `doctor --json` 结构，并只在存在真实 `sync_mcp` 样本时评价性能；clean CI 的无样本状态保持可见但不冒充性能失败。
- write-set：`.github/workflows/ci.yml`、`tests/run.ps1`、`README.md`、`README.en.md` 与本文件。
- 排除：不修改 `skills.json`、MCP server、auth/provider、用户配置、生成脚本或既有 governance PR #2。

## 根因与修复

- `doctor --json` 只从未跟踪的 `build.log` 汇总性能；clean GitHub runner 在 doctor 步骤前没有执行 `同步MCP`，因此不存在 `sync_mcp` 样本。
- workflow 却设置 `SKILLS_SYNC_MCP_THRESHOLD_MS=12000` 并以严格模式运行，导致无样本被当作回归。远端 `main=ae8a860` 与 governance PR head `4addb13` 均能稳定复现。
- CI 改用仓内既有 `-WarnOnly`：doctor JSON 结构仍为硬失败；缺样本或真实样本超阈值会形成 warning/observation。
- doctor 阻断移除后，clean runner 暴露出第二层继承型失败：GitHub 预装 Pester `5.7.1`，而仓内 466 个测试使用 Pester 4 语法。workflow 精确安装 `4.10.1`，测试入口也精确导入并校验该版本。
- 未选择在 CI 运行非 dry-run `同步MCP`，因为该命令会向 runner 用户目录投影 MCP 配置；未选择伪造性能记录，因为那不能证明真实耗时。

## 兼容性、风险与回滚

- 兼容性：`check-doctor-json.ps1` 的参数和 JSON 契约不变；本地或专用性能 lane 仍可不带 `-WarnOnly` 严格执行。测试继续使用仓库既有 Pester 4 语义，CI 供应链精确 pin `4.10.1`。
- 残余风险：普通 CI 不再把 `sync_mcp` 性能 observation 当阻断；若需要稳定性能 SLO，应新增具备隔离 HOME、真实样本与明确资源预算的专用 lane。
- 回滚：只回退本 write-set；不会触碰当前主工作树的 ahead 历史、dirty 文件或 governance PR 分支。

## 验证记录

- baseline：`HEAD=origin/main=ae8a8604b298d4261029fdf90ce9423db7c552dc`，隔离工作树从该 SHA 创建；父工作树既有 ahead/dirty 内容未进入本切片。
- red：`$env:SKILLS_SYNC_MCP_THRESHOLD_MS='12000'; pwsh -NoProfile -File scripts/quality/check-doctor-json.ps1`，exit `1`，关键输出为 `doctor --json report misses sync_mcp metric in performance.summary.`。
- green：同一 clean baseline 改用 `-WarnOnly`，exit `0`，缺样本以 warning 保持可见。
- remote red：PR #3 首轮 push/PR checks 的 doctor 步骤已通过，但 `Run tests` 在 Pester `5.7.1` 下分别以 454 Unit + 12 E2E 失败，exit `1`；失败均为版本不兼容症状而非业务断言回归。
- Pester pin green：`pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` 明确输出 `Pester Version: 4.10.1`，Unit 与 12 个 E2E 全部通过，exit `0`。
- build：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1`，exit `0`。
- test：`pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`，exit `0`；Unit 与 E2E 均通过。
- contract/invariant：`./skills.ps1 doctor --strict --threshold-ms 8000` 与 `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`，均 exit `0`。
- hotspot/full：Pester pin 后重新执行 `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`，exit `0`；关键输出为 `Pester Version: 4.10.1` 与 `Local quality gates passed (full).`。
- 五轴审查：correctness、readability、architecture、security、performance 均无 Critical/Required 问题；唯一残余项是普通 CI 只观察性能，已在上节显式记录。
- 发布后补录：PR URL、frozen head SHA、checks、merge SHA、fresh `origin/main` 与默认分支复测。
