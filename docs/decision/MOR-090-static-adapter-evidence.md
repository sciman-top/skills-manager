# MOR-090：静态 Adapter 事实证据包（Codex / ZCode / Claude+DeepSeek）

**状态**：static-fact evidence；采集日期 2026-08-28。不是 `host_loaded`/`live_accepted`，不证明模型当前可用或参数被当前 gateway 接受
**证据状态词表**：`verified`（官方文档/本机 help 直证）｜`operator_declared`（操作者一手声明/界面证据，无独立附件复核）｜`inferred`（由命名/公告推断的精确值）｜`unknown`（无一手来源）。**只有 `verified` 条目可进 Adapter allowlist**。
**消费方**：未来 `<runtime-root>` runtime 的 Adapter contract/fixture（MOR-100/MOR-300/MOR-400）；runtime 未选定前 fixtures 不创建
**方法边界**：来源=官方产品文档 + 本机只读 `--help`/版本；未读取 `~/.codex`、`~/.zcode`、`CLAUDE_CONFIG_DIR` 等用户配置或凭据；未发送任何模型请求；社区资料仅作结构启发，不作为能力证据

## 1. codex_cli（本机 `codex-cli 0.150.1`）

| # | 事实 | 来源 | 状态 |
| --- | --- | --- | --- |
| C1 | config 字段 `model`（string）、`model_reasoning_effort` 官方词表 `minimal \| low \| medium \| high \| xhigh`，xhigh 为 model-dependent | Codex Configuration Reference（learn.chatgpt.com/docs/config-file/config-reference），2026-08-28 | verified（官方文档） |
| C2 | `max` 不在 `model_reasoning_effort` 词表内；security 扫描面官方文档另列 "minimal, low, medium, high, xhigh, and max" | 同上 + Codex Security CLI quickstart（learn.chatgpt.com/docs/security/cli），2026-08-28 | verified；`max` 记为 `surface=security_cli` 候选，禁止进入 config 面合同 |
| C3 | launch 面：`codex exec -m <MODEL>`、`-c <key=value>`（dotted path 覆盖 config.toml 值） | 本机 `codex exec --help`（0.150.1），2026-08-28 | verified（本机只读 help） |
| C4 | profile 机制：`$CODEX_HOME/profile-name.config.toml` 独立文件 + `--profile` 选择；project-scoped config 不可覆盖 provider/auth/profile selection | Configuration Reference，2026-08-28 | verified；additive profile 为投影 POC 首选候选 |
| C5 | 原生挂点：`review_model`（/review 模型覆盖）、`agents.default_subagent_model`、`agents.default_subagent_reasoning_effort`、`agents.max_concurrent_threads_per_session`（不含主线程） | Configuration Reference，2026-08-28 | verified；供未来 review route key / subagent 映射复用，本版不启用 |
| C6 | `gpt-5.6-sol` 模型 slug 真实（官方安全扫描推荐 "gpt-5.6-sol with xhigh reasoning effort"）；GPT-5.6 官方公告确认 Sol/Terra/Luna 三档横跨 ChatGPT/Codex/API，`gpt-5.6-terra` 有官方模型页 | Codex Security workbench + openai.com/index/gpt-5-6 + developers.openai.com/api/docs/models/gpt-5.6-terra，2026-08-28 | Sol/Terra slug `verified`（公告/模型页级）；`gpt-5.6-luna` 精确 slug 为 `inferred`（推断自公告命名，无独立 exact model page 直证）——不进 allowlist，保持 candidate，进 MOR-100 fixture 前须本机 help 或官方 exact page 证实 |

**未决**：`~/.codex/config.toml` 实际 shape/ownership/rollback entry（属 projection POC 采集，需独立授权）；`--profile` 在本机版本对 config profile vs permission profile 的精确语义。

## 2. zcode（GLM / bigmodel）

