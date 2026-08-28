# 跨宿主模型编排实施计划与任务清单

**状态**：design-only；任务只在用户选定 `<runtime-root>` 后可执行
**路线图**：[cross-host-model-orchestration-roadmap.md](cross-host-model-orchestration-roadmap.md)
**接口/数据合同**：[cross-host-model-orchestration-architecture.md](cross-host-model-orchestration-architecture.md)

## 1. 执行合同

本计划所有代码 write set 都以 `<runtime-root>` 为前缀。它不授权在 `D:\CODE\skills-manager` 建 runtime、不授权新建仓、不读取凭据、不调用模型、不改 provider/auth/gateway，也不代表有权写 `~/.codex`、ZCode 或 Claude 用户目录。

每个任务开始都必须冻结：

```text
Goal
Exact write set
Minimum proof
Stop
Rollback
Truth boundary
```

先读 fresh `git status`，不得吸收并发改动。host write、fresh task、外部模型调用与账户动作均是独立授权域。所有 control-plane 单元/合同测试默认零网络、零 OAuth 读取、零 gateway/model request。

建议布局仅在 R0 选定 runtime 后创建：

```text
<runtime-root>/
  config/model-orchestration.schema.json
  config/model-orchestration.defaults.yaml
  src/Contracts.ps1
  src/Policy.ps1
  src/PrivateState.ps1
  src/Resolver.ps1
  src/Receipt.ps1
  src/Projection.ps1
  src/Intent.ps1
  src/Adapters/CodexCli.ps1
  src/Adapters/ZCode.ps1
  src/Adapters/ClaudeCode.ps1
  scripts/ai-route.ps1
  scripts/review-model-presets.ps1
  tests/Unit/*.Tests.ps1
  tests/Contract/*.Tests.ps1
```

PowerShell 7 是建议实现介质；R0 如选择既有 C# runtime，可改用相同 contracts/schema/fixture/verification，不得复制两套 policy。

## 2. 依赖图

```text
MOR-DOC-001 -> MOR-090                              # 只读事实采集，不依赖 root；evidence 文档留在设计仓
MOR-DOC-001 -> MOR-000 -> MOR-010 -> MOR-020 -> MOR-030 -> MOR-040 -> MOR-050
MOR-030 / MOR-050 -> MOR-210                        # R4 preset policy 只依赖 R1 离线链，不等 projection
MOR-210 (+ receipt/verifier) -> MOR-230             # R4.5 只读 review
MOR-090 + MOR-000 -> MOR-100 / MOR-300 / MOR-400    # Adapter 合同需一手事实 + root 选定
MOR-100 -> MOR-110
MOR-300 -> MOR-310
MOR-400 -> MOR-410
MOR-050 -> MOR-140 -> MOR-150 -> MOR-200            # 投影链，独立于 preset policy
MOR-230 -> MOR-600 -> MOR-700
MOR-050 -> MOR-055 -> MOR-060
MOR-060 -> MOR-850
```

注：runtime fixtures（`tests/fixtures/<host>-static/`）仍须等 `<runtime-root>` 选定后在目标 runtime 创建；MOR-090 的持久化 evidence 文档保留在当前设计仓（`docs/decision/`），不阻塞于 root。

## 3. R0-R1：设计、策略、离线 resolver

### MOR-DOC-001：冻结本设计切片

- **Goal**：保留本 PRD、架构、路线图、实施计划、runbook 与索引，明确它们不扩展 skills-manager runtime。
- **Exact write set**：当前六份文档文件；不含 `skills.json`、`skills.ps1`、host config 或 auth 文件。
- **Minimum proof**：Markdown relative-link check、关键合同检索、`git diff --check`。
- **Stop / rollback**：若文档要求改变 provider/OAuth/宿主运行状态，停止；只 revert 本文档切片。
- **Truth boundary**：`repo_verified`。

### MOR-000：选择 runtime root、owner 与首期 host

- **Goal**：记录 `<runtime-root>`、owner、首期 host、private state/receipt root、初期三套 GPT preset、授权模型和本次回滚入口；并一次钉死：identity binding 来源（不可伪造/可审计；无法绑定时 `identity_unbound`，禁止持久 override 与 projection）、native bridge role pin 的优先级与排除规则（`overrides/resources/native-agent-bridge/design-griller.toml` 与 `cold-capability-runner.toml` 显式钉 `gpt-5.6-terra/high`；preset 不得静默覆盖，改档需配对实测）、普通任务结构化 ingress 合同。
- **Exact write set**：目标 runtime 的 `docs/decision/MOR-000-brief.md`；不得创建 source/config/secret。
- **Minimum proof**：目标为 Git root；host/identity/owner 无歧义；目标的 target ownership/rollback 仅记录为待证实事实。
- **Stop / rollback**：未指定 root，或需要读取 token/config 才能决定时 stop；删除 brief 即回滚。
- **Truth boundary**：human design decision。

