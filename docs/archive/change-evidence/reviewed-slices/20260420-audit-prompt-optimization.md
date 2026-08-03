# 20260420-audit-prompt-optimization

- rule_id: R1,R2,R6,R8
- risk_level: low
- scope: `src/Commands/AuditTargets.ps1`（内置 AI 提示词三处增强） + `src/Commands/Utils.ps1`（帮助与菜单文案对齐） + `tests/Unit/AuditTargets.Tests.ps1` + `tests/E2E/SkillAudit.Tests.ps1` + `skills.ps1`（由 build 同步生成） + `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` + `README.md` / `README.en.md`
- current_anchor: `src/Commands/AuditTargets.ps1`
- target_destination: 保持审查链路不变，仅提升提示词可执行性/一致性

## Basis
- 用户要求：对项目中给 AI 代理的内置提示词做改进、完善、优化。
- 本次聚焦“实际生效链路”三处提示词：
  - `Get-DefaultAuditOuterAiPrompt`
  - `Write-AuditAiBrief`
  - `Write-AuditOuterAiPromptFile`
- 目标：在不改 schema 和命令语义前提下，降低外层 AI 漏项与越序执行风险。

## Changes
1. 强化默认外层 AI 提示词：
   - 明确 `do_not_install` / `overlap_findings` 的职责边界；
   - 增加 `N/A` 输入路径语义、阻断条件、占位符清理、自检失败即停；
   - 明确 dry-run 汇报必须保留原始序号并展示双理由。
2. 强化 `ai-brief.md`：
   - 增加 blocker 处理、真实来源约束、`decision_basis` 布尔约束；
   - 增加 `<...>` 占位符清理、`install.mode` / `confidence` 合法值约束；
   - 增加统一的 dry-run 用户汇报格式。
3. 强化运行态 `outer-ai-prompt.md` 包装文案：
   - 增补 Blocking Conditions；
   - 增补 User Summary Format；
   - 把“写 JSON -> 自检 -> dry-run -> 等待确认”写成显式顺序。
4. 新增回归测试，锁定上述提示词约束在源码和生成包中持续存在。
5. 同步优化仓库级代理规则文件：
   - 明确 `reports/skill-audit/<run-id>/ai-brief.md` 与 `outer-ai-prompt.md` 是运行态产物，禁止直接手改；
   - 明确提示词源码与默认覆写入口分别位于 `src/Commands/AuditTargets.ps1` 与 `overrides/audit-outer-ai-prompt.md`。
6. 同步优化 README 中的外层 AI 交接说明：
   - 把“先自检，再 dry-run，再按原序号汇报”写入中英文文档；
   - 同步调整脚本扫描结束后的下一步提示文案。
7. 同步优化 `Utils` 帮助源与菜单：
   - 帮助正文明确“交给外层 AI 后先写并自检 recommendations，再 dry-run”；
   - 菜单文案明确“按原序号选择增删”，避免与重排/映射产生歧义；
   - 帮助正文补充“运行态提示词产物不可直接手改，源码在 `src/Commands/AuditTargets.ps1` / `overrides/audit-outer-ai-prompt.md`”。
8. 统一 `AuditTargets` 控制台输出术语：
   - `审查建议摘要` 增加“原序号”提示；
   - 空列表统一输出“无新增建议 / 无卸载建议”；
   - dry-run 阶段明确“沿用原序号”；
   - 两阶段流程结束语统一为“应用确认结束”。

## Commands
1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`
5. `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Unit/AuditTargets.Tests.ps1'"`
6. `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/E2E/SkillAudit.Tests.ps1'"`
7. `codex --version`
8. `codex --help`
9. `codex status`

## Key Output
- build: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- test(发现): 成功输出技能清单，exit_code=0
- contract/invariant(doctor): `Your system is ready for skills-manager.`
- hotspot(构建生效): `=== 构建生效流程完成 ===`
- unit test: `Passed: 43 Failed: 0`
- e2e test: `Passed: 2 Failed: 0`
- codex --version: `codex-cli 0.121.0`
- codex --help: 成功返回命令帮助，exit_code=0
- scan bundle next-step message: `AI 应先填写并自检 recommendations.json，再执行 dry-run，并按原序号列出新增/卸载清单。`

## N/A
- type: `platform_na`
- item: `codex status`
- reason: 当前非交互终端环境，命令返回 `stdin is not a terminal`
- alternative_verification: 使用 `codex --version` + `codex --help` + 本地规则与门禁证据补齐平台诊断
- evidence_link: `docs/change-evidence/20260420-audit-prompt-optimization.md`
- expires_at: `2026-04-27`

- type: `gate_na`
- item: `supply_chain_gate`
- reason: 本次仅修改提示词文本与生成脚本文案，无依赖/锁文件变更
- alternative_verification: 全链路门禁 + 定向单测 + diff 人工审查
- evidence_link: `docs/change-evidence/20260420-audit-prompt-optimization.md`
- expires_at: `2026-04-27`

## Rollback
1. 回退文件：`src/Commands/AuditTargets.ps1`、`skills.ps1`
2. 重新生成：`./build.ps1`
3. 复验门禁：`./skills.ps1 发现` -> `./skills.ps1 doctor --strict --threshold-ms 8000` -> `./skills.ps1 构建生效`
