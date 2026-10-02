# 配额与限流详解

## 一、Antigravity 配额模型

官方：`https://antigravity.google/docs/plans`

### 所有计划的共同基线

- 使用 Gemini 模型作核心 agent 模型，含 **Gemini 3.1 Pro、Gemini 3.8 Flash** 及其他 Gemini Enterprise 模型
- **无限 Tab 补全**
- 全部产品功能（计划任务、CLI 等）

### 分档

| 计划 | 配额 | 周限 | 额外 |
|---|---|---|---|
| **Google AI Ultra** | 最高、最宽松，**每 5 小时刷新** | 最高 | 可访问**第三方模型** |
| **Google AI Pro** | 高，**每 5 小时刷新直至触达周上限** | 更高 | — |
| **非 Pro / Ultra** | 「有意义」的配额，**按周刷新** | 有 | — |

### 官方关于「额度怎么算」的原话

> "The baseline rate limits are primarily determined by available capacity and exist to prevent abuse. Under the hood, the rate limits correlate with **the amount of work done by the agent**, which can differ from prompt to prompt. As a result, you receive more prompts when your tasks are straightforward and the agent can complete the work quickly, while **more complex tasks consume more quota**."

> "Usage limits for this service are subject to modification. These adjustments may be necessary to manage system capacity and maintain service stability."

→ **次数不是计量单位，工作量才是。** 「我一天才发 X 次就被限」这个抱怨在机制上不成立。

### 超额（Overages）

- Pro / Ultra 用户可用**购买的 AI credits**（或一次性促销额度）补充，按 Gemini Enterprise 标准消耗定价计。
- 设置项 **`AI Credit Overages`**（中文界面 = 「**允许 AI 额度超限使用**」，一个开关）：
  - `Never` = **开关关闭** —— 绝不自动使用，等基线刷新（**保守值，推荐**）
  - `Always` = **开关开启** —— 基线耗尽时自动用 credits，刷新后自动切回
- **界面位置**：`设置 → 模型 → 模型额度 → 允许 AI 额度超限使用`。
  同一页还能看到「每周限额剩余 / 5 小时限额剩余」的百分比与刷新倒计时 —— **这是判断当前是否触顶最快的入口**。
- **Settings** 页可查看跨模型的基线配额使用情况。

> 提醒：不要把「关掉超额使用」当成待办事项去反复提醒用户 —— 它默认就是关的，
> 属于「确认一下」而不是「需要修改」。**先看状态再给建议。**

### 官方明确「不支持」

1. **BYOK / BYOE**（自带密钥或自带端点换取额外速率）
2. 通过自定义合同获得组织级层级

→ 任何「给 Antigravity 配自带端点/中转扩容」的方案，都是在跟官方设计对着干。

## 二、Gemini API 限速

官方：`https://ai.google.dev/gemini-api/docs/rate-limits`

### 三个维度

| 维度 | 含义 |
|---|---|
| `RPM` | 每分钟请求数 |
| `TPM` | 每分钟输入 token 数 |
| `RPD` | 每天请求数 |

- **按 project 计，不是按 API Key 计** → 多建 Key 无效。
- **任一项超限即报错**（RPM 20 时，一分钟内第 21 个请求就报错，哪怕 TPM 还很空）。
- **RPD 在太平洋时间午夜重置** → 对国内用户是**下午**。
- 限速因模型而异；有些限制只对特定模型生效（如 IPM 只对图像生成模型算）。
- **preview / experimental 模型限速更严。**

### 消费型限流（spend-based）

按**滚动 10 分钟窗口**计：

| 层级 | 上限 |
|---|---|
| Free | 不适用 |
| Tier 1 | $10 |
| Tier 2 | $50 |
| Tier 3 | $200 |

超限返回 `429 RESOURCE_EXHAUSTED`。解法：等待重试 / 降低昂贵请求速率（更小上下文、更短输出）/ 申请提额。

### 使用层级

| 层级 | 升级条件 | 计费上限 |
|---|---|---|
| Free | 有活跃 project 或免费试用 | — |
| Tier 1 | 设置并绑定有效计费账号 | $250 |
| Tier 2 | 已付费 $100 + 首次成功付款满 3 天 | $2,000 |
| Tier 3 | 已付费 $1,000 + 首次成功付款满 30 天 | $20,000 – $100,000+ |

- 基于绑定计费账号在 Google Cloud 服务的**累计消费**。
- Free → Tier 1 一般即时生效；后续层级 10 分钟内生效。
- 满足条件通常自动升级，但**极少数情况会因审核中的其他因素被拒**。

### 其他

- **Priority inference**：独立限速，默认 = 同模型同层级标准限速的 **0.3 倍**（消耗仍计入整体交互流量）。
- **Batch API**：独立限速——并发 100、输入文件 2GB、文件存储 20GB，另有各模型的 Batch enqueued tokens 上限。
- **权威自检入口**：`https://aistudio.google.com/rate-limit`（可按最近 28 天查）。**不要用第三方仪表盘。**

## 三、Gemini CLI 免费层

- OAuth 路径：约 **60 RPM / 1000 RPD**（社区文档口径，官方可能随版本调整）。
- **agentic 会话里每一次工具调用都是一次请求** → 一句「帮我把这个仓库修好」可能触发几十次请求。
  - **免费层额度是按聊天场景设计的，不是按 agent 循环设计的。**
- 常见触发场景：agent 循环、模型 fallback 重试（跨模型重试会额外消耗配额）。
- 旧版 CLI（约 0.1.4 之前）存在**限速后循环切换模型并卡死**的 bug：错误提示每分钟重复出现，程序无响应。官方解释是上线初期容量超载触发速率限制与模型切换逻辑异常。→ **升级到最新版。**
- 缓解：批处理 prompt、请求间加延迟、用 Flash 处理高吞吐低复杂度任务、改用 AI Studio API Key 按量付费。

### 常见误配（会造成「订阅了却还在吃免费层限流」）

- 同时设了 `GOOGLE_CLOUD_PROJECT` / gcloud 配置 与 AI Studio API Key → CLI 走错认证路径，回落到受限的免费层，报 429。
- 区分两个产品：
  - **Gemini for Google Cloud（Code Assist / Vertex AI）**：绑 Google Cloud Project，走 gcloud / IAM / ADC。
  - **Gemini API（AI Studio 按量付费）**：绑计费账号，**只用 API Key**，不依赖 project id / gcloud。
- 修法：清掉冲突的环境变量（`GOOGLE_CLOUD_PROJECT`，并检查 shell profile），**在绑定计费后重新生成** API Key（升级前生成的 Key 可能仍被限制在免费层），设 `GOOGLE_API_KEY` / `GEMINI_API_KEY`。

## 四、429 与封号的对照表

| | 429（限流） | 403 / ToS disabled（封号） |
|---|---|---|
| 性质 | 官方承认的频率/额度机制 | 未公开细则的账号级风控 |
| 给恢复时间 | **是**（5 小时 / 周 / 太平洋午夜 / 滚动 10 分钟） | 否 |
| 官方清单 | 在（Rate limits 文档 + AI Studio 可视化） | 不在 |
| 错误体 | `429 RESOURCE_EXHAUSTED` / `Quota exceeded` | `403 This service has been disabled in this account for violation of Terms of Service` |
| 处置 | **等刷新 + 切模型 + 长任务切段 + 买 credits** | **停用违规工具 + 申诉 + 等自动解封 / 走再认证表单** |

**不要把 429 当封号处理。** 反复重试是把限流升级为封号的唯一本地动作。
