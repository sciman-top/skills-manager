# AI 编码效能手册（参考件）

**定位**：本文件是 reference，不是规则、不是门禁，也不以全文进入任何宿主上下文（AGENTS.md 与 rules/global 不引用它）。高频稳定的执行闭环已提炼到默认投影的 `overrides/custom/ai-coding-workflow/SKILL.md`；本文件保留完整映射、预算观测和模型分工背景。数字必须带来源与核实日期；与现行宿主文档冲突时以宿主文档为准。

## 1. 六杠杆 → 本仓机制映射

| 实践取舍 | 本仓机制锚点 |
| --- | --- |
| 上下文保持相关；一个任务围绕一个可验收目标 | `ai-coding-workflow` 第 3 节：重读当前事实、按需用短胶囊交接；独立调查仅在授权且并行净收益为正时委派 |
| AGENTS.md/skills 短而准："删掉会致错吗"检验；重复犯错→retrospective→才入规则 | `src/Domain/SkillMetadata.ps1`（description≤1024、name≤64、frontmatter、块标量）；`RuleDiagnostics.ps1`（global 16384B/130 行、project 10240B/80 行 byte/line budget） |
| Prompt 四要素 Goal/Context/Constraints/Done-when | 根 AGENTS.md 日常合同：Goal / Exact write set / Minimum proof / Stop |
| 探索→计划→实现→提交；清晰的小改动直接推进 | `ai-coding-workflow` 的 tiny/direct、normal、high-risk；宿主计划入口以当前可用工具为准 |
| 给 agent 一个它能自己跑的验证；只认证据不认声明 | `scripts/quality/run-local-quality-gates.ps1`（与 CI 共享分类器）、`tests/run.ps1`、verification-before-completion skill |
| 重复工作三层沉淀：契约→AGENTS.md；方法→skill；已手工跑稳的流程→scheduled | 本仓即该杠杆的产品化；"手工未跑稳不定时化" |

## 2. 常见坑 → 防法 → 机制锚点

| 坑 | 防法 | 本仓锚点 |
| --- | --- | --- |
| 范围蔓延/过度设计 | 冻结 Goal/write set/Stop；审查 prompt 用 "Report gaps, not style preferences" | AGENTS.md B 节执行边界与现有 review skill |
| 长会话退化（重复犯错、忘约束） | 同一问题失败两次后整理事实、假设和尝试，澄清缺口；历史误导时换新上下文 | 宿主侧行为；复用已有任务记录，不另建状态库 |
| 幻觉 API/最优主张 | 强制一手来源+核实日期 | references/reference-shelf 只读缓存政策、一手资料核实纪律 |
| 汇报与实态不符 | 命令、界面或请求链证据必须直接支持对应结论；Git 状态只说明文件变更 | verification-before-completion skill；本文第 8 节 |
| 测试迁就实现 | 不许改测试迁就实现；行为变化显式走契约迁移 | 审计快照 fixture 契约迁移先例（stale_snapshot fail-closed） |
| 权限过大/并行互踩 | 默认最小权限、信任后再放开；并行用 git worktree | doctor config risks；scheduler 契约扫描（禁 RunLevel Highest）；git diff 分界并发改动 |
| 规则膨胀反噬 | 每条规则过"删掉会致错吗"；重复失效下沉现有脚本或测试 | AGENTS.md 源文件与最低门禁约定；已有 quality scripts |
| 逐步微管理、盯着 agent 看 | 单主执行者自主完成闭环；仅在已授权、写集互斥、能独立验证且净收益为正时并行 | ai-coding-workflow skill 的执行姿态与 task-fit 节 |
| 做错目标或自证正确 | 用具体用户操作定义验收；重要改动独立复核需求、diff、反例 | 任务合同与已有 review skill |
| 看不到真实行为 | 按受影响行为选观察证据；缺失时报告未验收边界 | 本文第 8 节；已有测试、日志和宿主工具 |
| 审查诱发过度设计（gap-hunting） | 审查者只报正确性/相关问题，不给风格与"可改进"建议；fresh context 审查 | ai-coding-workflow 第 2 节；本文 5.3 审查模板 |
| 缺少 build/test 命令 | 入口与最低门禁命令写进项目 AGENTS.md | 根 AGENTS.md 第 1 节 entrypoint、C 节最低门禁 |
| 将输入或工具故障误判为模型推理不足 | 分别检查输入、工具执行、认证、额度、端点与协议；证据不足时不改模型配置 | 本文第 4 节；宿主当前工具输出与官方配置说明 |

