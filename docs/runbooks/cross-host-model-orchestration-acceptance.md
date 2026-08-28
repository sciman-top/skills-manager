# 跨宿主模型编排验收 Runbook

**性质**：host-specific、identity-specific 的分层验收；不是网关发现、模型检测或普通本地测试
**关联**：[PRD](../product/cross-host-model-orchestration-prd.md) · [架构](../product/cross-host-model-orchestration-architecture.md) · [路线图](../product/cross-host-model-orchestration-roadmap.md) · [实施计划](../product/cross-host-model-orchestration-implementation-plan.md)

## 1. 验收对象与真值边界

本 Runbook 的目标是证明指定 `host + identity + route source + execution slot + model/effort` 的**控制面与宿主采纳边界**。它从不证明所有账号、所有网关、所有模型、运行中的 UI 会话或未来可用性。

| 层级 | 最低证据 | 不证明 |
| --- | --- | --- |
| `repo_verified` | schema、resolver、static Adapter、intent、receipt、projection transaction tests | credential 有效、外部模型可用、host 已读取配置 |
| `filesystem_projected` | exact target 的 before/after/backup hash、lock、atomic apply、rollback receipt | fresh host 已采用、任务正确 |
| `host_loaded` | fresh task 的可观察启动参数、配置采用或宿主事件 | 业务质量、其他 route/host |
| `live_accepted` | 指定 execution slot 的真实工作产物 + 独立 verifier | 跨身份/宿主/模型普遍有效 |

文档、policy、private override、CLI plan、模型自述、进程存在、HTTP 状态、一次回复或网关日志均不能越级。日常控制面不读取模型列表、OAuth、gateway 或请求状态，也不因失败自动换模型。

## 2. 每次 run 的输入冻结

记录：

1. runtime repo revision、`git status`、policy revision、Adapter revision、run id、UTC 时间和执行者；
2. exact `host`（canonical：`codex_cli`）、`identity_selector`、`selection_plane`/`route_map_id`、执行槽位、route key、model、effort、workload、operation、workspace classification 与 stop condition；
3. 是否为 `resolve`、private override 写入、projection plan/apply/rollback、fresh host observation 或真实业务验收；
4. 当前授权仅覆盖什么；没有授权时默认执行 offline resolve 或 dry-run；
5. 私有 receipt root 和 exact rollback entry。

receipt root 的 canonical path 为 `<runtime-root>/.ai/receipts/<yyyy-mm-dd>/<run-id>/`（state 为 `<runtime-root>/.ai/state/`），为 ignored/private 且只允许当前用户读取。不得把 token、cookie、prompt、完整 command、base URL query 或未脱敏环境变量写进 receipt。

## 3. 步骤 A：离线 policy 与五槽位验收

在 fixture/state root 上执行，不访问网络或宿主用户配置：

```powershell
pwsh -NoProfile -File .\scripts\ai-route.ps1 resolve --host codex_cli --identity current-redacted-identity --workload standard_review --risk-level normal --operation read_only --workspace-root <root> --offline
```

`--workload` 是常规入口；`--execution-slot` 仅为 fixture/dry-run 直通参数，必须与 `--workload` 派生结果一致，且不能替代完整字段（缺 `--risk-level`/`--operation`/`--workspace-root` 一律拒绝）。

验收项目：

| 检查 | 必须结果 |
| --- | --- |
| slot 目录 | 只接受 `quick_triage`、`routine_maintenance`、`standard_review`、`bounded_implementation`、`deep_investigation_or_implementation` |
| precedence | `manual_override -> operator_override -> host_default` |
| Sol-only | light=Sol/low；standard=Sol/medium；deep=Sol/xhigh |
| Terra-only | light=Terra/medium；standard=Terra/high；deep=Terra/xhigh |
| Luna-only | light=Luna/medium constrained；standard=Luna/high constrained；deep=Luna/xhigh constrained；high-risk=blocked |
| risk overlay | 任一 slot 触发安全、迁移、发布、公开契约或高扇出规则时进入 high-risk gate |
| unknown | 未知 slot/route key/model/effort、缺 Adapter allowlist 或 scope 不匹配必须 `blocked`/`manual_mapping_required` |

