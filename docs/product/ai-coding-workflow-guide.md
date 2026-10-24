# AI 编码工作流与约束（参考件）

**定位**：本文件是参考件，不是规则、不是门禁，不进入任何宿主上下文。高频稳定闭环已提炼到默认投影的 `overrides/custom/ai-coding-workflow/SKILL.md`。本文合并原《AI 编码效能手册》与《通用指南》，取代二者。
**核实日期**：2026-10-18。外部依据见第 6 节；未核实原文的说法已单独标注。

## 1. 顶层宗旨

1. **先定验收，再动手**：写清 `Goal / Exact write set / Minimum proof / Stop`。
2. **删除优先于新增**：每个新增文件、门禁、测试或文档，都要说清当前调用方、替代或删除了什么、最小证明。
3. **用宿主原生能力，仓库只补真实缺口**：权限、sandbox、hook、subagent、plan mode、skills 先用宿主自带的。
4. **确定性强制优先于文字**：能用权限、hook、测试、CI 表达的约束，不写成提示词。
5. **证据先于断言**：给出命令、退出码与关键输出；未验证的明说。
6. **边界处校验一次**：外部输入在边界校验，内部信任已校验的数据。这是防止过度防御的核心。

Anthropic 的原则是"找到最简单的方案，只在必要时增加复杂度"（见第 6 节）。

## 2. 单任务流程

1. **分流**：一句话能描述 diff 的小改动直接做；否则先只读探索（plan mode，或范围明确的 subagent）。
2. **写契约**：目标、写集、最低证明、停止条件。
3. **小切片实现**：循环内跑相关测试；给 AI 一个它能自己运行的检查。
4. **按风险选最低充分证明**：文档只跑 `git diff --check`；行为变更跑 focused 测试；运行时、安全、数据、迁移类改动才跑一次 full。
5. **按风险审查**：风险、不确定性或项目契约需要时，用 fresh 上下文独立审查；只报影响正确性或已声明需求的问题，允许零发现。
6. **提交小 PR**：写清改动、证明与删除量，按当前项目的审阅和合入授权收口。
7. **复盘**：同一错误第二次出现，才把它转成 hook、权限或测试；否则不加规则。

上下文变得无关、混乱或任务明显切换时，再压缩或开启新会话；保留目标、决定、写集、有效证明和下一步。同一问题连续失败两次，先总结事实和缺口，再决定澄清、压缩或交接。

CLI 可通过 `skills.ps1 ai-coding --template implementation` 输出任务模板；另有 `review`、`failure`、`handoff`、`checklist`，支持 `--json`。该入口只输出模板，不扫描目标仓、不执行任务或调用模型。

验收预期应来自需求、示例或外部契约，关键回归在可行时确认旧行为会失败。UI 观察实际交互与空态/错误态；API 检查调用方兼容和错误响应；数据处理核对代表性输入与不变量；性能优化比较相同条件的前后结果。只选择本次适用的证明，不为低风险改动增加完整测试流程。

## 3. 防过度工程：提交前五问

1. 现在谁调用它？没有调用方就不做。
2. 它替代或删除了什么？优先净删除。
3. 宿主原生能力或已有函数能否满足？
4. 最小证明是什么？一条命令或一个观察即可。
5. 这个失败真实发生过吗？假设性失败不做防御。

## 4. 强制层级

越靠前越确定，应优先使用。

| 层 | 机制 | 适合 | 限制 |
| --- | --- | --- | --- |
| 1 宿主权限 | `permissions.deny`、`.codex/rules`、sandbox | 破坏性命令、写入边界 | 只挡已知形式 |
| 2 Hook | Claude `PreToolUse`（exit 2 或 `permissionDecision: deny`）、`Stop`（需设连续阻断上限）；Codex hooks 需 `/hooks` 信任 | 每次编辑的不变量、生成物保护 | Codex 官方称其为"护栏而非完整边界"，部分工具路径不走 hook |
| 3 脚本与测试 | focused 测试、`build.ps1 -Check` | 可执行的不变量 | 测试文字不等于行为 |
| 4 CI 与分支保护 | required check、差异检查 | 合并前裁决 | 只保护它覆盖的路径；solo 无人工批准，人工要读 diff |
| 5 AGENTS.md / SKILL.md 文字 | 偏好、流程、项目事实 | 无法机械化的判断 | 不能保证遵循，越长越被忽略 |

每条文字规则都问一句：能否降到上层？不能就删或缩短。删减检验：删掉这一行，AI 会不会犯错？不会就删。

## 5. 对本仓的落点

- 项目契约：根 `AGENTS.md`（5 节，约 45 行），只写仓库事实、不变量与门禁入口。
- 冻结面：PRD §3.1 为唯一清单，AGENTS.md 只指向它。
- 生成物：`build.ps1 -Check` 与 CI `-CheckGenerated`；hook 只是辅助，Bash 写入不受 hook 覆盖，最终裁决是 CI。
- 门禁：`scripts/quality/run-local-quality-gates.ps1`，选档以 `resolve-gate-profile.ps1` 为准。
- 已知缺口：Bash 写入生成物未被 hook 拦截；PR 章程仍为表单式校验（只查占位符，不查语义）。

## 6. 依据

- Claude Code hooks：33 个事件；`PreToolUse` 可用退出码 2 或 `permissionDecision: deny` 阻断；`Stop` 可阻止结束，需防循环。 <https://code.claude.com/docs/en/hooks>
- Claude Code 最佳实践：对 CLAUDE.md 每一行问"删掉会不会让 Claude 犯错"；验证应给 Claude 一个可运行的检查；subagent 审查 prompt 若要求"找缺口"，会诱发过度工程。 <https://code.claude.com/docs/en/best-practices>
- Anthropic，Building effective agents：找到最简单的方案，只在能明显改善结果时增加复杂度；抽象层可能遮蔽提示词。 <https://www.anthropic.com/engineering/building-effective-agents>
- Codex hooks：可通过 `permissionDecision: deny` 或退出码 2 阻断，项目 hook 需受信任后才加载；官方称其为"护栏而非完整强制边界"。 <https://learn.chatgpt.com/docs/hooks>
- Agent Skills 规范：`name` 与 `description` 必填；元数据常驻，正文按需加载；`SKILL.md` 建议不超过 500 行。 <https://agentskills.io/specification>
- 未核实原文：OpenAI 的 harness engineering 文章（"AGENTS.md 约 100 行地图"）。原文返回 403，仅见二手解读 <https://opensource.adobe.com/ai-repo-harness-guide/READING/>，不作为依据。