| # | 事实 | 来源 | 状态 |
| --- | --- | --- | --- |
| Z1 | GLM Coding Plan 当前阵容 GLM-5.3 / GLM-5.3-Flash / GLM-5.2 / GLM-5-Turbo；无 `GLM-3.5-Flash`（旧模板名，未见于当前阵容） | z.ai/subscribe + docs.bigmodel.cn 新品页，2026-08-28 | verified；旧名退出 static default |
| Z2 | 候选 slug `glm-5.3-flash`（GLM-5.3-Flash，2026-08-26 发布，Coding Plan 已全面放开） | docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash，2026-08-28 | verified |
| Z3 | surface 词表：Chat Completion API `reasoning_effort` 为枚举，GLM-5.2+ 支持 `low / high / max`（默认 `max`）——`verified`（官方文档）；ZCode 选择面提供 低/高/最高 三档与之对应——`operator_declared`（操作者界面截图，2026-08-28，artifact：`~/.zcode/cli/image-cache/sess_fe51fa41-48ad-4999-a591-903968c6fe16/image-c09cf0b5b9c0de7bf52238a342b48f13.png`，SHA-256 `6b79b0e22cd9c37fc8569cd5ff9631f77edefd5c5df663cd7585556f8d1514a5`；image-cache 为易失缓存，附件留存前该半边证据按 operator_declared 计） | docs.bigmodel.cn API 参考/核心参数/GLM-5.3 页 + 操作者截图 | 拆分：文档半边 verified；UI 半边 operator_declared |
| Z4 | `thinking` 不可关闭：GLM-5.3+ 始终启用思考，不再支持 `thinking.type: "disabled"`；默认 max 档 token 消耗显著 | GLM-5.3 模型页，2026-08-28 | verified；light 档语义须在 MOR-030 明示"low effort 仍思考" |
| Z5 | **投影面未取证**：ZCode 档位选择位于桌面 UI/计划层；控制面能否表达/投影该选择未知，预期 manual handoff | 无一手来源 | unknown → MOR-090 后续采集项；取证前 GLM route 一律 `manual_mapping_required` |

**未决**：ZCode identity surface（`builtin:bigmodel-coding-plan/<model>` 标识与选择面的关系）；第三方网关对 `reasoning_effort` 的映射差异（如经非官方端点，须按 surface 另立合同）。

## 3. claude_code（宿主面；本机 `Claude Code 2.1.247`）

| # | 事实 | 来源 | 状态 |
| --- | --- | --- | --- |
| A1 | 模型选择优先级：`/model` > `--model` > `ANTHROPIC_MODEL` > settings `"model"` > `ANTHROPIC_DEFAULT_MODEL`；`/model` 自 v2.1.153 可持久写入用户 settings | code.claude.com/docs/en/model-config，2026-08-28 | verified；settings `"model"` 为候选投影字段 |
| A2 | effort 面：`/effort`、`--effort`、`CLAUDE_CODE_EFFORT_LEVEL`、settings `"effortLevel"`；词表 `low..max`，model-dependent（Opus 4.6/Sonnet 4.6 上限 high） | 同上 | verified |
| A3 | **clamp 行为**：不支持的档位静默向下降档（"xhigh runs as high on Opus 4.6"） | 同上 | verified；fixture 必须留痕，请求≠观察不得标 `host_loaded` |
| A4 | **fallback 行为**：`fallbackModel` 链上限 3 个模型（去重），529 过载触发，subagents 继承 | 同上 + claude-code issue #65782，2026-08-28 | verified；同上纪律 |
| A5 | 自定义模型串经 flag/env/settings 不做前缀校验；`ANTHROPIC_CUSTOM_MODEL_OPTION`、`ANTHROPIC_DEFAULT_*_MODEL` 可重指向别名 | 同上 | verified |
| A6 | 第三方 provider（自定义 base URL）上**自动模型 fallback 被禁用**；桌面应用路由读其自身 third-party inference 配置而**不是** `ANTHROPIC_BASE_URL`/settings.json（CLI 与桌面投影面必须分列） | code.claude.com/docs/en/env-vars + /llm-gateway-connect，2026-08-28 | verified；对 DeepSeek 场景利好（fallback 面收窄），但桌面宿主的投影/表达面未取证 |

