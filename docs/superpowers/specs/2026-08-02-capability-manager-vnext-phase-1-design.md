# skills-manager vNext Phase 1 Design: Read-only inventory and rule advisor

**program_id**: `skills-manager-vnext`
**phase**: `P1`
**status**: implementation_ready
**date**: 2026-08-02

## 1. Goal

在不替代 Codex/ChatGPT/Claude/Gemini/Trae 官方 skills、plugins、MCP、connector、规则加载与权限系统的前提下，提供统一但不扁平化的本地能力清单和只读规则诊断。输出必须可追到文件、revision、命令或官方证据；建议不能自我证明，更不能直接写规则。

## 2. Evidence refresh

### 2.1 Official Codex facts

2026-08-02 通过当前 Codex manual helper 刷新以下事实：

- `AGENTS.md`：全局取 `AGENTS.override.md > AGENTS.md` 的首个非空文件；项目从 root 到 cwd 每层最多一个，近端后加载；combined budget 由 `project_doc_max_bytes` 控制；fresh run/session 重建加载链。
- `AGENTS.md` 应保持小而稳定，承载每次都适用的项目约定；重复流程优先进入 skill，确定性约束进入 hooks/linters/CI/config。
- Skill 是带渐进披露的可复用工作流；plugin 是可安装分发单元，可组合 skill、connector/MCP、hook、assets/UI；存在等价 plugin 时优先复用。
- MCP/connector 提供外部数据与受控动作，auth/permission 由宿主与外部服务所有；本项目不得保存 OAuth/token。
- Plugin 可用 surface、安装状态和新会话激活边界属于宿主事实；repo inventory 不等于 installed、enabled、authorized 或 live accepted。

Official sources:

- <https://learn.chatgpt.com/docs/agent-configuration/agents-md>
- <https://learn.chatgpt.com/docs/customization/overview>
- <https://learn.chatgpt.com/docs/plugins>
- <https://learn.chatgpt.com/docs/skills-and-plugins>
- <https://learn.chatgpt.com/docs/extend/mcp>

### 2.2 Reference revisions

- `openai/codex`: `61a44880a85d2fd0d8770908dea5733495e571c8`
- `openai/plugins`: `11c74d6ba24d3a6d48f54a194cd00ef3beea18f9`
- 参考仓仅作只读结构/fixture 依据；不继承其指令，不运行其脚本，不复制公共目录。
- `openai/skills` 仍为 historical compatibility，不作为当前官方推荐源。

## 3. Phase boundary

### In scope

- `CapabilityDescriptor`、`RuleDocument`、`RuleResponsibility` versioned plain-object contract。
- 聚合当前仓 runtime truth、reference shelf、显式 supplied official/plugin inventory 和授权 host-local read paths。
- Codex-first 规则发现；Claude 仅实现当前证据支持的 profile，不推断未知 precedence。
- 确定性诊断、repo truth 核对、责任覆盖和 recommendation-only semantic advisor。
- `capability-inventory`、`rule-audit` 的 machine-readable read-only CLI/report。
- 三类代表仓 fixture/授权 repo 的 precision、performance、zero-write 验收。

### Out of scope

- 修改 global/repo/nested rule、active profile、MCP、plugin 或 skill projection。
- plugin install/uninstall/enable/auth，connector OAuth，MCP live call。
- 中央 target registry、跨仓同步、统一规则模板/CI、daemon/database/UI。
- LLM/provider 调用；P1 semantic advisor 只使用确定性结构和显式 evidence。
- Gemini/Trae 未获官方证明的规则 precedence；保持 `unknown` 而不是猜测实现。

## 4. Product invariants

1. `read_only=true`：除显式 `--out` 报告路径外，不写任何文件；报告也不得位于被扫描 root 内的规则路径。
2. `provider_calls=0`、`native_mutations=0`、`profile_changed=false`。
3. Capability、RuleDocument、Profile 不建立继承树；只共享 source/evidence 引用和 OperationPlan target ref。
4. 官方、runtime、reference、host-installed、candidate truth 必须分栏，不能按名称合并成单一真假值。
5. deterministic finding 才可进入 blocking profile；semantic finding 始终 recommendation。
6. 未读到的路径、未验证的 precedence、未运行的 fresh-session probe保持 `unknown/not_verified`。
7. 默认仅扫描 repo root、其祖先规则链和显式授权 user path；不枚举整盘或全部目标仓。
8. 任何建议都包含 `source/revision/evidence/confidence/disposition/truth_boundary`。

## 5. Contracts

### 5.1 CapabilityDescriptor v1

```text
schema_version, id, kind(skill|plugin|mcp), name
truth_origin(runtime|reference|official|host_installed|candidate)
source{type,path_or_url,revision,checksum,license,trust_tier}
lifecycle(active|deprecated|historical|unknown)
host_compatibility[], components[], evidence[], verification_state
```

同一 capability 可以有多个 descriptor；dedupe decision 另存为 `canonical|duplicate|alternative|conflict|unknown`，不得删除输入。

### 5.2 RuleDocument v1

```text
schema_version, id, host, scope(global|repo|subtree|override)
responsibility(common|platform_delta|project_action|deterministic_enforcement|task_local)
path, owner, content_hash, byte_size, precedence
discovery_state(observed|inferred|unknown), source_of_truth
findings[], evidence[], verification_state
```

