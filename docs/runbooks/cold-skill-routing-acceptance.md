# 冷技能路由实跑验收 Runbook

**契约**: 2.0 · **新增**: 2026-08-23 · **性质**: 显式验收工作流，不属于普通编码完成条件

## 1. 边界

- 验收对象是 `capability-router` 冷发现链路：可见能力判定（宿主）→ 一次有界冷发现 → 宿主语义选择 → 精确闭包校验 → admission → 按 `execution_contract` 分流执行。
- 只读发现与执行授权严格分离：router 永远 `writes_performed=false`、`execution_authorization.status=not_granted`；任何加载/执行都以 `load_validation.pass=true` + `truth_boundary=candidate_load_validated` 为前置。
- `native_agent_bridge` 仅投影到 `~/.codex/agents`（Codex）。宿主没有原生子代理机制时（如 ZCode），`native_child_started` 必须记 `not_observable` 并注明原因；`conversation_owner=parent` 的契约由父任务代行，禁止伪称子代理已运行。
- 真值层级：Pester/build/gate=`repo_verified`；投影=`filesystem_projected`；新宿主会话可见=`host_loaded`；带事件证据的真实代表任务=`live_accepted`。不得把代表性验收外推为全部冷技能已 live accepted。

## 2. P0 场景语料（固定，不得使用"这个方案/当前 diff"类占位语）

| # | 请求语料（范例） | 预期链路 |
|---|---|---|
| S1 | `$grill-me 帮我审问 D:\fixtures\plan.md 这个方案`（可见技能） | 直接 `grill-me`；不触发 cold discovery、不启动 router |
| S2 | `用 grill-with-docs 技能，基于 docs/product/x.md 每轮一题审问`（显式冷技能） | 精确发现+闭包校验 → `multi_turn_user_decision`/`design-griller` → 一题一轮等用户作答 |
| S3 | `用 domain-modeling 技能只读审视 reports/cold-skill-eval/<run-id>/fixture-order-model.md`（冷技能单轮只读） | `decision` 域发现 → 精确校验 → `one_shot`/`cold-capability-runner` 的 read_only admission；无任何写入 |
| S4 | `我要对一份设计文档做逐轮审问式打磨，每轮只问一个能改变方案走向的问题`（不点名） | 宿主判定可见能力不足时，一次 `decision` 域有界发现；选择后进入 S2 同一交互契约 |
| S5 | `解释 route-capability.ps1 里 fingerprint 校验的作用`（普通单轮） | 无 cold discovery、无 child、无副作用 |
| S6 | `只列出 decision 域候选和契约，不要加载不要执行` | router 仅返回候选/闭包/availability/contract；`candidate_discovery_only` |
| S7 | 受控写场景（如冷技能产出报告） | 只写 `reports/cold-skill-eval/<run-id>/`；记录 exact write set、最低验证与回滚 |
| S8 | 官方一手资料外部读取（如 `microsoft-docs` 冷技能） | 仅官方页面且网络可用时执行；否则记 `platform_na`，不阻塞其余场景 |

- 隐式正例与负例各需三个独立 fresh-host 轮次：正例必须表现为一次有界链路；负例三次均不得发生冷发现或 child。任何未经 admission 的写入、外部调用，或把交互契约塞给 runner，都是硬失败。
- 域内候选超过 `MaxCandidates`（默认 12）必须返回 `domain_hint_required` 与零候选；出现字母序截断即失败。

## 3. Live receipt 格式（ignored: `reports/cold-skill-eval/<run-id>/receipt.json`）

每场景一条记录，只接受宿主/工具事件作为证据，不接受助手口头宣称：

```json
{
  "scenario": "S3",
  "request_verbatim": "<原始请求语句>",
  "host_visible": "pass|fail|not_observable",
  "implicit_candidate": "pass|fail|not_observable",
  "cold_discovery_attempted": "pass|fail|not_observable",
  "candidate_load_validated": "pass|fail|not_observable",
  "skill_md_loaded": "pass|fail|not_observable",
  "native_child_started": "pass|fail|not_observable",
  "child_id_or_reason": "<agent id 或 not_observable 原因>",
  "execution_contract": "<mode>/<native_agent>",
  "side_effect_authorized": "read_only|controlled_write|none",
  "writes_or_external_calls": ["<exact write set / url 或空>"],
  "truth_boundary": "repo_verified|filesystem_projected|host_loaded|live_accepted",
  "live_result_accepted": "pass|fail",
  "evidence": { "event_ref": "<命令/文件/child 输出引用>", "observed_at": "<时间戳>", "output_sha256": "<原始输出哈希或 null>" }
}
```

- `pass` 必须带 event/receipt 引用、时间与原始输出哈希或 child id；无法由宿主观察的字段标 `not_observable`，不得推断为成功。
- 已知失效模式回归（必须全绿）：junction 形态 catalog（`-CatalogPath`、`SKILLS_MANAGER_CAPABILITY_CATALOG`、跨根 env var）一律规范化为物理对照；规范化失败、失效 hash、越界闭包、任意 reparse 逃逸继续 fail-closed（见 `tests/Unit/CapabilityRouterCrossRepo.Tests.ps1`）。

## 4. 步骤与停止条件

1. focused Pester：两个 router 测试文件全绿（`repo_verified`）。
2. `build.ps1` + `skills.ps1` 无生成漂移；`run-local-quality-gates.ps1 -Profile auto`。
3. 提交本切片（本地 main，不 push）；工作树洁净后执行显式投影 `pwsh -NoProfile -File .\skills.ps1 构建生效`。
4. 从 `.zcode` / `.agents` junction 与仓内 router 实跑 S1–S8（含 junction env var 回归）；落 receipt（`live_accepted` 仅限带事件证据的链路；router 层为 `repo_verified`）。
5. 停止：不 push、不发布、不自动扩展到全部 78 个冷技能的真实执行、不改宿主 auth/provider/插件缓存。
