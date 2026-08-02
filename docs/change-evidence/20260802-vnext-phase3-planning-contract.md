# skills-manager vNext Phase 3 planning contract

## Result

- P3 已由新任务明确授权；current phase 从 P2 切换为 P3。
- 规划真源为 `tasks/skills-manager-vnext-phase3.tasks.json`，共 7 个最大合理切片。
- 当前仅 `SMV-P3-001 = done`；其余任务仍为 pending。

## Entry evidence

| Evidence | Current fact | Decision |
| --- | --- | --- |
| OpenAI Codex manual (current local fetch, 2026-08-02) | plugin 是 skills/MCP/optional UI bundle；manifest 为 `.codex-plugin/plugin.json`；local/repo/workspace/public 分层 | adopt official shape；host owns install/auth/runtime |
| `codex-cli 0.145.0` help | `plugin list --json --available`、`plugin marketplace list --json` 是只读入口 | adopt snapshot adapter；不执行 mutation |
| `openai/plugins@11c74d6b...` | examples use name/version/description/source/license/component paths；root license 不统一 | adopt per-plugin supply-chain lint |
| `skills.json` + `reports/skill-projection/current.json` | 四个 custom domain workflow 在多个 profile 中重复路由并投影 | two-workflow distribution demand established repo-side |
| current official/curated inventory | no equivalent junior classroom courseware + physics animation bundle | allow one teaching candidate；defer generic exporters |

## Scope decision

- Implement：三 scope snapshot inventory、manifest/source/version/license lint、Codex skills-only fixture exporter、static/behavior/non-blocking model-snapshot eval。
- Defer：MCP/UI、Claude/Gemini exporter、marketplace writer、plugin install、online model eval、public submission。
- Do not build：public marketplace、account/auth/session/runtime、daemon/database/GUI。

## Baseline and boundary

- `D:\CODE\skills-manager` was clean at task start despite the older handoff describing a dirty tree; live Git truth wins.
- `skills.json` SHA-256: `4FE42DC2DFA385F785A3BADE3650D011D4961E24F5FA5456900B8F2F3699053F`.
- Read-only reference hash: `08F260985FBE36E2659F2D93E5C8BF0E7F96CCE49AD7B794AFB39AA794BF4478`.
- No plugin install, host mutation, provider call, process restart, commit or push occurred.

## Rollback

Restore P2 plan/todo/current-phase docs and remove only the P3 spec/manifest/planning evidence. Do not change P0/P1/P2 evidence or external references.