### 5.3 RuleFinding v1

```text
finding_id, kind(deterministic|semantic), code, severity
path, line?, message, evidence[], confidence
disposition(adopt|adapt|reject|defer), blocking
```

`blocking=true` 仅允许 deterministic finding 且 profile 明确启用。

### 5.4 RuleResponsibility v1

```text
constraint_id, common_intent, platform_deltas[]
project_actions[], enforcement_refs[]
coverage(covered|gap|conflict|duplicated|not_applicable)
evidence[], confidence, recovery_condition?
```

## 6. Discovery profiles

### Codex profile

- global candidates：`${CODEX_HOME}/AGENTS.override.md`，否则 `AGENTS.md`。
- project candidates：Git root 到 cwd 每层 `AGENTS.override.md > AGENTS.md > configured fallback`，每层最多一个。
- combined byte budget 来自显式 profile/config evidence；无证据时记录 default observation，不伪装 live loaded。
- `.codex/rules/*.rules` 作为 deterministic enforcement reference，不把其内容当 guidance 文档。

### Claude profile

- 仅扫描明确候选 `CLAUDE.md`/项目 wrapper 和已有 host matrix 允许的路径。
- precedence/import/wrapper 不能从 Codex 语义类推；未知项为 `inferred/unknown`。

### Other hosts

- Phase 1 只输出 matrix 中明确 read path 的 descriptor；无官方加载证据时不建立 precedence chain。

## 7. Deterministic diagnostics

- file existence/type、UTF-8/BOM、byte/line budget、wrapper first physical line。
- exact duplicated blocks、同一层 override/base shadow、候选链预算截断。
- markdown 中显式 path/command 的存在性；命令只做语法/入口核对，不执行外部脚本。
- global 文件出现 repo-private absolute path/command，project 文件出现已证实 host-loading tutorial。
- prose 声称 enforcement 但无 hook/config/policy/script/CI reference。
- profile 不适用时输出 `not_applicable + reason + recovery_condition`。

## 8. Semantic advisor

- common/platform_delta/project_action/enforcement/task_local 责任错位。
- 全局与项目语义重复、冲突、缺口；固定 heading 不是语义判断依据。
- 推荐最小 surface：prompt/thread -> AGENTS -> skill -> plugin -> MCP -> hook/config/CI。
- semantic finding 默认 `blocking=false`；没有外部模型评分。
- `adopt/adapt/reject/defer` 必须记录为什么、落点和验证方式。

## 9. CLI contract

```powershell
.\skills.ps1 capability-inventory --json [--out <path>]
.\skills.ps1 rule-audit --repo <path> --host codex --json [--out <path>]
```

- stdout 在 `--json` 下只有一个 JSON envelope。
- 未显式 `--out` 时零写入。
- `--out` 只能写精确报告文件，不修改被扫描文件。
- exit `0`：contract valid；exit `2`：deterministic blockers；exit `1`：运行/输入错误。
- semantic recommendations 不单独产生 exit `2`。

## 10. Task design

1. `SMV-P1-001`：规划真源和 dynamic verifier。
2. `SMV-P1-002`：三个领域合同与 invalid fixtures。
3. `SMV-P1-003`：capability inventory 聚合和 source disposition。
4. `SMV-P1-004`：host-profile rule discovery。
5. `SMV-P1-005`：deterministic diagnostics。
6. `SMV-P1-006`：responsibility coverage 与 semantic advisor。
7. `SMV-P1-007`：TargetAudit/repo truth integration。
8. `SMV-P1-008`：read-only CLI/report integration。
9. `SMV-P1-009`：representative repo acceptance and closeout。

## 11. Representative fixtures

- simple：根规则一个文件，命令/路径真实。
- nested：global + repo + subtree/override，有明确 precedence。
- conflict：重复、预算、陈旧命令、责任错位和 enforcement 缺口。

真实仓只在用户已授权 workspace/root 内只读扫描；fixture 是 contract evidence，不冒充 live acceptance。

## 12. Ordered verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000
python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

每个 task 先执行 manifest 中 targeted tests；full gate 不替代 zero-write/provider-call-zero probe。

## 13. Failure routing

- official/manual 与当前 callable host 冲突：记录两者并以当前环境实测限制实现，不扩写通用结论。
- unknown precedence：保持 candidate chain，不排序为 confirmed。
- semantic precision 不足：降为 `defer`，不增加更多规则或 LLM gate。
- scan 超时：收窄授权 roots/排除目录，不能跳过 hash/schema/redaction。
- 两次相同失败：进入 clarify_required；不跨过当前 task。

## 14. Done definition

- P1 manifest 全部非 deferred task done，waiver 合法。
- capability inventory 保留类型字段和 truth origin，识别 current official plugin 与 deprecated source。
- 三类代表 fixture 和至少三个授权代表仓只读扫描通过；precision 样本有记录。
- deterministic/semantic finding、coverage、disposition 和 truth boundary 可机器读取。
- 所有 read-only probes 对扫描 root、`skills.json`、host config/profile hash 不变，provider/native invocation count 为 0。
- full gate exit 0；fresh Codex rule-load probe若未授权/未执行则保持 not_run，P1 仅可写 `repo_verified`。
