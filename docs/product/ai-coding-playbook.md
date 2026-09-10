# AI 编码效能手册（参考件）

**定位**：本文件是 reference，不是规则、不是门禁，也不以全文进入任何宿主上下文（AGENTS.md 与 rules/global 不引用它）。高频稳定的执行闭环已提炼到默认投影的 `overrides/custom/ai-coding-workflow/SKILL.md`；本文件保留完整映射、预算观测和模型分工背景。数字必须带来源与核实日期；与现行宿主文档冲突时以宿主文档为准。

## 1. 六杠杆 → 本仓机制映射

| 杠杆（官方共识） | 本仓机制锚点 |
| --- | --- |
| 上下文是第一资源，会腐烂；一会话一工作单元 | 全局规则受控投影 + `global-rules-check`（9.79 条目瘦身 -22%）；长调查派子代理，主上下文只留结论 |
| AGENTS.md/skills 短而准："删掉会致错吗"检验；重复犯错→retrospective→才入规则 | `src/Domain/SkillMetadata.ps1`（description≤1024、name≤64、frontmatter、块标量）；`RuleDiagnostics.ps1`（global 16384B/130 行、project 10240B/80 行 byte/line budget） |
| Prompt 四要素 Goal/Context/Constraints/Done-when | 根 AGENTS.md 日常合同：Goal / Exact write set / Minimum proof / Stop |
| 探索→计划→实现→提交；一句话能描述 diff 的小改动跳过计划 | 任务合同冻结 + plan 模式（宿主侧 `/plan`、Shift+Tab） |
| 给 agent 一个它能自己跑的验证；只认证据不认声明 | `scripts/quality/run-local-quality-gates.ps1`（与 CI 共享分类器）、`tests/run.ps1`、verification-before-completion skill |
| 重复工作三层沉淀：契约→AGENTS.md；方法→skill；已手工跑稳的流程→scheduled | 本仓即该杠杆的产品化；"手工未跑稳不定时化" |

## 2. 常见坑 → 防法 → 机制锚点

| 坑 | 防法 | 本仓锚点 |
| --- | --- | --- |
| 范围蔓延/过度设计 | 冻结 Goal/write set/Stop；审查 prompt 用 "Report gaps, not style preferences" | AGENTS.md B 节 not_admitted 准入门 |
| 长会话退化（重复犯错、忘约束） | 两次纠正失败→新会话+重写 prompt | 宿主侧行为；关键决策写文件不靠会话记忆 |
| 幻觉 API/最优主张 | 强制一手来源+核实日期 | references/reference-shelf 只读缓存政策、一手资料核实纪律 |
| 汇报与实态不符 | 只认命令输出；收口附 `git status` 快照 | verification-before-completion skill |
| 测试迁就实现 | 不许改测试迁就实现；行为变化显式走契约迁移 | 审计快照 fixture 契约迁移先例（stale_snapshot fail-closed） |
| 权限过大/并行互踩 | 默认最小权限、信任后再放开；并行用 git worktree | doctor config risks；scheduler 契约扫描（禁 RunLevel Highest）；git diff 分界并发改动 |
| 规则膨胀反噬 | 每条规则过"删掉会致错吗"；重复失效下沉机制层 | mechanism-over-prose 裁决；9.79 瘦身 |

## 3. 宿主元数据预算：观测口径

宿主侧预算事实（**带核实日期，复用前须复抓原文**）：

| 宿主 | 预算事实 | 来源与核实日期 |
| --- | --- | --- |
| Claude Code | 技能元数据约 1% 上下文预算 + 最少调用驱逐 + 长 description 1536 字符截断 | code.claude.com/docs/en/skills；2026-09-03 核实记录 |
| Codex | 技能/工具预算约 2% prompt，超限压缩/省略+警告；project_doc_max_bytes 默认 32KiB | github.com/openai/codex issue #19679；2026-09-03 核实记录 |
| ZCode | 固定元数据预算；description ≤1024 字符、正文 >100KB 截断 | 用户级 AGENTS.md 契约；2026-09-10 核对 |
| GLM（经由 Coding Plan） | GLM-5.3：1M 上下文；coding 建议 `reasoning_effort: "max"`、temperature 1.0；thinking 关→开须先设 enabled+effort 再改模型 ID | docs.z.ai/guides/llm/glm-5.3；2026-09-10 直抓 |

**测量法**（本仓 2026-09-10 起内建，纯观测、无阈值、不影响 pass）：

```
.\skills.ps1 capability-inventory --json
```

读 `data.metadata_budget[]`：每 surface 一行 `skill_count / measured_count / description_chars_total / description_chars_max / entrypoint_bytes_total / entrypoint_bytes_max`。口径约束：

- surfaces 相互重叠（同一技能可同时出现在 repo_supply / canonical_projection / user_skill_root / host_skill_roots / system / plugins），**行间不去重、不做总和**；跨宿主比较用 `canonical_projection`（去重的 canonical 集）作参考。
- `host_visible` 行来自宿主快照三文件合同，旧快照无新增量字段，`measured_count` 可为 0——这是如实覆盖标注，不是缺陷。
- 逐技能明细在 `data.surfaces[].items[]` 的 `description_chars` / `entrypoint_bytes`（UTF-8 字节，不含 BOM 修正）。

**"预算触界"退役判据的使用法**：把实载宿主 surface（如 user_skill_root 的 managed_current 子集）的聚合与上表预算对照；触界后走退役政策四判据流程（触发失准/上游废弃/预算触界/用户报告无价值），本手册不自动触发任何删除或裁剪。

## 4. GPT + GLM 双模型分工

- **契约写一次、两边吃**：AGENTS.md 是宿主中立开放规范（Codex/Claude Code/ZCode 同读）；稳定工程事实进 AGENTS.md，宿主差异进各自配置层。
- **分工而非二选一**：GLM 承接大批量机械任务与长程端到端任务（GLM-5.3 定位 long-horizon agent、多阶段任务收益最大、Coding Plan 非高峰点数半价）；GPT 高推理档承接架构决策、疑难 debug、安全审查。
- **交叉审查必须 fresh context**：新会话/子代理独立审再合并发现，防继承被审者盲区；审查输出要求 "Report gaps, not style preferences"。
- **资产积累节奏**：AI 同类错第 2 次→AGENTS.md 候选规则或 skill 候选（先过 retrospective + 准入门）；手动重复同一流程第 3 次→scheduled task 候选（先手工跑稳）。

## 5. 实践来源（直抓日期）

- Claude Code Best Practices — code.claude.com/docs/en/best-practices（2026-09-10；原 anthropic.com/engineering/claude-code-best-practices 308 重定向至此）
- Codex Best Practices — learn.chatgpt.com/guides/best-practices（2026-09-10）
- AGENTS.md 开放规范 — agents.md（2026-09-10）
- OpenAI Prompt Engineering Guide — developers.openai.com/api/docs/guides/prompt-engineering（2026-09-10）
- GLM-5.3 模型文档 / Coding Plan 端点 — docs.z.ai/guides/llm/glm-5.3、docs.z.ai/devpack/quick-start（2026-09-10）