## 4. deepseek_provider_dialect（provider 面）

| # | 事实 | 来源 | 状态 |
| --- | --- | --- | --- |
| D1 | Anthropic 兼容端点 `https://api.deepseek.com/anthropic`（`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`） | api-docs.deepseek.com/guides/anthropic_api + Claude Code 集成指南，2026-08-28 | verified |
| D2 | exact 模型名 `deepseek-v4-flash` / `deepseek-v4-pro`；未识别模型名**自动回落 flash**；`claude-opus*`→pro、`claude-haiku/sonnet*`→flash | 同上 | verified；回落行为必须建 fixture，模型串钉死精确拼写 |
| D3 | effort 透传：`output_config` "Only effort is supported"；`thinking` 支持但 `budget_tokens` 被忽略；`redacted_thinking` 不支持 | 同上 | verified |
| D4 | 原生 API `reasoning_effort` 词表 `low / high / max`（legacy `deepseek-chat`/`deepseek-reasoner` 名 2026-07-24 停用） | api-docs.deepseek.com updates + V4 公告，2026-08-28 | verified |

**未决**：Claude Code `effortLevel` 是否向自定义 base URL 透传为 `output_config.effort`（A2×D3 的端到端链路，官方无明文）——维持"集成时 fixture 验证"，不得按"应当透传"写合同；组织策略 clamp（无法静态取证，归入 observed 证据纪律）；Claude 桌面应用（非 CLI）的模型选择/投影面（A6）。

## 5. 采纳决定

- 进入 Adapter allowlist 的最小集（全部 verified）：C1/C3/C4/C6（Sol/Terra slug）、Z2、Z3 文档半边、A1/A2/A6、D1/D2/D3/D4。
- 保持候选（不进 allowlist）：C2 的 `max`（security 面单列）、`gpt-5.6-luna` 精确 slug（inferred）、Z3 UI 半边（operator_declared，附件留存后复评）、Z5/A×D 交叉项（取证后评审）。

## 6. 来源 URL 清单（全部抓取于 2026-08-28）

- Codex Configuration Reference：https://learn.chatgpt.com/docs/config-file/config-reference
- Codex Security CLI quickstart：https://learn.chatgpt.com/docs/security/cli
- Codex Security workbench：https://learn.chatgpt.com/docs/security/plugin/workbench
- GPT-5.6 官方公告：https://openai.com/index/gpt-5-6/
- gpt-5.6-terra 官方模型页：https://developers.openai.com/api/docs/models/gpt-5.6-terra
- GLM Coding Plan：https://z.ai/subscribe
- GLM-5.3-Flash 模型页：https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash
- GLM-5.3 模型页：https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3
- bigmodel Chat Completion API：https://docs.bigmodel.cn/api-reference/模型-api/对话补全
- bigmodel 核心参数说明：https://docs.bigmodel.cn/cn/guide/start/concept-param
- Claude Code model configuration：https://code.claude.com/docs/en/model-config
- Claude Code environment variables：https://code.claude.com/docs/en/env-vars
- Claude Code LLM gateway connect：https://code.claude.com/docs/en/llm-gateway-connect
- DeepSeek Anthropic API：https://api-docs.deepseek.com/guides/anthropic_api/
- DeepSeek Claude Code 集成：https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/
- DeepSeek 更新日志：https://api-docs.deepseek.com/updates/
- claude-code issue #65782（fallbackModel）：https://github.com/anthropics/claude-code/issues/65782
- 拒绝：GLM-3.5-Flash 旧名；把 provider 方言可表达性当作宿主生效证明；以社区配置补齐任何 token。
- fixtures（`tests/fixtures/<host>-static/`）待 `<runtime-root>` 选定后随 MOR-100/300/400 创建；本证据包为其唯一输入底稿。
