# P6 host read-only acceptance

Date: 2026-08-11

## Scope and immutable boundaries

This closeout executed the P6-015 read-only host probes after repository verification. It did not modify Codex configuration, the user skill root, provider/auth/session settings, plugins, MCP, or the managed projection. It did not restart the host. The accepted truth boundary remains:

`repo_verified != host_inventory_loaded != host_invocation_observed != live_accepted`

## Repository verification

- Pre-acceptance full receipt: `qgr-20260811-040114-d5c6cd0a` through `reports/quality-gates/current.json`.
- Result: full profile passed with 15 gates, 985/985 Pester cases, 89 valid skills, generated sync, dependency baseline, skill metadata, planning contract, and source stability passing.
- Final exact-current receipt remains resolved through the stable `reports/quality-gates/current.json` pointer after this tracked closeout update.

## Fresh SkillSurfaceView probe

Command:

```powershell
.\skills.ps1 capability-inventory --view skill-surfaces --json
```

| Surface | Count | Coverage | Freshness | Authority |
| --- | ---: | --- | --- | --- |
| `repo_supply` | 89 | `complete` | `fresh` | `repository_generated_supply` |
| `canonical_projection` | 0 | `not_observed` | `unknown` | `projection_manifest` |
| `user_skill_root` | 6 | `complete` | `fresh` | `filesystem_observation` |
| `system` | 6 | `complete` | `fresh` | `host_filesystem` |
| `plugin_cache` | 45 | `complete` | `fresh` | `host_plugin_cache` |
| `host_visible` | 0 | `not_observed` | `unknown` | `host_snapshot` |

The probe returned `writes=0`, `provider_calls=0`, `native_mutations=0`, and left Git status unchanged. `canonical_projection` and `host_visible` are intentionally not observed because this slice used `构建生效 -SkipHostProjection` and supplied no host snapshot. Count differences are therefore source-explained and do not establish host invocation.

## Fresh host skill-selection sample

The host CLI was `codex-cli 0.146.1`. A fresh ephemeral read-only task used `gpt-5.6-sol` with `model_reasoning_effort=medium`, made no tool calls, and returned:

```json
{"selected_skills":["custom-powershell-windows-automation"],"reason":"匹配PS7、Windows自动化与安全写入"}
```

The task reported 26,639 input tokens, 2,816 cached input tokens, and 34 output tokens. This is model self-report only. It is useful selection evidence but cannot prove `SKILL.md` injection or execution.

## Formal invocation acceptance

The non-executing formal invocation plan returned `truth_level=host_evaluation_partial`, `provider_calls=0`, and no repository change. Execute mode was not admitted because both required authoritative inputs were unavailable:

- no schema-v1 receipt with `authority=native_host_events` containing fresh same-skill same-correlation `injected -> executed` events;
- no exact-current `reports/skill-projection/current.json`, because host projection was explicitly skipped.

A fresh selection evaluator attempt failed closed on the missing exact-current projection snapshot before dispatch. Reusing an older projection would be stale evidence and was rejected. Therefore `host_invocation_observed=not_observed` remains unchanged.

## Subagent lifecycle acceptance

The requested first wave attempted to spawn `gpt-5.6-sol/low` and then continue with `gpt-5.6-sol/medium`, followed by a second-wave `gpt-5.6-sol/xhigh`. The first spawn was rejected by the host with:

```text
agent thread limit reached
```

The live agent tree exposed only `/root`; there was no completed child to close or slot to release. The host did not expose the root model/effort receipt either. The three-tier lifecycle result is therefore `platform_na`, not passed. No scheduler or model router was implemented in this repository.

Official OpenAI documentation states that current local Codex releases support direct-request subagent workflows, configurable agent model/reasoning settings, and `agents.max_concurrent_threads_per_session`: <https://learn.chatgpt.com/docs/agent-configuration/subagents>. The observed thread-limit rejection is a host/runtime acceptance gap, not proof that repository orchestration should be restored.

## Controlled lifecycle consequence

`skill-evolution apply` promotes only an evaluated package into `overrides/custom/<skill>`. New skills remain cold-catalog-only. This closeout did not add names to `managed_link_includes`, run host projection, enable a host-visible skill, or retire a package. Activation/projection and retirement remain separate reviewed, receipt-backed operations; repository source promotion is not host enablement.

## Final truth

- repository: `repo_verified` after the exact-current full gate pointer is refreshed;
- host selection: fresh self-report observed, but only `host_evaluation_partial`;
- host inventory: existing P6 inventory truth is retained; this probe did not supply a `host_visible` snapshot;
- invocation: `host_invocation_observed=not_observed`;
- subagent lifecycle: `platform_na` because the host rejected the first child at its thread limit;
- live business workflow: `live_accepted=not_accepted`.
