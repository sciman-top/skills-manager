# 跨宿主模型编排路线图

**状态**：design-only；不授权选择实现仓、修改 host、发起模型请求或启动真实任务
**唯一细化任务来源**：[实施计划](cross-host-model-orchestration-implementation-plan.md)
**关联**：[PRD](cross-host-model-orchestration-prd.md) · [架构](cross-host-model-orchestration-architecture.md) · [验收 Runbook](../runbooks/cross-host-model-orchestration-acceptance.md)

## 0. 阶段原则

路线图只建立“人工声明 -> scoped route update -> 可选受控投影”的最薄主链。任何自动外部状态决策、网关/账号枚举、外部请求验证、失败自动恢复或后台改变 route 的能力都不在本路线图范围内。

| 状态 | 含义 |
| --- | --- |
| `not_started` | 尚无实现仓或前置决策未完成 |
| `repo_verified` | 目标 runtime 的代码、schema、fixture 和最低门禁通过 |
| `filesystem_projected` | 在当前授权下完成了精确目标的 hash/backup/rollback 文件事务 |
| `host_loaded` | fresh host 有可观察证据说明其采用了计划中的配置/启动参数 |
| `live_accepted` | 指定 host + identity + route + workload 完成真实工作并有独立验证 |
| `blocked` | 无静态 contract、无安全 mapping、无授权或风险越界；不是降级理由 |

任何较低层证据都不能推导更高层状态。

## 1. 阶段总览

| 阶段 | 最小目标 | 进入条件 | 退出证据 | 不解锁 |
| --- | --- | --- | --- | --- |
| R0 | 冻结设计并选择 runtime owner/root | 本文档集 review | owner、root、首期 host、五 slot/当前三 route key 书面决定 | 修改 host、验证模型 |
| R1 | 离线 policy/default/override/resolver | R0 | schema + fixture + resolver tests | 网络、宿主启动 |
| R2 | Codex 静态 Adapter 与 dry-run | R1 + 可复核本机静态事实 | contract/command plan tests | 读取/写入 `~/.codex` |
| R3 | Codex scoped state 与受控投影 POC | R2 + 目标 ownership/授权 | plan/backup/hash/rollback transaction tests | 自动更新或运行期改配置 |
| R4 | 三套 GPT-5.6 三档 preset | R1 | Sol-only/Terra-only/Luna-only policy tests | 任意 effort 都自动可用 |
| R4.5 | 只读 Preset Review | R4 + route/adapter receipt | keep/promote/demote/block 建议 | 自动推广或写配置 |
| R5 | ZCode 静态 Adapter/default | R1 + ZCode static facts | dry-run/contract tests | 从 Codex 推导 ZCode 能力 |
| R6 | Claude Code 静态 Adapter/default | R1 + Claude static facts | dry-run/contract tests | 从 ZCode/Codex 推导 Claude 能力 |
| R7 | 人工证据的 promotion workflow | R4.5 + 同类 verifier 结果 | reviewed policy patch 与 rollback | 自动 benchmark/提权 |
| R9 | 离线日常运维命令 | R1 | resolve/status/receipt/rollback tests | watcher、probe、后台修复 |

## 2. R0：实现归属和配置边界

**目标**：确定实际的 `<runtime-root>`、owner、首期宿主、首期写入目标和权限模型。没有 root/owner 时，文档外的后续任务必须 `blocked`。

必须明确：

1. runtime 是既有 host-local repo/受控 Cockpit 扩展，还是另一个已存在治理 runtime；不得默认放进 skills-manager。
2. 首期只接 `codex_cli`，还是另一个拥有可复核 model selection surface 的宿主。
3. Codex default 是否启用 `gpt56_sol_only`，并由静态合同确认 Sol/low、medium、xhigh。
4. private state root、receipt root、精确 projection target、当前授权、backup 与 rollback entry。

**停止条件**：决定需要读取 token、改登录、切 OAuth、重启应用或观察实时可用性时，停止在 design decision，保留当前 runtime。

## 3. R1：离线策略和人工声明主链

**目标**：在零网络、零 host 写入下，实现 workload/risk 分类、三档模板、private default/override、receipt 和精确的一句话 parser。

退出条件：

- policy 对未知字段、未知 candidate、effort 不在静态 allowlist、scope 不匹配、风险越界、过期 emergency approval、损坏 private state 均 fail closed；
- precedence 可稳定得到 `manual_override -> operator_override -> host_default`；
- `gpt56_sol_only`、`gpt56_terra_only`、`gpt56_luna_only` 都按相同三条基础 route key 解析，并固定映射到五个 execution slot；未来 route-key 数量可以演进，但 slot 不随模型档位变化；
- Sol-only 为 `Sol/xhigh / Sol/medium / Sol/low`；Terra/Luna-only 为 `xhigh / high / medium`；Luna high-risk 必须 block；
- “当前 Codex 只有 Terra 可用，切 Terra-only 并落盘”只更新 current Codex/current identity 的 override；“恢复默认”只移除该 override；
- 任何问句、模糊命令、无 host、未知 model/effort、跨 host 泛化均零写入；
- offline receipt 标明 `operator_declared_unverified`，而不是模型可用事实。