最低证明是 fixture resolver tests、receipt verifier、`git diff --check`。无 `--execute`、无 projection apply 时，必须零 child、零 host write、零模型调用。通过只达到 `repo_verified`。

## 4. 步骤 B：宿主 AI 一句话 action

在已加载 `model-orchestration` Skill、且已验证 Skill 调用的是同一 control-plane CLI 的宿主中，使用以下任一明确动作：

```text
当前 Codex 只使用 GPT-5.6 Sol，切换 Sol-only 三档编排并落盘。
当前 Codex 只有 GPT-5.6 Terra 可用，切换 Terra-only 三档编排并落盘。
当前 Codex 只有 GPT-5.6 Luna 可用，切换 Luna-only 三档编排并落盘。
当前 Codex 恢复默认模型编排。
```

预期行为：

1. scope 必须是 current Codex/current identity；不得广播给 Claude/ZCode 或另一个 Codex identity。
2. 前三句写一个 scoped `operator_override`，并按五个 slot 解析当前 preset 的 route-key map；第四句仅删除该 scope override。
3. 每份 receipt 写明 `selection_plane`/`route_map_id`、requested/resolved/observed 三段 route、execution slot map、静态 Adapter revision、`verification=operator_declared_unverified`、是否生成/应用 projection plan，以及未触及的 provider/auth/base URL/session/plugin cache。
4. “落盘”默认授权 private override 写入；只有 Adapter 已证明 target ownership、允许字段、rollback entry，且 standing projection authorization 与 plan token 都有效时，才可继续 native projection。
5. “Terra 可用吗？”、“都切 Terra”、无目标 host、未知 model/effort 或多 host 未逐一声明 map 的句子必须零写入，返回 answer、`clarify_required` 或 `manual_mapping_required`。

一次 parser/override 成功的最高结论仍是 `repo_verified`；若 apply 了精确 host target，最高为 `filesystem_projected`。它不代表外部模型当前已验证可用。

## 5. 步骤 C：受控 native projection

仅当 Adapter 的 static contract 已明确：

- exact target root 与 target ownership；
- 可写字段严格为 model/profile/effort；
- before/after hash、backup、lock 和 rollback entry；
- 当前 host/identity 的 projection authorization。

才可执行：

```powershell
pwsh -NoProfile -File .\scripts\ai-route.ps1 project --host codex_cli --from-current-override --plan
pwsh -NoProfile -File .\scripts\ai-route.ps1 project --plan <private-plan-path> --apply --token <plan-bound-token>
```

验收顺序：

1. plan 显示 canonical target、route source、五 slot -> route key mapping、allowed fields、before/after hash、backup、policy/Adapter revision 与 rollback entry；
2. Apply 前按序重验：canonical containment -> single-writer lock -> target recheck -> before hash -> confirmation token；
3. 依次完成 `backup -> atomic apply -> after hash -> private receipt`；中断只允许同 plan resume 或按 receipt 精确 rollback；
4. 任何 drift、unknown ownership、UI-only surface、running-session 风险、路径逃逸、secret/provider/auth/session 字段都返回 `manual_host_selection_required` 或 block；
5. Apply 成功只到 `filesystem_projected`，不会声明 host 已加载。

## 6. 步骤 D：fresh host adoption 与业务验收

host adoption 只在用户明确授权启动一个**fresh、范围受控的真实任务**时观察；它不是为了“寻找可用模型”而进行的检测。先审阅 dry-run 的 host、identity、execution slot、route key、model、effort、operation、workspace 和 redaction，再启动。

| 观察 | 可报告的最高结论 | 禁止外推 |
| --- | --- | --- |
| host 可观察到实际采用的计划参数/配置 | 此 route 的 `host_loaded=true` | 其他 host/identity/slot |
| host 不能观察 model/effort | `host_loaded=not_observable` | 不能靠任务看似成功补写 |
| 观察到宿主加载与 resolved route **不一致** | `host_loaded=false`、`observation_status=route_mismatch`、**hard fail** | 不得记为 `not_observable`；不得以控制面选择搪塞 |
| 指定 slot 产出满足独立 verifier | 此 host/identity/route/slot 的 `live_accepted` | 全局质量、长期稳定、跨模型等价 |

