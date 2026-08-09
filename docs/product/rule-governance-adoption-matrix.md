# 规则治理参考采纳矩阵

**scope**: `skills-manager vNext` Rules Advisor planning
**reference_revision**: `D:\CODE-other\governed-ai-coding-runtime@bbf5aba4b221ecf5ac0279ad41c9c51c104b4191`
**status**: adopted_with_rule_estate_followthrough
**最后更新**: 2026-08-08

## 1. 结论

该参考仓值得参考，但只作为静态规则治理模式和测试证据来源。最有价值的不是固定文档模板，而是三层责任分工：全局 common 定义跨仓稳定 WHAT，平台 delta 定义宿主加载/诊断/权限差异，项目 action 定义本仓 WHERE/HOW。目标仓保持自治，任何建议先以只读 finding/patch plan 表达。

全局最优会倾向完整 typed model、跨平台 adapter、统一索引和更广自动化；当前运行约束仍要求复用 PowerShell、文件/Git 真源、现有门禁与单用户工作流。2026-08-05 的 read-only C#/.NET typed-core PoC 已完成历史 parity 评估，但因零生产/仓外消费者和无净收益证据退役；任何未来生产迁移仍须一个 seam、两个 caller、corpus parity、分发/回滚和净收益证据。

## 2. Adoption matrix

| 模式 | disposition | 本项目落点 | 原因 | 验证 |
| --- | --- | --- | --- | --- |
| 全局 common / 平台 delta / 项目 action | `adopt` | `FR-RUL-008..010`、`RuleResponsibility` | 边界清晰，能减少重复和平台语义泄漏 | P1 代表仓责任覆盖 fixture |
| Codex/Claude common 可比较、delta 独立 | `adopt` | host matrix + P1 discovery | 共同工程语义可复用，加载/权限不能混同 | 官方文档/help + host-specific probe |
| 根规则只保留高频硬规则和入口 | `adopt` | `FR-RUL-011` | 降低常驻上下文，支持渐进披露 | byte/duplicate/surface findings |
| prose 与确定性 enforcement 分离 | `adopt` | `deterministic_enforcement` responsibility | `AGENTS.md`/`CLAUDE.md` 不是权限系统 | script/hook/CI/rules 引用检查 |
| `Global Rule -> Repo Action` 映射 | `adapt` | coverage 五态 | 保留可执行承接，允许 `not_applicable` 和非 R1-R8 规则族 | gap/conflict/duplicate fixtures |
| stable rule / dynamic state 分离 | `adopt` | `FR-RUL-020`、项目根状态真源指针 | 防止任务计数、gate 与 host/live 快照在根规则中过期 | fresh manifest read + estate structural findings |
| 固定 `1/A/B/C/D` 结构 | `adapt` | 可选 profile | 对当前用户规则有效，但不是宿主官方通用要求 | profile opt-in，不作为默认 universal blocker |
| 全局 130 lines/16 KiB、项目 80 lines/10 KiB | `adapt` | 可配置 budget finding | 可作保守默认；Codex 官方限制是合并项目链预算且可配置，不是这些固定数字 | host/profile budget source |
| Claude `@AGENTS.md` 薄 wrapper | `adapt` | Claude profile candidate | 能减少双份维护，但 import/上下文语义必须由当前官方资料或 native probe 证明 | BOM/import/static + Claude-native evidence |
| 权威中央 target registry / 模板覆盖 / 后台 drift repair | `reject` | 明确非目标 | 目标仓自治，恢复旧控制面会扩大误写面和维护成本 | 动态磁盘发现；缓存 registry 只报告 drift |
| reviewed rule-estate orchestration | `adapt` | `FR-RUL-014..019`、`rule-estate-plan/apply/rollback` | 用户核心需求需要全局和多目标仓治理，但不需要中央真源或跨仓事务 | exact allowlist、target-set/target-file hash/lock preflight、dirty observation、per-target receipt |
| 跨仓统一规则 CI 和无审阅自动覆盖 | `reject` | 无产品落点 | repo-side 静态通过不等于宿主加载，语义误报不应自动写入 | AI self-review 拒绝；显式 review/token；host/live 分层 |
| 通用规则 AST / 重型 policy engine / daemon / DB / Web UI | `reject` | `ADR-SMV-005/008` | 当前没有规模、性能或协作证据 | 架构触发条件 review |
| Claude 全加载 precedence 与 hosted 行为 | `defer` | host-specific evidence backlog | 本轮本机 help 只证明部分能力，不能外推完整语义 | 刷新 Anthropic 官方文档并做可用 native probe |

## 3. 1+1>2 acceptance

一个规则族只有同时满足以下条件才是 `covered`：

1. common intent 是跨仓稳定、会改变执行的约束。
2. 每个适用宿主的 delta 有官方文档、help/schema 或 native probe 依据；未知保持 unknown。
3. 项目 action 落到真实命令、路径、阻断条件、证据或明确 N/A。
4. common、delta、action 不冲突，也没有需要同步维护的重复正文。
5. 需要确定性执行的部分已路由到 config/rules/hooks/scripts/CI，而不是只写 prose。

结构一致、行数达标、wrapper 可解析或静态 verifier 通过，只能证明相应结构合同，不能单独证明 `covered`、`host_loaded` 或 `live_accepted`。

## 4. Truth boundary

- OpenAI Codex 语义来自 2026-08-01 当前 manual：global/repo/nested discovery、root-to-cwd merge、默认 32 KiB 合并项目指令预算、fresh run/session 重建，以及 experimental `.rules` 的命令决策边界。
- Claude 本轮只把本机 `claude 2.1.206 --help` 明示的 `CLAUDE.md` auto-discovery/skills/bare 边界作为 capability evidence；未完成的 precedence、import 和 hosted 结论保持 defer。
- 参考仓工作树在读取时干净，revision 如页首；它已退役为静态档案。本项目采纳其 v9.60 common/delta/action、渐进披露和反过度设计思想，但不继承其“本仓不做跨仓管理”的退役产品边界，也不执行其脚本或写入其文件。