### MOR-090：一手事实与社区结构参考的受控采纳

- **Goal**：在每个 Adapter 首次实现前，建立可复核的静态事实包；依次使用官方文档/官方 help/schema/受控源码，再用社区项目作结构启发，不把社区示例或文档名称当成模型可用性结论。
- **Exact write set**：`docs/decision/MOR-090-static-adapter-evidence.md`、对应 `tests/fixtures/<host>-static/`；仅记录 URL/version/revision/license、脱敏 help/schema 摘要、采用/拒绝决定及 exact consumer，不写 host config、token 或模型请求 receipt。
- **Minimum proof**：每一个 `model/effort/field/target` 都有一手来源或标为 `unknown`；社区来源有 revision/license 和“只采用何种结构”的说明；未证实字段不进入 Adapter allowlist。
- **Stop / rollback**：官方资料不可获取、宿主 help/schema 缺失或社区许可/来源不明时，记录 `platform_na`/`manual_host_selection_required` 并停在 dry-run/manual；不以网页猜测、反编译敏感资产、读取 OAuth 或改配置补齐。删除该 evidence/fixture 切片可回滚。
- **Truth boundary**：static-fact evidence；不是 `host_loaded` 或 `live_accepted`。

### MOR-010：schema 与 policy 样例

- **Goal**：定义 versioned schema，分别表达 `RouteKey`、固定五项 `ExecutionSlot`、risk gate、static Adapter contract、host default、operator override、projection plan 和 receipt。
- **Exact write set**：`config/model-orchestration.schema.json`、`config/model-orchestration.defaults.yaml`、`tests/Contract/PolicySchema.Tests.ps1`。
- **必测**：unknown property；重复 id；未定义引用；空/secret-like 值；unknown model/effort；错误 host scope；缺 `owner/reason/expires_at` 的 Terra emergency；Luna high-risk 非 block；illegal provider/auth/base URL field。
- **Minimum proof**：schema validator 与 focused tests；样例无 secret。
- **Stop / rollback**：schema 被要求接收自由 URL/token 或运行时 catalog 时 stop；revert 三文件。
- **Truth boundary**：`repo_verified`。

### MOR-020：不可变领域 contracts

- **Goal**：实现 `RouteRequest`、`RouteKey`、`ExecutionSlot`、`RiskGate`、`RouteDecision`、`LaunchPlan`、`ProjectionPlan`、`RouteReceipt`、`Outcome` 与稳定 reason codes。
- **Exact write set**：`src/Contracts.ps1`、`tests/Unit/Contracts.Tests.ps1`。
- **必测**：selected/blocked/manual 互斥；fingerprint 排除 secret；route key 与 slot 分离；五个 slot 的固定枚举/未知拒绝；多个 slot 可复用一个 route key；新增 route key 不改变 slot schema；high-risk 是 overlay；frozen decision 不可改。
- **Minimum proof**：focused tests；零网络、零 persistent host write。
- **Stop / rollback**：host-specific config key 渗入 common contract 时退回 Adapter private data；revert。
- **Truth boundary**：`repo_verified`。

### MOR-030：Policy loader 与 execution-slot classifier

- **Goal**：解析结构化 workload 到固定 execution slot，再解析 slot 到 route key；禁止从 prompt/model 名/历史任务猜测。
- **Exact write set**：`src/Policy.ps1`、`tests/Unit/Policy.Tests.ps1`、`tests/fixtures/policy/*.yaml`。
- **默认 slot 模板**：`quick_triage -> light`；`routine_maintenance/standard_review/bounded_implementation -> standard`；`deep_investigation_or_implementation -> deep`；任何 slot 叠加 high-risk 条件即进入 risk gate。
- **必测**：unknown workload；slot 没有 operation/verification；五个固定 slot；多个 slot 复用 route key；未来 fourth/fifth route key fixture 不改变 slot resolution；低风险 simple diff 可走 light、标准 review 不得误走 light；workspace/data-class disallow；risk override；无审批 Terra critical；Luna critical block；`--workload` 常规入口与 `--execution-slot` fixture 直通的一致性校验（不一致拒绝）；请求 operation 超出 slot operation 时 blocked；`risk_level` 仅 `normal | high`。
- **Minimum proof**：focused tests + fixture-based `ai-route resolve --offline`。
- **Stop / rollback**：若实现需要读取用户 prompt、会话或模型 catalog 才能分类，停止；revert。
- **Truth boundary**：`repo_verified`。