任务结果与 plan 不一致是 hard fail。运行中会话不热切换；中断后只能创建带 handover 的新任务，receipt 写 `continuity=not_proven`。不得为改善结果重启/kill host、gateway 或 proxy，或改 OAuth/provider/共享配置。

## 7. 步骤 E：Preset Review 与未来档位演进

Preset Review 必须零网络、零写入。输入是 static contract、policy/default/override revision、五 slot/route-key/risk matrix、route/outcome receipt、同类 verifier、workspace 条件与 rollback point。

Review 要回答：

1. 五个 slot 是否仍各自拥有不同 operation、写集/回滚、最低验证或风险语义；
2. 当前三条 route key 是否能由 static contract 逐条表达；
3. 是否有同 host/identity、同类 execution slot 的 evidence 支持把 `review` 或 `max_depth` 作为第四/第五 route key；
4. 新 route key 是否能在不改 slot、intent、receipt、projection transaction 的前提下加入；
5. 推荐是 `keep`、`promote`、`demote`、`block` 或 `insufficient_evidence`，并给出最小补证和 rollback。

更改模型/effort 档位数通常只需要一个 reviewed route-key map patch。新增、删除、改名、拆分五个 execution slot 是 policy major change，必须另附 migration、跨宿主兼容、fixture/receipt compatibility 与 rollback；不能在日常“切换模型”动作中发生。

## 8. Route receipt 最小形状

```json
{
  "schema_version": 1,
  "run_id": "2026-08-28-codex-terra-only",
  "scope": {
    "host": "codex_cli",
    "identity_selector": "redacted-current"
  },
  "request": {
    "workload": "standard_review",
    "execution_slot": "standard_review",
    "route_key": "standard",
    "operation": "read_only",
    "risk_level": "normal",
    "risk_gate": "none"
  },
  "selection_plane": "operator_override",
  "route_map_id": "gpt56_terra_only",
  "verification": "operator_declared_unverified",
  "requested_route": null,
  "resolved_route": {
    "model": "gpt-5.6-terra",
    "effort": "high",
    "constrained": false
  },
  "fallback_applied": false,
  "clamp_applied": false,
  "observed_host_route": null,
  "observed_by": null,
  "observation_status": "not_observable",
  "policy_revision": "sha256:...",
  "adapter_revision": "sha256:...",
  "projection_receipt_ref": null,
  "truth_boundary": "repo_verified",
  "redaction_verified": true
}
```

receipt verifier 至少拒绝：secret-like value、未知 slot/key、route-key 与 actual model/effort 不匹配、scope 混用、Luna high-risk 非 block、Terra high-risk 缺 emergency、无授权 projection apply、**任何持久化的 `host_loaded` 字段**（该值只能由 `observation_status` 派生，verifier 输出三态结论而不读取持久字段）、`observed_host_route` 出现但 `observed_by`/`observed_at` 或独立 host evidence 不齐全、缺失 fallback/clamp 字段、constrained 约束对象违反冻结形状、未知字段。verifier fixture 须覆盖 `match`/`route_mismatch`/`not_observable` 三种 receipt。

## 9. 停止、恢复和回滚

| 观察 | 当次动作 | 不允许的“恢复” |
| --- | --- | --- |
| 用户发现模型可用性变化 | 用户向当前宿主声明新的 preset/map；写 scoped override | 自行读取 host/gateway/OAuth 来判断 |
| 任务失败、限流、认证、参数错误 | 仅追加 outcome receipt，等待用户下一句声明或恢复默认 | 自动 retry、自动换模型、清状态、切账号 |
| 需要 native target 但 contract 未证实 | dry-run/manual handoff | 猜路径、编辑共享 config 或 UI 自动化 |
| 新模型多出档位 | Preset Review 后 reviewed route-key map patch | 静默增删 execution slot |
| 需要修改五个 slot | 单独 major-change 设计/迁移/验证 | 搭载在一次日常切换里 |
| 会话中断 | 最小 handover，另开任务 | 声称无缝延续 |

回滚只删除本次 scoped private override、按 receipt 回滚本次 projection action，或 revert 本次 policy patch。不得删除其他 identity state、其他宿主 receipt、用户历史、认证资产或宿主运行配置。
