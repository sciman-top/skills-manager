# MOR-090 §5.1 逐项 (surface, exact_model, exact_effort) tuple 矩阵

**规则**：每行是唯一 tuple；只有 `tuple_status=verified` 的行可进 Adapter allowlist；`fact_ids` 仅指向上文证据行，不作为 allowlist 依据；任何跨 surface 外推（如 `openai_api` 的 `max` → `codex_config_surface`）一律禁止。`partial`/`candidate`/`operator_declared`/`unknown` 行在对应 fixture 取证并升级为 `verified` 前，一律按 `manual_mapping_required` 解析。

| surface | exact_model | exact_effort | tuple_status | fact_ids |
| --- | --- | --- | --- | --- |
| openai_api | gpt-5.6-sol | none | verified | C6 |
| openai_api | gpt-5.6-sol | low | verified | C6 |
| openai_api | gpt-5.6-sol | medium | verified | C6 |
| openai_api | gpt-5.6-sol | high | verified | C6 |
| openai_api | gpt-5.6-sol | xhigh | verified | C6 |
| openai_api | gpt-5.6-sol | max | verified | C6 |
| openai_api | gpt-5.6-terra | none | verified | C6 |
| openai_api | gpt-5.6-terra | low | verified | C6 |
| openai_api | gpt-5.6-terra | medium | verified | C6 |
| openai_api | gpt-5.6-terra | high | verified | C6 |
| openai_api | gpt-5.6-terra | xhigh | verified | C6 |
| openai_api | gpt-5.6-terra | max | verified | C6 |
| openai_api | gpt-5.6-luna | none | verified | C6 |
| openai_api | gpt-5.6-luna | low | verified | C6 |
| openai_api | gpt-5.6-luna | medium | verified | C6 |
| openai_api | gpt-5.6-luna | high | verified | C6 |
| openai_api | gpt-5.6-luna | xhigh | verified | C6 |
| openai_api | gpt-5.6-luna | max | verified | C6 |
| codex_config_surface | gpt-5.6-sol | low | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-sol | medium | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-sol | high | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-sol | xhigh | partial（model-dependent，待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-terra | low | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-terra | medium | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-terra | high | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-terra | xhigh | partial（model-dependent，待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-luna | low | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-luna | medium | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-luna | high | partial（待 MOR-100 fixture） | C1 |
| codex_config_surface | gpt-5.6-luna | xhigh | partial（model-dependent，待 MOR-100 fixture） | C1 |
| codex_security_cli_surface | gpt-5.6-sol | max | candidate | C2 |
| zcode_ui | glm-5.3-flash | low | operator_declared（UI 截图） | Z3 |
| zcode_ui | glm-5.3-flash | high | operator_declared（UI 截图） | Z3 |
| zcode_ui | glm-5.3-flash | max | operator_declared（UI 截图） | Z3 |
| claude_host | <exact model 待 MOR-400 钉定> | low | unknown（按 model 分列，MOR-400 fixture） | A2a |
| claude_host | <exact model 待 MOR-400 钉定> | medium | unknown（按 model 分列，MOR-400 fixture） | A2a |
| claude_host | <exact model 待 MOR-400 钉定> | high | unknown（按 model 分列，MOR-400 fixture） | A2a |
| claude_host | <exact model 待 MOR-400 钉定> | xhigh | unknown（按 model 分列，MOR-400 fixture） | A2a |
| claude_host | <exact model 待 MOR-400 钉定> | max | unknown（按 model 分列，MOR-400 fixture；持久化面见 A2b） | A2a/A2b |
| deepseek_provider | deepseek-v4-flash | low | verified | D3/D4 |
| deepseek_provider | deepseek-v4-flash | high | verified | D3/D4 |
| deepseek_provider | deepseek-v4-flash | max | verified | D3/D4 |
| deepseek_provider | deepseek-v4-pro | low | verified | D3/D4 |
| deepseek_provider | deepseek-v4-pro | high | verified | D3/D4 |
| deepseek_provider | deepseek-v4-pro | max | verified | D3/D4 |

**allowlist 初始集**（= `tuple_status=verified` 行，共 24 行）：openai_api 3 模型 × 6 档（18）+ deepseek_provider 2 模型 × 3 档（6）。在目标 runtime Adapter 落地前仅作为合同底稿，不构成任何宿主可用性断言。`zcode_ui` 3 行为 operator_declared、`claude_host` 5 行为 unknown、codex_config 12 行为 partial、security 面 1 行为 candidate——均不进 allowlist，解析时 `manual_mapping_required`。