### MOR-040：private default/override/receipt state

- **Goal**：实现私有 `host_default`、`operator_override`、resolved route/outcome receipt 与 rollback reference；不保存任何外部执行状态或自动恢复状态。
- **Exact write set**：`src/PrivateState.ps1`、`src/Receipt.ps1`、`tests/Unit/PrivateState.Tests.ps1`、runtime 的 `.gitignore`（仅已有时）。
- **必测**：canonical scope containment；atomic interruption；lock collision；before-hash drift；backup；unknown property；scope isolation；restore-default 精确删除；secret rejection；receipt append-only；override `requires_reconfirm_after` 过期后下一次显式 resolve 返回 `manual_mapping_required` 且不自动切换。
- **Minimum proof**：临时 state root tests；结束后 `git status` 无 private state 文件。
- **Stop / rollback**：需要 SQLite、daemon、跨机同步、TTL、health、retry 或从 task error 改写 state 时 stop；revert。
- **Truth boundary**：`repo_verified`。

### MOR-050：resolver、离线 CLI 与 redacted receipt

- **Goal**：离线得到 deterministic route，不接触 host/network。
- **Exact write set**：`src/Resolver.ps1`、`src/Receipt.ps1`、`scripts/ai-route.ps1`、`tests/Unit/Resolver.Tests.ps1`、`tests/Contract/Receipt.Tests.ps1`。
- **必测**：`manual_override -> operator_override -> host_default`；Adapter allowlist（按 §5.1 矩阵逐项，仅 verified tuple）；slot/route-key mapping；五 slot 三 key fixture；五 slot 五 key future fixture；all three GPT preset；risk gate；GLM/DeepSeek static fixture（candidate 未取证 -> manual/block）；missing model/effort -> manual/block；no auto fallback；redaction；receipt 三段式（requested/resolved/observed）与 fallback/clamp 字段；host alias 归一化（`codex`→`codex_cli`，state/receipt 只存 canonical）；constrained 约束对象（false 无限制字段 / true 限制字段非空 / 不一致 fail closed）。
- **Minimum proof**：所有 fixture 的 `resolve --offline` 和 focused tests；零 network/process/host write。
- **Stop / rollback**：CLI 试图访问 gateway、读取 OAuth、执行 child 或改 host config 时停止；revert。
- **Truth boundary**：`repo_verified`。

### MOR-055：人工声明 override 与恢复默认

- **Goal**：实现 current host/current identity 的 persistent override，只通过用户声明更新；identity 必须有可审计绑定来源，未绑定时 `identity_unbound` 并拒绝持久写入。
- **Exact write set**：`src/Defaults.ps1`、`src/PrivateState.ps1`、`src/Resolver.ps1`、`scripts/ai-route.ps1`、`tests/Unit/Defaults.Tests.ps1`、`tests/Contract/OperatorOverrideReceipt.Tests.ps1`。
- **必测**：Sol/Terra/Luna preset switch；Codex override 不影响 ZCode/Claude；新 map 基于该 host template；无法映射时 `manual_mapping_required`；restore 只删 exact override；task outcome 不变更 state；receipt 为 `operator_declared_unverified`；`identity_unbound` 拒绝持久写入；`requires_reconfirm_after` 到期重确认。
- **Minimum proof**：offline fixture state root、schema/resolver tests；zero host config write。
- **Stop /rollback**：override 修改 provider/auth/base URL，污染 tracked policy，跨 host 广播，或缺 receipt/backup 时 stop；精确 rollback state。
- **Truth boundary**：`repo_verified`。

### MOR-060：宿主 AI 一句话 action parser

- **Goal**：让薄 Skill 把明确用户指令映射到同一 CLI/module transaction。
- **Exact write set**：`src/Intent.ps1`、`scripts/ai-route.ps1`、`skills/model-orchestration/SKILL.md`（或 runtime 已有受管 Skill source）、`tests/Unit/Intent.Tests.ps1`、`tests/Contract/NaturalLanguageAction.Tests.ps1`。
- **必测**：三种 Codex preset；ZCode GLM candidate（未取证零写入/manual）；Claude Flash/high、Flash/max、Pro/max candidate；restore default；问句/转述/无 host/未知 effort/“所有环境”零写入；“落盘”仅满足 projection capability+authorization 时生成 plan；普通任务 ingress：AI 分类建议须用户确认后才成结构化 RouteRequest，从 prompt 直推即拒绝。
- **Minimum proof**：parser fixture + offline receipt；断言无 `--execute` 时零 child 和零 host write。
- **Stop / rollback**：若需要 LLM 分类、prompt 猜测、绕开 CLI 或直接编辑 config，停止；revert。
- **Truth boundary**：`repo_verified`。

