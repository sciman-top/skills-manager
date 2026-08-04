# Portable Capability Catalog Correction Evidence

**date**: 2026-08-04
**program_id**: `skills-manager-vnext`
**track**: P5-local hierarchical discovery follow-up
**status**: `repo_verified`
**verification_ceiling**: `repo_verified + current_user_projection_verified`
**P6_ADMISSION_STATUS**: `hold`
**M1_PILOT_STATUS**: `collecting_0_of_10`
**LIVE_ACCEPTANCE_STATUS**: `not_run`

## Authorization and problem evidence

用户要求继续自动修复 capability routing 的已知天然限制、跨仓失效与 token/治理成本。复核证明此前 32/32 selection 与 8/8 cold-load 只覆盖 `skills-manager` 自身可见配置：用户级 `capability-router` 在普通目标仓找不到向上级 `reports/skill-projection/current.json` 时可返回 0 domain/0 candidate；47 个 canonical but unrouted skill 也没有稳定 cold-discovery 入口。profile 同时承担预热预算与 cold index，是这两个现象的共同根因。

进一步真实 probe 发现，portable router 重新用单行正则读取 `SKILL.md` description，导致 YAML block scalar 的 `prompt-engineering-patterns` 被降级成字面量 `>-`，直接损害宿主语义选择输入。读取 skill entrypoint 的只读授权也曾与 skill 工作流内的写入授权混写，routing policy 的同能力多组 metadata 曾被后写覆盖。

## Adopted design

```text
profile = 宿主任务边界预热与 metadata 预算
portable catalog = 完整 canonical cold-discovery index
host AI = 唯一语义选择者
router script = containment、availability、load 与 execution policy
```

- build/projection 从 canonical inventory、`skill_projection.discovery_catalog` 和 routing policy 幂等生成 `agent/capability-router/catalog.json`。
- catalog 只保存规范化 metadata、相对路径、domain membership 与 routing rules，随 router 包投影到 `~/.agents/skills`。
- router 优先读取相邻 catalog；显式 manifest/config/policy 保留兼容，但普通跨仓调用不再依赖它们。
- catalog description 是 cold discovery metadata 真源；router 仍复核路径 containment、文件存在与 skill name。
- 47 个原 `unrouted` canonical skill 全部进入现有 domain，不加入 resident profile，因此不增加宿主初始 metadata 预算。
- `load_side_effect=read_only` 与 `workflow_side_effect/execution_policy` 分离；可读取 operator skill 不等于已授权执行写入。
- lexical `required_intents/excluded_intents` 死配置删除；routing rules 保留多组 provenance，不再静默覆盖。
- evaluator 改为无关非 Git CWD、真实用户级 router 路径，并区分 cumulative/cached/uncached input 与可观测 command count；未执行新的付费 host replay。
- 上游 code-review skill 的 351 行五轴全量评审、每次变更必审与多模型建议被小型 override 收敛为按风险审查；通用反引号文案不进入 package 硬门禁，避免把示例文本误当资源声明并派生补丁资产。

## Write set and boundaries

本切片修改 projection、router override、routing/evaluator verifier 与测试、`skills.json` discovery mapping、PRD/architecture/roadmap/current spec/plan/todo/root contract，并新增一份 code-review override、cross-repo regression test 和本 evidence。`agent/`、runtime report 与用户 skill root 只由现有 `构建生效` 生成/投影，不手改。

未修改 provider、auth、model、sandbox、session、plugin/MCP 安装或生产系统；未重启 Codex；未执行付费模型调用；未创建 P6 manifest、schema major、daemon、数据库、第二模型或新 track/task count。

## Verification record

| Check | Result |
| --- | --- |
| Regression red | portable block-scalar description initially returned `>-`; clean worktree 的 routing verifier 因缺少 ignored projection report 失败；篡改 `host_selected` 时临时 inventory 首版错误自证 |
| Focused green | routing verifier 3/3、cross-repo 1/1、skill integrity 11/11、skill projection 32/32 |
| Managed build/projection | `mappings=97`, non-empty `overrides=14`, agent skills `108`, projection entries/unique `111/111`, conflicts `0`, active profile `default`, user projection `persisted=True`; reconciliation remains advisory |
| Real cross-CWD probe | user home, unrelated Git repo and nested directory all resolved `~/.agents/skills/capability-router/catalog.json`; no manifest/config/policy; engineering includes `codebase-design`; zero write |
| Clean-worktree contract | fresh detached worktree without `agent/` or projection report: build passed; 30-case verifier zero finding; routing tests 4/4; ignored dependencies remained absent |
| Routing/config/integrity/planning contracts | capability routing `30/30`, semantic auto-selection `0`, side-effect violation `0`; skill routing pass (`default`, active `7`, external `12`); skill integrity `107`, errors/warnings `0/0`; skills config enforce pass with one existing legacy-schema observation; P5 `5/5`; Lean design `4/4`, M1 `collecting 0/10`, P6 hold |
| Full local quality gate | 2026-08-04 23:52–23:55 +08:00, exit `0`; Unit `782/782`, E2E `18/18`; build, repo hygiene, generated sync, skill integrity/routing, dependency, config, host-capability, planning and doctor contracts all passed; total `167183 ms` |
| Diff/Git boundary | full gate 后 `git diff --check` exit `0`; `HEAD == origin/main == a9cc3001`；本切片提交/推送状态由最终 Git closeout 命令记录 |

## Governance-weight follow-through

- `cd420241` 把 Lean planning fixture 从复制 P0-P5 全历史改为最小成功/失败 stub，并保留一次真实集成检查；该文件从约 15.9 秒降至约 6.3 秒。
- `a9cc3001` 让 30-case router verifier 复用带文件长度和 mtime 失效的 metadata cache；热点从约 16.8 秒降至约 12.6–13.3 秒。
- 当前 corpus verifier 只验证 tracked corpus/policy/config/router，始终构造语料所需的最小临时 manifest；deployment catalog 的生成与跨仓消费由各自最低充分测试层证明。
- 删除通用反引号资源扫描、9 份为其补齐的重复 checklist 资产、resource-overlay 新抽象与相应测试；保留 Markdown link、OpenAI manifest resource、MCP dependency 等结构化声明检查。
- catalog 只由 projection seam 生成；不在 agent build 与 projection 两处重复扫描完整技能 inventory。

## Rollback

仅撤销本 evidence 所列 tracked 增量，然后运行 `build.ps1` 与 `skills.ps1 构建生效` 从恢复后的 source 重建 `skills.ps1`、`agent/` 与受管 projection。不得覆盖历史 P0-P5/Lean/profile evidence、独立 M1 registry、无关用户改动、auth/provider/plugin/session 或外置源码。

## Truth boundary

本切片最多证明 portable cross-repo catalog/runtime 为 `repo_verified`，且当前用户 projection 的三种 CWD 形状通过。历史 32/32 selection、8/8 cold-load 继续是 `host_evaluation_partial`；没有新的 fresh paid host replay，没有 M1 样本，没有普遍 token 降低或真实业务 `live_accepted` 证据。宿主语义概率性、fresh-task 固定上下文与稳定 skill-body invocation trace 缺口仍是天然边界。