**明确不做**：模型列表、OAuth、网关、请求、健康、失败重试或自动 fallback。

## 4. R2-R4：Codex 的可验证最薄链

R2 只把已经人工复核的 Codex help/schema/source 事实编成 `StaticAdapterContract` 和 dry-run launch plan；不猜未出现的 config key，也不读取用户目录。

R3 先验证是否存在一个可拥有、可恢复、只含 model/profile/effort 的 native target。若无，Adapter 返回 `launch_only` 或 `manual_host_selection_required`，不以“可以传 CLI 参数”推断持久配置可写。若有，才能建立：

```text
plan -> token -> canonical target -> before hash -> backup
     -> atomic apply -> after hash -> receipt -> exact rollback
```

R4 将三个日常 GPT 预设加入 policy/fixture：

| preset | light 通道 | standard 通道 | deep 通道 | 高风险门 |
| --- | --- | --- | --- | --- |
| `gpt56_sol_only` | Sol/low | Sol/medium | Sol/xhigh | Sol/xhigh + policy |
| `gpt56_terra_only` | Terra/medium | Terra/high | Terra/xhigh | Terra/xhigh + emergency |
| `gpt56_luna_only` | Luna/medium constrained | Luna/high constrained | Luna/xhigh constrained | blocked |

这里的 phase exit 只到 `repo_verified`，或在明确 host 写入授权下到 `filesystem_projected`。不得把成功投影或 command plan 说成模型已可用。

## 5. R4.5：Preset Review

用户要求“全面审查各宿主预设是否最优”时，进入只读 R4.5。输入只限 static contract、policy/default/override revision、route/outcome receipt、相同类型 verifier、工作区/风险条件与 rollback point。

review 至少检查：

1. 三个基础 effort 是否确实能由当前静态 contract 表达；
2. 五个 execution slot 是否仍具有独立 operation、写集、验证或风险差异；改变 slot 必须是具迁移/兼容/rollback 的 major change，而模型档位演进只应修改 route-key map；
3. Terra/Luna 的 constrained 限制是否和写集、验证与风险相称；
4. evidence 是否混用了不同 host/identity/gateway/context；
5. 推荐是 `keep`、`promote`、`demote`、`block` 或 `insufficient_evidence`，最小补证和 rollback 是什么。

R4.5 不请求模型、不验证网关、不写任何 plane。对当前基线，保守结论是：Sol-only keep；Terra critical keep_emergency；Luna critical block；GLM/DeepSeek Flash 的高 effort 至少保持 constrained，除非有该宿主内的可比较 verifier 证据。

## 6. R5-R6：ZCode 和 Claude 的独立接入

两个宿主都从一次可复核的静态事实采集开始：版本/help/schema/source、可表达的 model/effort 字段、identity surface、launch surface、可投影 target 及 rollback entry。这个采集由实施/维护者显式触发并提交 fixture；运行时不自动读取。

| host | 静态三槽位 default | R5/R6 最小验收 | 不可推导 |
| --- | --- | --- | --- |
| ZCode | GLM-3.5-Flash/low（轻量）；high（有界/标准 review）；max（深度 constrained）；high-risk block | offline plan + contract tests | Flash/max 等于 critical |
| Claude Code | DeepSeek V4 Flash/high（轻量）；Flash/max（有界 constrained）；V4 Pro/max（深度）；Pro/max + policy（高风险） | offline plan + contract tests | Claude 成功代表 ZCode/Codex，或 Pro/max 自动获批 |

若 target ownership、schema 或模型选择面不能被验证，返回 handoff/manual，不能编辑 `.zcode`、Claude 用户配置或认证资产。

## 7. R7 与 R9：人工 promotion、离线运营

R7 只把人工收集、同类可比较且经过 verifier 的结果，转化为一个 reviewed policy promotion/rollback patch。它不是自动 benchmark、排行榜或学习系统。

R9 仅提供：

- `status`：查看 private default/override 与真值边界；
- `resolve --offline`：解析下一任务 route；
- `receipt inspect`：查看脱敏 route/projection/outcome receipt；
- `restore-default`：删除一个 exact scoped override；
- `rollback`：按 private projection receipt 精确回滚。

这些命令都不启动 watcher、网络验证、账号操作、模型轮询或状态清理。

## 8. 全局停止与回滚

- 回滚只限当前阶段写入的 runtime source、private state、projection action 或 policy commit；不得覆盖其他身份、宿主或用户资产。
- 首次遇到 auth/identity 混淆、未知 target ownership、running-session 风险、成本/付费需求、静态接口不明、跨档争议或受控字段外写入时，停止当前 phase。
- 不因官方文档检索、web、认证工具或 gateway 报错改变当前可用编码路径。
- 文档、test、private receipt、host projection 和新任务验收必须分别报告，不外推。