## 4. R2-R4：Codex 静态 Adapter 与三套 preset

### MOR-100：Codex static Adapter contract

- **Goal**：消费 MOR-090 的官方/本机一手事实及被批准的结构参考，建立 Codex static contract/fixture；运行时不 discovery。
- **Exact write set**：`src/Adapters/CodexCli.ps1`、`tests/fixtures/codex-static/*.txt`、`tests/Unit/CodexCliAdapter.Tests.ps1`、policy contract entry。
- **必测**：按 MOR-090 §5.1 矩阵逐项验证 codex_config_surface 组合——openai_api 面已 verified 的 (model, effort) **不自动外推**；字段词表 minimal..xhigh verified，逐项 (model, xhigh) 为 model-dependent，经本机 help/fixture 确认后才进 allowlist；`max` 不得进入 config 面合同（security 等 surface 单列 candidate）；未证实组合一律 manual/block；未知参数拒绝；capability=false 即 launch/manual；无 private user-dir read。
- **Minimum proof**：fixture parser/contract tests；真机事实采集若有仅是 read-only maintenance evidence。
- **Stop / rollback**：需要修改 `~/.codex`、login、重启 Desktop 或执行模型任务才能“确认”时停止；revert。
- **Truth boundary**：`repo_verified` + static-fact evidence，非 live。

### MOR-110：Codex dry-run launch

- **Goal**：将 frozen decision 生成可审查、脱敏的一次性 Codex launch plan。
- **Exact write set**：`src/Adapters/CodexCli.ps1`、`scripts/ai-route.ps1`、`tests/Contract/CodexLaunchPlan.Tests.ps1`。
- **必测**：三通道、五个 slot、Terra emergency、Luna critical block、Windows quoting、no token、unknown effort not emitted、frozen mismatch。
- **Minimum proof**：dry-run snapshots；无 `--execute` 时零 process launch。
- **Stop / rollback**：help/schema 未证实 effort 表达时只输出 manual handoff；revert。
- **Truth boundary**：`repo_verified`。

### MOR-140：受控 projection engine

- **Goal**：实现通用 plan/apply/rollback；仅当 Adapter 已证实 exact native model target/ownership 时可实际使用。
- **Exact write set**：`src/Projection.ps1`、`src/Adapters/CodexCli.ps1`、`scripts/ai-route.ps1`、`tests/Unit/Projection.Tests.ps1`、`tests/Contract/ProjectionReceipt.Tests.ps1`。
- **必测**：canonical containment、single-writer lock（先于 before-hash；范围与 stale-lock 崩溃恢复）、锁内 before-hash drift、backup、atomic failure、resume、per-action rollback、allowed-field allowlist（按 surface）、provider/auth/session rejection、dry-run no write。
- **Minimum proof**：mock filesystem + temporary fake host root；不写真实 `~/.codex`。
- **Stop / rollback**：无 schema/ownership/rollback contract 时返回 `launch_only`；revert source/tests。
- **Truth boundary**：`repo_verified`。

### MOR-150：Codex projection POC（独立当前授权）

- **Goal**：在用户明确指定的非生产或安全 target 上，对一个 scoped override 做一次 plan/apply/rollback。
- **Exact write set**：指定的一个 target + private backup/receipt；不得写 provider/auth/base URL/session/plugin cache。
- **Minimum proof**：plan token、before/after/backup hash、rollback restores before hash；host adoption 与业务验收分开记录。
- **Stop / rollback**：shared main config、running-session 风险、unknown ownership、drift 或受控字段外写入立即 stop；rollback completed action only。
- **Truth boundary**：`filesystem_projected`；host loaded 另验。

### MOR-200：fresh Codex host adoption（独立当前授权）

