# Global skill dispatch correction

**日期**: 2026-08-07
**范围**: `capability-router`、portable catalog、宿主-facing trigger contract
**truth level**: `repo_verified + host_prompt_contract_verified`
**host automatic invocation**: `not guaranteed by official skill contract`
**live_accepted**: `not_run`

## 结论

用户看到的“profile / cold-load 都不能按请求自动命中”不是 47 个技能被删除，也不是 `grill-with-docs` 再次丢失。根因是入口职责被拆成了两个概率性步骤：Codex 初始 prompt 只暴露预算内的 skill metadata；随后是否隐式调用 `capability-router` 由宿主模型依据 description 自主决定。仓库原来的 router description 又把它限定成“仅在没有 visible matching skill 时才用”的 fallback，因此宿主可能在看不到 cold skill 时直接跳过 router。portable catalog 只证明 router 被调用后能发现技能，不能强制宿主调用它。

另一个确定性缺口在本仓脚本：没有 `DomainHint`/`ProfileHint` 时，旧实现默认使用 `current_profile`。从 router 相邻 catalog、无 `skills-manager` manifest/config 的普通工作目录启动时没有 current profile，结果只能返回 domain 摘要或 0 个候选；这与“无需 profile 即可 cold-load”目标冲突。

## 官方约束与本仓事实

- OpenAI [Build skills](https://learn.chatgpt.com/docs/build-skills.md) 规定 progressive disclosure：宿主先看到 `name`/`description`，选择后才读取完整 `SKILL.md`；Codex 初始 skill 列表最多占上下文 2%，未知上下文时上限为 8,000 字符，技能过多时可能缩短描述或省略技能。
- 同一官方页面只承诺 implicit invocation “can choose a skill when the task matches the description”，没有 pre-model middleware、强制 fallback 或 skill invocation trace 的保证。
- 当前 canonical inventory 为 111；active projection 为 12；profile membership 为 59；47 个技能在 portable catalog 中有完整 path/description/domain，但不在 default resident metadata。
- 2026-08-04 的 `a131349f` 有意把这 47 个技能从 profile membership 移入 `discovery_catalog.domain_memberships`，目标是保持 8,000 字符预算和 portable cold index。该迁移没有证明宿主会在每个任务自动触发 router，因此体验上的“回归”是入口契约未闭合，而非技能文件回滚。

## 本次修复

1. `route-capability.ps1` 在未提供 domain/profile hint 时改为 `global_catalog_discovery`，默认候选上限提高到 128（调用方可用 `-MaxCandidates 256`），不再隐式使用 current profile；显式 hint 仍保留为兼容性的窄域过滤。
2. 输出增加 `automatic_dispatch`，明确 `scope=all_catalog_skills`、`profile_switch_required=false`、`profile_mutation_allowed=false`；不会写 host、profile、provider、session 或文件。
3. `capability-router` metadata、`agents/openai.yaml` 和全局/project AGENTS contract 改为 resident dispatcher：每个可能受益于本地 skill 的非平凡请求先做一次 complete-catalog dispatch，再由宿主 AI 选择 1–3 个最小技能并进入 deterministic policy。
4. 新增 unit/cross-repo regression，覆盖无 hint、无 active profile、repo 外 CWD、cold skill candidate 和 zero-write 边界。

## 验证

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1          pass
CapabilityRouter.Tests + CapabilityRouterCrossRepo.Tests + verifier 34/34 pass
global_catalog_discovery candidates                              106, truncated=false
discovery_catalog.domain_memberships covered                      47/47
writing-plans / architecture-patterns cold policy               load_skill, load_allowed=true
profile_switch_required / profile_mutation_allowed               false / false
writes_performed                                                  false
```

## 未宣称的边界

本切片已经把仓库侧的可达性修复为“调用 dispatcher 即可看到完整 catalog，不需要人工 profile”。它不能把 Codex 的概率性 implicit invocation 伪装成硬保证：若宿主模型完全忽略 skill metadata、AGENTS contract 或工具调用，仓库没有官方 pre-model hook 可以强制它执行。若产品要求数学意义上的“每个请求必经路由”，下一层必须是宿主 middleware/app-server 的 pre-request injection，并由宿主提供 invocation trace；这不是继续膨胀 profile 或修改本仓 policy 能解决的问题。

## 回滚

只回滚本切片的 `overrides/custom/capability-router/**`、`config/skill-routing-policy.json`、`tests/Unit/CapabilityRouter*.Tests.ps1`、`AGENTS.md` 和本 evidence 文件；保留用户已有的 watch 改动。重新运行 `build.ps1`、受影响 Pester 和 full gate 后再恢复旧 projection。
