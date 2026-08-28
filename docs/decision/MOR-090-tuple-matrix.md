# MOR-090 tuple matrix（生成视图，勿手改）

canonical source 为同目录 MOR-090-tuple-matrix.json；本文件由其生成。校验：pwsh -NoProfile -File scripts/quality/validate-mor-tuple-matrix.ps1。

规则：每行唯一 tuple；只有 status=verified 的行可进 Adapter allowlist，最终 route 候选还须宿主侧与 provider 侧同时 verified（交集）；禁止跨 surface 外推；非 verified 行解析时一律 manual_mapping_required。claude_host tuples 尚未生成（exact model 未钉定，MOR-400 生成，见 JSON _meta.pending_surfaces）。

| surface | layer | exact_model | exact_effort | field_path | status | facts | notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| openai_responses | provider_dialect | gpt-5.6-sol | none | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-sol | low | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-sol | medium | reasoning.effort | verified | C6 | 官方默认 |
| openai_responses | provider_dialect | gpt-5.6-sol | high | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-sol | xhigh | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-sol | max | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-terra | none | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-terra | low | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-terra | medium | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-terra | high | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-terra | xhigh | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-terra | max | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-luna | none | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-luna | low | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-luna | medium | reasoning.effort | verified | C6 | 官方默认 |
| openai_responses | provider_dialect | gpt-5.6-luna | high | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-luna | xhigh | reasoning.effort | verified | C6 |  |
| openai_responses | provider_dialect | gpt-5.6-luna | max | reasoning.effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-sol | none | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-sol | low | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-sol | medium | reasoning_effort | verified | C6 | 官方默认 |
| openai_chat_completions | provider_dialect | gpt-5.6-sol | high | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-sol | xhigh | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-sol | max | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-terra | none | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-terra | low | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-terra | medium | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-terra | high | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-terra | xhigh | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-terra | max | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-luna | none | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-luna | low | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-luna | medium | reasoning_effort | verified | C6 | 官方默认 |
| openai_chat_completions | provider_dialect | gpt-5.6-luna | high | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-luna | xhigh | reasoning_effort | verified | C6 |  |
| openai_chat_completions | provider_dialect | gpt-5.6-luna | max | reasoning_effort | verified | C6 |  |
| codex_config_surface | host_adapter | gpt-5.6-sol | low | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-sol | medium | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-sol | high | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-sol | xhigh | model_reasoning_effort | partial | C1 | model-dependent，待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-terra | low | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-terra | medium | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-terra | high | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-terra | xhigh | model_reasoning_effort | partial | C1 | model-dependent，待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-luna | low | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-luna | medium | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-luna | high | model_reasoning_effort | partial | C1 | 待 MOR-100 fixture |
| codex_config_surface | host_adapter | gpt-5.6-luna | xhigh | model_reasoning_effort | partial | C1 | model-dependent，待 MOR-100 fixture |
| codex_security_cli_surface | host_adapter | gpt-5.6-sol | max | security-scan effort selector | candidate | C2 | 独立 surface，单列候选 |
| zcode_ui | host_adapter | glm-5.3-flash | low | UI effort 选择（低） | operator_declared | Z3 | UI 截图 artifact，附件留存前不升级 |
| zcode_ui | host_adapter | glm-5.3-flash | high | UI effort 选择（高） | operator_declared | Z3 | UI 截图 artifact，附件留存前不升级 |
| zcode_ui | host_adapter | glm-5.3-flash | max | UI effort 选择（最高） | operator_declared | Z3 | UI 截图 artifact，附件留存前不升级 |
| deepseek_anthropic_messages | provider_dialect | deepseek-v4-flash | low | output_config.effort | verified | D3 |  |
| deepseek_anthropic_messages | provider_dialect | deepseek-v4-flash | high | output_config.effort | verified | D3 |  |
| deepseek_anthropic_messages | provider_dialect | deepseek-v4-flash | max | output_config.effort | verified | D3 |  |
| deepseek_anthropic_messages | provider_dialect | deepseek-v4-pro | low | output_config.effort | verified | D3 |  |
| deepseek_anthropic_messages | provider_dialect | deepseek-v4-pro | high | output_config.effort | verified | D3 |  |
| deepseek_anthropic_messages | provider_dialect | deepseek-v4-pro | max | output_config.effort | verified | D3 |  |
| deepseek_chat_completions | provider_dialect | deepseek-v4-flash | low | reasoning_effort | verified | D4 |  |
| deepseek_chat_completions | provider_dialect | deepseek-v4-flash | high | reasoning_effort | verified | D4 |  |
| deepseek_chat_completions | provider_dialect | deepseek-v4-flash | max | reasoning_effort | verified | D4 |  |
| deepseek_chat_completions | provider_dialect | deepseek-v4-pro | low | reasoning_effort | verified | D4 |  |
| deepseek_chat_completions | provider_dialect | deepseek-v4-pro | high | reasoning_effort | verified | D4 |  |
| deepseek_chat_completions | provider_dialect | deepseek-v4-pro | max | reasoning_effort | verified | D4 |  |
| deepseek_responses | provider_dialect | deepseek-v4-flash | low | reasoning.effort | unknown |  | 无直接一手页面 |
| deepseek_responses | provider_dialect | deepseek-v4-flash | high | reasoning.effort | unknown |  | 无直接一手页面 |
| deepseek_responses | provider_dialect | deepseek-v4-flash | max | reasoning.effort | unknown |  | 无直接一手页面 |
| deepseek_responses | provider_dialect | deepseek-v4-pro | low | reasoning.effort | unknown |  | 无直接一手页面 |
| deepseek_responses | provider_dialect | deepseek-v4-pro | high | reasoning.effort | unknown |  | 无直接一手页面 |
| deepseek_responses | provider_dialect | deepseek-v4-pro | max | reasoning.effort | unknown |  | 无直接一手页面 |

tuple_status 枚举：verified | partial | candidate | operator_declared | unknown。