- **Goal**：仅当用户授权启动一个 fresh、低风险任务时，观察 host 是否采用 planned route。
- **Exact write set**：private receipt/event 或明确临时 workspace；不写业务资产。
- **Minimum proof**：可观察 host event/launch parameter 与 receipt 一致；不可观察则明确 `host_loaded=not_observable`。
- **Stop / rollback**：不能观察、运行会话风险、identity ambiguity 或 task scope 越界时停止；删除临时 artifact。
- **Truth boundary**：per-route `host_loaded`，不是模型普遍可用。

### MOR-210：GPT 三预设与 execution-slot contract

- **Goal**：实现 Sol-only、Terra-only、Luna-only 的当前三 route-key policy，并用固定五个 execution slot 验证 route-key 复用和风险覆盖。
- **Exact write set**：policy defaults、fixtures、resolver/adapter tests、slot catalog docs。
- **必测**：`quick_triage` light；`routine_maintenance`、`standard_review`、`bounded_implementation` standard；`deep_investigation_or_implementation` deep；Terra critical emergency；Luna critical block；Sol/low absent -> manual/block；unused max not auto-added；Luna preset 各组合在 codex_config_surface fixture 证实前按 candidate/manual 解析（不因 preset 存在而视为可用）。
- **Minimum proof**：focused resolver/adapter tests；零实时 API。
- **Stop / rollback**：将 Luna/Flash 自动升为 high-risk，把模型多一档误当作新增 slot 的理由，或在无迁移兼容/rollback 的情况下改五 slot 目录时 stop；revert policy/tests。
- **Truth boundary**：`repo_verified`。

### MOR-230：Preset Review（只读）

- **Goal**：分析每个启用 host default、GPT preset 与 current override，输出 `keep/promote/demote/block/insufficient_evidence`。
- **Exact write set**：`scripts/review-model-presets.ps1`、`tests/Contract/PresetReview.Tests.ps1`、`docs/preset-review-template.md`；实际 review 仅 private receipt。
- **Review inputs**：policy/default/override revision、static Adapter contract、five-slot/route-key/risk matrix、route/outcome receipt、同类 verifier、rollback reference。
- **必测**：slot 无独立差异 -> merge recommendation；standard review 被放入 light -> demote；Terra critical 缺 emergency -> block；Luna critical -> block；GLM/Flash max 无证据 -> constrained；cross-host evidence reuse rejected；zero mutation/network。
- **Minimum proof**：fixture report + contract tests。
- **Stop / rollback**：review 自动排名、调用模型、改 default/override/host config 时 stop；revert。
- **Truth boundary**：`repo_verified` policy assessment。

## 5. R5-R6：ZCode 与 Claude 静态接入

### MOR-300：ZCode GLM static Adapter 与 default

- **Goal**：消费 MOR-090 的一手事实后，才可把 GLM 模板从 candidate 升为 default。`GLM-3.5-Flash` 未见于当前官方阵容（2026-08-28 检索），退出 static default；当前候选 slug 为 `glm-5.3-flash`（GLM Coding Plan 在列）。GLM surface 词表已证实：bigmodel Chat Completion API `reasoning_effort` 枚举 GLM-5.2+ 支持 `low/high/max`（默认 `max`），ZCode 选择面 低/高/最高 对应；仍待取证的是 ZCode 宿主投影面与 identity surface，且 `thinking` 不可关闭需在 light 档语义中明示。取证前任何 GLM route 解析为 `manual_mapping_required`。
- **Exact write set**：`src/Adapters/ZCode.ps1`、ZCode static fixture、policy default、`tests/Unit/ZCodeAdapter.Tests.ps1`、launch-plan tests。
- **Minimum proof**：fixture parser + offline resolution；每个精确 token 必在 static allowlist；未知 target -> manual。
- **Stop / rollback**：不得以 skills/MCP config 当 model target，不读/写 `.zcode` 用户配置或认证资产；revert。
- **Truth boundary**：`repo_verified` + static-fact evidence。

### MOR-310：ZCode projection POC 或 manual handoff

- **Goal**：若 Adapter 证明 native target ownership，则复用 MOR-140 transaction；否则稳定输出 exact model/effort handoff。
- **Exact write set**：ZCode Adapter/projection tests；获授权后仅一个 exact target/private receipt。
- **Minimum proof**：plan/token/hash/backup/rollback，或 manual handoff fixture；不从运行时探测 target。
- **Stop / rollback**：before-hash drift、UI-only、provider/auth field 或 unknown schema 时 stop；rollback exact action。
- **Truth boundary**：`repo_verified` 或 `filesystem_projected`。

### MOR-400：Claude DeepSeek static Adapter 与 default

