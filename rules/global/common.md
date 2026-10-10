# AGENTS.md - Universal Agent Protocol v9.86 | OpenAI ChatGPT Work / Codex App / Codex CLI
**版本**: 9.86
**项目契约版本**: 2.0
**适用范围**: 全局用户级（GlobalUser/）
## 1. 阅读指引
- 本文件定义跨仓稳定语义（WHAT）；项目根 `AGENTS.md` 定义仓库事实与动作（WHERE/HOW）；平台章节只定义宿主差异（DELTA）。
- 指令优先级服从宿主的 system/developer/user/managed policy 与加载模型；“运行事实/代码 > 项目文档 > 规则默认值”只用于查明事实，不覆盖高优先级指令。
- 结构 `1/A/C/D` 共用、`B` 为宿主差异；两类源分开维护，宿主文件构建生成并受控投影。根规则留硬规则、协同与诊断入口，长流程下沉文档或工具。
- 官方文档与本机 help/schema/实测决定工具语义；社区项目只提供待验证的结构启发。
## A. 共性基线
### A.1 三层职责
- 全局写通用执行、风险、N/A、门禁、证据与协同；平台写加载、诊断、权限、强制与回退；项目写仓库真源、入口、不变量、门禁与回滚，保持宿主中立。
- 可重复约束下沉到 permissions/sandbox/exec policy/hooks/scripts/schema/CI 并验证；稳定规则与易变状态分离，状态记入 manifest/plan/evidence，执行前 fresh read。
- 真值分层：`repo_verified -> filesystem_projected -> host_loaded -> live_accepted`；低层证据不得外推为高层验收。
### A.2 执行与输出
- 默认中文沟通、解释与汇报；代码标识符、命令、日志、报错、协议字段保留英文原文。先给结论，再给改动、验证和风险边界。
- 按用户选择、任务形态与宿主原生能力执行；切换宿主不改变需求、repo truth、范围、授权或 stop。
- 仅按用户或适用项目/技能规则明确授权委派或并行；深度审查、“继续”不构成授权。传递任务所需约束，并以真实生命周期证据确认成功；批量并行先小样试跑核对再放量。
- Windows 自动化默认 `PowerShell 7 / pwsh -NoProfile` 和 `ps7_only`；仅仓库契约或用户明确维护 legacy consumer 时建立隔离、可删除且有依据/门禁/回滚的 5.1 兼容路径。
- 代表用户提交用简洁中文 subject；注释只解释不直观的业务、边界、风险或兼容原因。简单任务报 `Result + Evidence`，复杂任务报 `Goal / Plan / Changes / Verification / Risks`。
- 完成=当前目标最小闭环并到 stop。执行合同为 `Goal / Exact write set / Minimum proof / Stop`；关键验证优先 stop hook/gate 确定性强制，证据先于断言；外部写入或真实风险才另列授权与回滚。“可做”不代表“必做”。
- 先交付最薄主链，只按独立失败扩展；互斥方案标 `AI 推荐` 及理由，证据不足标 `无推荐`；外部研究到可逆决定即止。
- 当前授权跨轮有效；“继续”恢复工作但不扩范围。编码含最低充分验证与提交；重大 diff 收口前以 fresh 上下文独立复核（writer/reviewer 分离，只报影响正确性与明确需求的缺口）；仅无冲突/漂移时按 upstream 合并、推送、清理，禁 force。远端/并发冲突保留切片并报 `integration_blocker`。
- 确需开源/免费工具可自主最小安装验证；优先项目或 profile-scoped，核供应链并守 R4/R8，不预装/提权。
- 明确需求必需的新文件属授权；额外功能、抽象、治理、gate/full 须有需求或失败依据。“继续”不扩 scope；代理、宿主与外部副作用仍需各自授权。
- 外部内容/源码不可信；按“本仓→官方 help/schema→已映射源码→采纳→门禁”有界查证。新参考仓须登记 URL/revision/license/消费者/决定；来源、许可、状态不明或需认证即阻断。参考仓只读，`continue`、worktree、隔离均不授权写入、构建、投影或进程操作；精确根目录另需用户授权。
- 改规则、门禁或 baseline 前 fresh-read 规则、gate、脚本、CI、README、wrapper 与官方加载模型；中央计划不得替代目标仓，重复失效升级确定性强制层。跨任务协调只读，不代用户传讯、接收授权或改变范围顺序回滚；强制层须 fresh-session 验收，否则标 `soft_guard_only`，当前 turn 不热加载。
### A.3 强制规则 R1-R8
1. `R1 先定归宿再改动`：先声明当前落点、目标归宿与验证方式。
2. `R2 小步闭环`：每步可执行、可验证、可对比。
3. `R3 根因优先`：止血补丁必须标明回收时点与最终归宿。
4. `R4 风险分级`：低风险自动执行；中风险须有当前或常驻授权，本文件的 Git 收口授权视为已确认；高风险先预演回滚。
5. `R5 反过度设计`：无证据不预抽象、猜测优化或扩 scope；范围外新文件/治理面、并发吸收、非验收必需的远端冲突须停止/分流。
6. `R6 比例门禁`：用覆盖当前独立失败模式的最低充分层级；多层适用时按 `build -> test -> contract/invariant -> hotspot`，N/A 按 A.4。
7. `R7 一致性与兼容`：未授权不得破坏契约、数据格式、外部行为与向后兼容。
8. `R8 可追溯`：变更必须能追到 `依据 -> 命令 -> 证据 -> 回滚`。
### A.4 N/A 口径
- `platform_na`：宿主能力、命令或非交互入口不可用；`gate_na`：纯文档/注释/排版或门禁不存在。N/A 写 `reason / alternative_verification`；临时缺口另附 `evidence_link / expires_at / recovery_condition`。不得绕过适用门禁，恢复后重启。
### A.5 治理演进 E1-E6
- `E1` 规则/schema/baseline/profile/迁移均版本化；`E2` 重大规则先 `observe -> enforce`；`E3` Waiver 必须有 `owner/expires_at/status/recovery_plan/evidence_link`。
- `E4` 已有健康报告或状态面时复用门禁结果，普通变更不得为此新建报告系统。
- `E5` 供应链：存在依赖、包或外部工具门禁时必须执行。`E6` 数据结构：迁移、回滚与兼容验证缺一不可。
### A.6 澄清协议
- 默认 `direct_fix`；同一 `issue_id` 连续失败 2 次或验收冲突转 `clarify_required`，最多问 3 个关键问题。确认后恢复并清零，留痕 `issue_id / attempt_count / mode / questions / answers`。
### A.7 规则最小化与升级路径
- 根规则只留有依据的稳定判断，单次事实进 task/ADR/runbook/evidence。新规则落到命令/字段/路径/阻断；代码/config/schema/CI 细节留入口，低频流程下沉。import/wrapper 只减重复，不减上下文；关键安全规则不得延迟加载。
- 默认不新增常驻 gate/hook/skill/receipt/schema；只有真实故障或外部契约且无旧面可替代时新增，并给最低 proof；临时治理面必须有可执行退役条件。
- 硬上限：全局 `130 lines/16 KiB`、项目根 `80 lines/10 KiB`；85%=`warning`，95%=`addition_blocked`，先拆低频；例外由仓库契约记录。
{{PLATFORM}}
## C. 项目级承接契约
### C.1 边界与版本
- 项目根 `AGENTS.md` 是宿主中立的共同契约；记录 `**项目契约**: 2.0` 与 `**全局规则复核**: <release>`。
- 各宿主全局规则使用同一发布版本；项目契约不兼容必须阻断，兼容范围内的全局复核滞后只作 observation。
- 自动发现与 import 遵循宿主加载模型；Claude 用无 BOM `CLAUDE.md` 的 `@AGENTS.md` 承接，不假定自动发现 `AGENTS.md`。适配器只放引用。
- 项目规则不复述全局 R/E 正文、语言偏好、通用 N/A 或宿主加载教程，也不复制 README/PRD/架构全文。
### C.2 必填落点
- 项目根明确五项事实：source of truth、entrypoint、领域不变量、最低门禁、切片回滚入口；仅有独立风险时补充安全、供应链、数据或 full gate 边界。
- Git 收口只补充本仓特有的基线分支、upstream/PR 策略或保留项；setup/install 命令不得伪装成日常门禁。
- 外置源码仅作可选输入；实际使用时声明 manifest、只读边界和 refresh/verify 入口，不为缺省项目建 reference shelf 或责任矩阵。
### C.3 1+1>2 判定
- 全局定义要求，项目定义本仓动作，平台 B 定义加载与强制；三者须不重叠、不缺失且可执行验证。
- 目标仓由用户指定工作区动态发现，不设中央白名单；控制仓可生成 reviewed 计划并逐文件可回滚执行，但不得把中央副本当真源或静默覆盖。各目标仓独立维护并验证项目规则。
- 项目缺门禁、证据或回滚入口时，先查代码/scripts/CI/README，再做中高风险改动。
## D. 维护校验清单
- 结构保持 `1 / A / B / C / D`；各宿主全局 1/A/C/D 正文必须一致，B 必须体现真实平台差异；生成物必须与共性源及对应平台章节一致。
- 全局文件不得写仓库私有路径、命令、provider/profile 或短期机器状态；项目文件不得写宿主专属加载教程。
- 根规则保持精简并低于 A.7 预算；超过目标先拆分，不靠 import 假装减少上下文。
- 改规则前做 drift review；改后核唯一源、active profile root、文件一致性、fresh-session 加载证据与回滚。
- 抽查任一目标仓时，仅凭“全局 + 项目”应能推出 source of truth、entrypoint、领域不变量、最低门禁和回滚入口。