## 3. 宿主元数据预算：观测口径

宿主侧预算事实（**带核实日期，复用前须复抓原文**）：

| 宿主 | 预算事实 | 来源与核实日期 |
| --- | --- | --- |
| Claude Code | 技能元数据约 1% 上下文预算 + 最少调用驱逐 + 长 description 1536 字符截断 | code.claude.com/docs/en/skills；2026-09-03 核实记录 |
| Codex | 技能/工具预算约 2% prompt，超限压缩/省略+警告；project_doc_max_bytes 默认 32KiB | github.com/openai/codex issue #19679；2026-09-03 核实记录 |
| ZCode | 固定元数据预算；description ≤1024 字符、正文 >100KB 截断 | 用户级 AGENTS.md 契约；2026-09-10 核对 |
| GLM-5.3-Flash | 官方建议 `temperature: 1`、`top_p: 0.95`、`reasoning_effort: max`；`thinking.type` 仅支持 `enabled`，建议 `thinking.clear_thinking: false`。这些是模型 API 建议，不能据此假定 ZCode 或其他宿主暴露同名配置，也不能作为其他 GLM 型号的统一参数 | [官方模型页](https://docs.z.ai/guides/vlm/glm-5.3-flash)；2026-09-13 直抓 Markdown 原文复核 |

**测量法**（本仓 2026-09-10 起内建，纯观测、无阈值、不影响 pass）：

```
.\skills.ps1 capability-inventory --json
```

读 `data.metadata_budget[]`：每 surface 一行 `skill_count / measured_count / description_chars_total / description_chars_max / entrypoint_bytes_total / entrypoint_bytes_max`。口径约束：

- surfaces 相互重叠（同一技能可同时出现在 repo_supply / canonical_projection / user_skill_root / host_skill_roots / system / plugins），**行间不去重、不做总和**；跨宿主比较用 `canonical_projection`（去重的 canonical 集）作参考。
- `host_visible` 行来自宿主快照三文件合同，旧快照无新增量字段，`measured_count` 可为 0——这是如实覆盖标注，不是缺陷。
- 逐技能明细在 `data.surfaces[].items[]` 的 `description_chars` / `entrypoint_bytes`（UTF-8 字节，不含 BOM 修正）。

**退役取舍**：预算触界、触发失准、上游废弃或用户报告无价值是检查入口，不是按品牌整批删除的依据。先区分默认可见、按需加载和仅保留在仓库的供给；冷技能仍有更新维护成本，但不能把其全文字节数当作每轮实际上下文。删除前检查当前调用方、独有能力和依赖闭包；没有消费者或独有用途的条目才进入现有删除流程，不新增退役状态库。

- 通用工作流只补当前宿主与项目契约的真实缺口；重复的计划、访谈、逐任务代理和验证接力优先去掉。明确需要的严格 TDD、设计访谈仍按需保留。
- 测试保留行为、历史回归和授权/数据边界证明；审查复制实现、重复文案断言与重复验证层，不能只按测试数量裁剪。现有分类器的未知源码回退须在确认受影响测试后才收窄，不用模型能力替代覆盖证据。
- MCP 按数据、操作或观察能力取舍：已有等价宿主工具时避免重复接入；模型升级本身不能替代工具访问。源配置、宿主实际启用与真实调用分别核验。
- 效益比较复用第 7 节的真实任务记录；没有可比样本时只报告指令或执行步骤的减少，不宣称生产效率已经提升。

## 4. GPT + GLM 按任务选择

- **共享工程事实，分别核验加载**：本仓以 AGENTS.md 维护项目规则，Claude 通过 wrapper 引用；各宿主发现、继承和工具能力不同，不能用文件相同证明规则已加载。
- **一个任务由一个主代理负责到底**：普通任务优先使用已有上下文且成本、延迟合适的一方。GPT 做架构或疑难诊断、GLM 做批量或长程实现，可以作为待验证的选择假设；不固定为“GPT 设计 → GLM 编码 → GPT 审查”。第 7 节说明实际效果的观察方式。
- **按不确定性增加推理投入**：复杂取舍、跨模块故障、并发和安全问题可选更强推理档位；准确档位取决于当前模型、接口与宿主支持。缺少代码、复现或可运行环境时先补齐证据。
- **模型能力与执行环境分别确认**：普通对话、可访问工作区的 Codex 执行环境与 ZCode 工具链按当前会话事实选择。界面任务需要实际渲染和交互证据，交付任务需要请求到效果的证据。
- **有需要才独立审查**：重要改动使用新上下文或已授权代理，从需求、diff 和测试寻找反例；第二个模型同意不构成验证。低风险小改动不强制跨模型接力。

遇到“模型答得不好”时，先按观察到的故障选取检查，不例行扫描全部配置：

| 观察到的失败 | 先核查的事实 | 后续动作 |
| --- | --- | --- |
| 忽略图片或日志内容 | 当前请求是否实际包含输入、接口是否支持该输入 | 补齐有效输入；不要凭模型名称推断视觉能力 |
| 工具未执行或返回错误 | 当前宿主工具是否可用、命令与原始错误 | 修复已授权的工具调用路径，再判断模型推理 |
| 认证、限流或参数错误 | 脱敏错误、额度、端点用途、协议与支持参数 | 对照当前官方说明；配置变更仍按明确授权处理 |
| 输入与工具正常但方案反复错误 | 复现、被排除的假设、需求和验收是否冲突 | 重新诊断，必要时提高推理投入或交接其他模型 |

ZCode 的 Coding 套餐端点与通用 API 端点不能互换；参数和图片能力也不能仅凭模型名称推断。配置事实应查当前[官方说明](https://zcode.z.ai/cn/docs/configuration)，不在本手册复制密钥、账号或临时配置。

## 5. 可直接复制的任务模板

以下模板是输入辅助，不是新的规则或授权层。把占位内容换成当前任务事实；
跨宿主交接时传递任务胶囊，不复制整段历史对话。

### 5.1 普通实现或修复

```text
$ai-coding-workflow
Goal: <要实现或修复的用户可见结果>
Context: <仓库根、相关文件/模块、当前错误或复现步骤>
Constraints: <兼容性、不得触碰的目录、秘密和并发改动约束>
Exact write set: <允许修改的精确文件/目录>
Minimum proof: <build、受影响测试、contract 或其他最低充分验证>
Stop: <达到什么条件后停止，不做额外重构>

先读取当前 git status、相关源码和测试；如果事实不足，先报告缺口。
完成后报告改动、验证结果和剩余限制；仅在涉及投影或实际运行时区分
repo_verified / filesystem_projected / host_loaded / live_accepted，
不要把低层证明当成高层验收，也不要无条件增加四层工作。
```

用户不必预先知道精确文件或验证命令：可以只给目标、现场、约束和验收结果，
由执行者调查后确定写集和最低验证。字段用于固定执行边界，不应成为例行审批表。

### 5.2 GPT/Codex 与 GLM/ZCode 双向交接

```text
Task capsule:
Goal: <目标>
Current status/evidence: <仓库路径、分支、commit、未提交修改与归属、关键证据>
Decisions already made: <已确定的接口、行为和取舍>
Exact write set: <精确写集>
Remaining work: <尚未完成的实现、验证或阻塞>
Minimum proof: <最低验证>
Stop: <停止条件>

请重新读取当前仓库状态与相关改动，再在上述写集内推进剩余工作。
不要根据模型名称猜测 API、provider、权限或宿主能力；不要扩大写集。
如果发现契约冲突或真实失败与胶囊不符，先停下并报告证据。
```

### 5.3 Fresh-context 审查

```text
请只审查当前 diff/commit 的正确性、回归、安全、兼容和测试充分性。
先读取需求、当前仓库状态、实际源码、相关测试和项目规则。
Report gaps, not style preferences；不要为了提出建议而扩大范围。
只报告可由证据支持的 actionable findings，标明文件、触发条件、影响
和验证办法；实现者的总结只作为线索。没有发现问题时明确说明。
除非明确授权，不修改文件。
```

同一模型可以完成以上各类任务；模板不要求跨模型交接或自动故障切换。

## 6. 实践来源（直抓/复核日期）

- Claude Code Best Practices — code.claude.com/docs/en/best-practices（2026-09-10 直抓、2026-09-12 复核，新增可见面=/goal+Stop hook 四档验证门禁、/batch、gap-hunting 审查警告；原 anthropic.com/engineering/claude-code-best-practices 308 重定向至此）
- Codex Best Practices — learn.chatgpt.com/guides/best-practices（2026-09-10 直抓、2026-09-12 复核，新增可见面=extra-high 档、/fork、子目录 AGENTS.md nearest-wins）
- AGENTS.md 开放规范 — agents.md（2026-09-10）
- OpenAI Prompt Engineering Guide — developers.openai.com/api/docs/guides/prompt-engineering（2026-09-10）
- GLM-5.3 模型文档 / Coding Plan 端点 — docs.z.ai/guides/llm/glm-5.3、docs.z.ai/devpack/quick-start（2026-09-10 直抓、2026-09-12 复核）
- GLM-5.3-Flash（VLM 分区）— docs.z.ai/guides/vlm/glm-5.3-flash（2026-09-12 直抓；旧 /guides/llm/ 路径 308 重定向至此）
- GitHub Spec Kit（社区参考：spec-driven development，converge 反向收敛核对，30+ agent 可用）— github.com/github/spec-kit（raw README 2026-09-12）
- Superpowers（社区参考：方法论即 skills；与本仓 systematic-debugging/verification-before-completion 同名同构，可定期对照演进）— github.com/obra/superpowers（raw README 2026-09-12）

2026-09-13 读取原文后采纳的实践：[OpenAI 提示指南](https://learn.chatgpt.com/docs/prompting)用于目标、上下文、边界和验证模板；[ZCode 介绍](https://zcode.z.ai/cn/docs/welcome)与[模型配置](https://zcode.z.ai/cn/docs/configuration)用于区分模型和执行环境；[Aider](https://aider.chat/docs/usage/tips.html)用于相关上下文和小步修改；[Spec Kit](https://github.com/github/spec-kit)与[Superpowers](https://github.com/obra/superpowers)用于需求澄清、系统诊断和验收思路。这里只采纳适用方法，不引入整套框架或安装依赖。

## 7. 日常执行与反馈

默认单主执行者完成“理解目标 → 检查当前事实 → 实现 → 验证 → 收口”。用户提供业务取舍和可观察结果，AI 调查文件、调用链与命令；复杂或模糊任务先校准方案，小改动直接推进。执行中发现独立新问题只报告，不自动吸收。

`Goal / Exact write set / Minimum proof / Stop` 中的 Goal 和 Stop 对应整体授权目标。切片仅用于分步实现与验证，通过后继续剩余已授权工作，不能把一份方案、文档或一次测试通过当作全部完成。续做或交接保留已完成项、未完成项与有效证据；某项受阻时继续其他独立工作，最终明确剩余阻碍。只重跑输入变化导致失效的证明。

流程深度与诊断需求分别判断：`tiny/direct` 可以包含低风险且可复现的小 bug；根因不明时使用诊断技能，安全、数据或部署等高影响变化才按 `high-risk` 执行目标仓的额外保障。已获授权在当前范围内持续有效，外部动作不自动触发重复确认。各仓自行定义源文件与生成物，不按 `agent/` 等目录名套用本仓限制；新增结构可以服务明确的新功能，无须虚构故障。

技能只约束当前需要的决策，不重复全局规则和专项流程；描述与默认提示词用于发现和启动。验收分层仅在相关时汇报。模型升级后的精简先检查歧义、重复、误触发与替代能力，保持既有轻量 profile；没有依赖和实际使用证据时不批量删除技能库存或 MCP 定义。

- 上下文以当前相关源码、复现步骤、日志和参考实现为主；旧对话作为线索，既有决定和验证结果用短交接胶囊传递。
- 普通任务由 GPT 或 GLM 完整承担；模型分工是可调整的假设。以任务难度、工具可用性、总耗时和返工选择配置，避免每一步跨宿主交接。
- 重要改动的独立审查从需求、diff 和相关测试寻找反例；报告触发条件、影响与证据。第二个模型的同意不能替代验证。
- 失败用原始错误和当前状态反馈。同一问题连续失败两次，先整理已证实事实、失败尝试和未决问题，再决定澄清或换上下文；不盲目连续打补丁。
- 效率观察复用已有任务/PR记录，按需附一行：`任务类型 | 宿主/模型 | 一次验收通过与否 | 总耗时 | 人工纠错时间 | 验收后缺陷 | 可取得的费用或额度消耗`。优先看每个验收通过任务的综合成本；不可取得的数据标未知，失败任务的耗时与成本也计入。可在后续两周真实任务中积累可比样本，模型或宿主大版本变化后再抽样复测；这不是定时任务、门禁或本次交付的等待条件。不据少量非对照样本宣称模型优劣，不新建遥测或自动评分系统。

## 8. 按行为选择观察能力

下表是验收选项，不是每个项目的必跑清单。只选择能证明当前改动的行与检查；权限、数据与外部副作用仍服从当前任务范围。

| 受影响行为 | 优先复用的观察入口 | 要证明的结果与限制 |
| --- | --- | --- |
| Web/前端交互 | 开发服务器、浏览器、截图、控制台、现有交互测试 | 页面可见且操作路径正确；相关窄屏/错误状态得到验证，编译成功不能替代 |
| WPF/桌面/输入集成 | 实际窗口、焦点和输入事件、生命周期日志、目标设备 | 受影响的触控、焦点、多屏或关闭行为；无设备时明确硬件验收未完成 |
| API/服务/机器人交付 | 请求标识、入口到外部效果的日志、测试服务、实际 ACK | 当前超时/重试/幂等/交付行为；mock、HTTP 200 或健康探针不等于真实交付 |
| 自动化/配置/部署 | 既有 dry-run、隔离目录、备份、目标版本/hash回读 | 重复执行与部分失败符合约定；部署在范围内时再证明目标加载和回滚 |
| 数据/迁移 | 有代表性的可丢弃数据、事务与兼容测试、备份恢复入口 | 当前迁移的事务、重复执行、恢复与兼容；不自动访问生产数据 |

先复用已有日志、测试和宿主工具。观察缺失时写明“已验证到哪里、缺什么、下一步怎样验证”；仅当现有入口无法验证当前失败时，再承认最小 instrumentation 或测试改动。自动化证据与自然用户验收分别记录。

## 9. 本项目的工程终态与改进边界

目标是一个宿主中立、可验证、可回滚的本地能力管理器：工程事实和方法在唯一源维护，按需进入宿主，验证证据与真实使用结果分层。日常调用方是现有 `ai-coding-workflow`；详细说明留在本参考件，跨仓所需的最小观察选择已内置技能正文，不要求其他项目读取本仓文档。

现有职责链继续使用：`src/ → build.ps1 → skills.ps1` 承载 CLI；`skills.json + overrides/ → 构建生效 → agent/与受控投影` 承载技能配置和资产；`tests/fixtures/ai-coding-workflow/ → 隔离副本 → 宿主实跑与独立复验` 承载显式工作流验收。现有接口足够承载，无需新增主 CLI 命令、模型调度服务或状态数据库。

- 技术栈保持 PowerShell 7；本次没有跨平台运行约束、性能测量或部署失败证明需要换栈。
- 根 `AGENTS.md` 保留仓库入口、不变量、最低门禁和回滚；方法进现有技能，详细场景进本文，确定性约束继续由现有脚本与测试承担。
- 共享工程约定不表示宿主加载方式相同。ZCode 当前仅加载用户全局和 Workspace 的 `AGENTS.md`，不递归合并子目录或展开 import；关键项目约定须在 Workspace 根可见，规则变更按宿主新会话验证。
- 只有当前调用方的真实失败无法被现有接口承载时，才重新评估架构；先证明失败、改动范围、最低验证和仅回滚本次切片的入口。

补充来源（2026-09-12 已读取官方/项目原文）：[OpenAI 最佳实践](https://learn.chatgpt.com/guides/best-practices)、[ZCode 指令与工具能力](https://zcode.z.ai/cn/docs/agents)、[Aider 使用建议](https://aider.chat/docs/usage/tips.html)、[Anthropic 长程代理实践](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)。本文执行取舍为适用于本仓的工程判断，不是模型能力实测排名。

## 10. 可复用的宿主编码验收

调用方是显式验证编码工作流的用户或代理。受版本控制的[样例](../../tests/fixtures/ai-coding-workflow/)替代每次临时编写题目和检查脚本；只保存可重建的输入，不保存历史成功状态。它不进入技能投影，不新增产品命令、常驻服务或独立门禁。自动测试只检查样例能正确识别失败与合规实现，不调用模型。

先在仓库根运行以下准备命令。每次、每个宿主使用新的目录；不要直接修复 tracked fixture，也不要覆盖或 reset 已有实跑目录。

```powershell
$ErrorActionPreference = 'Stop'
$fixture = Join-Path (Get-Location) 'tests/fixtures/ai-coding-workflow'
$runRoot = Join-Path (Get-Location) ('artifacts/work/ai-coding-acceptance/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
foreach ($hostName in @('codex-cli', 'chatgpt-desktop', 'zcode')) {
    $workspace = Join-Path $runRoot $hostName
    Copy-Item -LiteralPath $fixture -Destination $workspace -Recurse
    git -C $workspace init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git init failed.' }
    git -C $workspace add -- AGENTS.md Labels.ps1 Test-Labels.ps1 task.txt review-task.txt
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git add failed.' }
    git -C $workspace commit --quiet -m '建立隔离编码验收基线'
    if ($LASTEXITCODE -ne 0) { throw 'Fixture baseline commit failed; check local Git identity.' }
    $baseline = git -C $workspace rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Fixture baseline lookup failed.' }
    $baseline | Set-Content -LiteralPath (Join-Path $runRoot "$hostName.baseline.txt") -Encoding utf8
}
$runRoot
```

按当前宿主支持的入口打开对应副本，使用其已有模型配置，在新任务中提交 `task.txt` 的内容。Codex CLI 可在副本目录按当前 `codex exec --help` 支持的选项使用 `Get-Content -LiteralPath task.txt -Raw | codex exec --sandbox workspace-write --json -`；将原始事件保存在副本之外的本次 run 目录。桌面入口不可用时保留该副本和缺口，不能通过其他宿主的结果补记成功。计划、权限及非交互命令以当前宿主为准，不修改 provider、认证或插件缓存来绕过阻塞。

验收需要同一次任务的证据：实际宿主/表面、模型与推理档位、源版本、技能读取或加载事件、修复前失败、修复后结果及最终 diff。仅元数据可见不足以证明技能正文已读取；只有代理自述时记录加载不可观察。用新任务的 `review-task.txt` 验证只读交接审查，不将两个模型的同意当成测试。

复验时从本仓调用未被被测代理修改的检查脚本。保留准备阶段输出的 `$runRoot`，将 `$hostName` 设为本次已完成的宿主目录名：

```powershell
$ErrorActionPreference = 'Stop'
$hostName = 'zcode' # Or codex-cli / chatgpt-desktop for the completed run.
$workspace = Join-Path $runRoot $hostName
$baseline = (Get-Content -LiteralPath (Join-Path $runRoot "$hostName.baseline.txt") -Raw).Trim()
$head = git -C $workspace rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $head -cne $baseline) { throw 'Fixture baseline changed.' }
pwsh -NoProfile -File ./tests/fixtures/ai-coding-workflow/Test-Labels.ps1 -SourcePath (Join-Path $workspace 'Labels.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Independent behavior checks failed.' }
git -C $workspace diff --exit-code $baseline -- AGENTS.md Test-Labels.ps1 task.txt review-task.txt
if ($LASTEXITCODE -ne 0) { throw 'Protected fixture inputs changed.' }
$status = @(git -C $workspace status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $status.Count -ne 1 -or $status[0] -cne ' M Labels.ps1') {
    throw 'Fixture contains unexpected changes or staging.'
}
git -C $workspace diff --check
if ($LASTEXITCODE -ne 0) { throw 'Fixture diff check failed.' }
```

原始样例的行为检查应失败；合规修复应为 `cases=11 failed=0`，覆盖空/单/多项、大小写、空白、首次顺序与拼写、文化无关比较、输入不变及幂等。复验还要求没有新增文件、暂存或提交，且只有 `Labels.ps1` 的修改；无输出的普通 diff 不能独自证明这些事实。被测副本之外的基线记录和原始事件应一并保留，只有可观察到的表面才记为该宿主验收。

此样例证明一条受控修复与审查路径，不证明全部技能、自然项目验收或效率提升。性能与费用仍按第 7 节在真实任务中观察；本项目不负责调度这段观察，也不以完成等待时长作为日常编码门禁。