- **Goal**：消费 MOR-090 的一手事实，分别建立 `ClaudeCodeHostAdapter`（宿主 model 选择、`effortLevel`、`fallbackModel` 链、组织 clamp、fresh-session 可观察性）与 `DeepSeekProviderDialect`（exact 模型名 `deepseek-v4-flash`/`deepseek-v4-pro`、未知名回落 flash、`output_config` effort 透传）两份合同；两合同各自取证并交叉验证前，`claude_deepseek_candidate` 保持 candidate：quick=Flash/high，routine/review/bounded=Flash/max constrained，deep=Pro/max，high-risk=Pro/max + policy。
- **Exact write set**：`src/Adapters/ClaudeCode.ps1`、Claude static fixture、policy default、`tests/Unit/ClaudeCodeAdapter.Tests.ps1`、launch-plan tests。
- **必测**：fixture parser + offline resolution；精确 V4 Pro/Flash 名称和 effort token 被原样保留；Claude effort clamp fixture（不支持档位静默降档必须留痕，不一致不得 host_loaded）；`fallbackModel` 链（≤3、529 触发）fixture；DeepSeek 未知名回落 flash fixture；unknown target -> manual。
- **Stop / rollback**：不得复制/修改 `CLAUDE_CONFIG_DIR`、登录或借 Pro/max 名称绕过 high-risk gate；revert。
- **Truth boundary**：`repo_verified` + static-fact evidence。

### MOR-410：Claude projection POC 或 manual handoff

- **Goal**：仅在 native target 及 ownership 已证实时投影 DeepSeek fields；否则保持 dry-run/manual handoff。
- **Exact write set**：Claude Adapter/projection tests；获授权后一个明确 native target/private receipt。
- **Minimum proof**：plan/token/before/after/backup/rollback tests；fresh host adoption 另行做。
- **Stop / rollback**：auth/provider/session key、unknown field、running-session risk 或 path escape 时 stop；rollback exact action。
- **Truth boundary**：`repo_verified` 或 `filesystem_projected`。

### MOR-500：各宿主 fresh adoption（独立当前授权）

- **Goal**：在 ZCode/Claude 各启动一个指定低风险 fresh task，记录是否可观察到 host adoption；不进行“找可用模型”的探测。
- **Exact write set**：private host-specific receipt/event；可选明确临时 workspace。
- **Minimum proof**：exact host/identity/route/workload/time；不可观察如实记为 `not_observable`。
- **Stop / rollback**：auth、identity、成本、session 或 scope 不清即停止；仅删除本 run 临时 artifact。
- **Truth boundary**：每 host/route 的 `host_loaded` 或 lower observation。

## 6. R7-R9：人工 promotion 与离线运营

### MOR-600：evidence/verifier completeness gate

- **Goal**：机械检查用于 Preset Review/promotion 的 case context 是否可比较，不排名模型。
- **Exact write set**：`scripts/verify-model-evidence.ps1`、`tests/Contract/ModelEvidence.Tests.ps1`、fixture/schema。
- **必测**：missing/duplicate case；input/source/context mismatch；cross-host identity mixing；unknown observed effort；slot/operation/risk mismatch；redaction。
- **Minimum proof**：all fixture tests；零网络。
- **Stop / rollback**：工具读取 secret、自动跑模型或自动修改 policy 时 stop；revert。
- **Truth boundary**：`repo_verified`。

### MOR-700：reviewed policy promotion/rollback

- **Goal**：把已审查的 host-local evidence 转成一个可撤销的 policy/default route-map patch。
- **Exact write set**：`config/model-orchestration.defaults.yaml`、approved decision record、受影响 tests。
- **Minimum proof**：schema/resolver tests、evidence verifier、owner decision、`git diff --check`。
- **Stop / rollback**：缺 owner、以一次回复取代 verifier、试图跨 host 借 evidence 或写 provider/auth 时 stop；`git revert` 本 patch。
- **Truth boundary**：`repo_verified` policy decision。

### MOR-850：离线日常操作

- **Goal**：提供 `status`、`resolve --offline`、`preset show/set`、`reconcile`、`restore-default`、`receipt inspect`、`project --plan` 和 `rollback`。
- **Exact write set**：CLI help、runbook、focused tests。
- **Minimum proof**：每命令 exit code、redaction、scope containment、non-mutating default、rollback tests；除明确 reconcile/project apply 外零写入。
- **Stop / rollback**：若加入 watcher、probe、自动 retry、自动 login/account switch、gateway scanning 或后台 state rewrite 时 stop；revert command slice。
- **Truth boundary**：`repo_verified`。
