# 配额与限流

2026-10-13 核对 Antigravity Plans 与 Gemini API Rate limits。以下是文档口径，实际账号额度、资格和 reset 以对应官方客户端/控制台为准，不承诺固定恢复时间。

## Antigravity 订阅

来源：https://antigravity.google/docs/plans

| 计划 | 基线刷新 | 周限额 |
|---|---|---|
| 非 Pro/Ultra | 每周 | 有 |
| Pro | 每五小时，直至达到周限额 | 有 |
| Ultra | 每五小时 | 有，额度更高 |

额度与 agent 实际工作量相关，复杂任务通常消耗更多。请求次数少不能排除高消耗，也不能排除额度显示/同步异常。五小时刷新不保证周额度恢复；不要把额度耗尽等同封禁或自动换模型。

Pro/Ultra 可用官方 AI credits 承担超额使用。AI Credit Overages 的 Never 表示不自动使用，Always 表示基线耗尽时使用 credits、刷新后切回。先查看实际设置再建议；不假定默认值或固定中文 UI 路径。Settings 可查看基线使用情况。

个人 Plans 当前不支持通过 BYOK/BYOE 增加速率限制；正式企业 API 入口另按企业文档核验。两者不能混为同一产品设置。

## Gemini API

来源：https://ai.google.dev/gemini-api/docs/rate-limits

- 配额按 project 应用，不按 API Key；同项目新建或轮换 Key 不能提高限额。
- RPM（每分钟请求）、输入 TPM、RPD（日请求）等任一维度超限都可能返回 429；部分模型还有 IPM、TPD 等维度。
- RPD 文档重置口径是太平洋时间午夜，北京时间通常为夏令时 15:00、标准时 16:00；实际以服务端提示为准，不套用到 Antigravity。
- 预览/实验模型可能有更严格限制。官方公布限额不保证始终获得相同容量。
- 部分账号还适用按滚动十分钟窗口评估的支出速率限制，是否适用取决于结算历史、层级及账号状态。
- 在 https://aistudio.google.com/rate-limit 查看当前有效限额；升级、支出和提额条件以当前官方页为准，不把历史数字固化为恢复方案。

正式 API 的实际调用方应同时控制请求频率、输入 token、并发与费用；串行并不保证 TPM 合规。非即时任务可评估官方 Batch API，但需核对其独立配额和计费。

## 重试与停止

来源：https://ai.google.dev/gemini-api/docs/troubleshooting

官方 API 对暂时性错误建议有上限的指数退避与抖动；400/402/403 等客户端错误不应重复重试。SDK、网关和调用方可能各自重试，须核对实际配置，避免叠加放大。

本仓宿主合同要求 provider 的 429/quota/auth/risk/billing 错误停止当前任务，等待 operator 或 fresh parent selection；官方 API 建议不自动授予宿主重试权限。不热切模型、不换号、不重复 prompt。仅在另有明确调用方合同允许时实现 API 暂时性错误重试，并遵守服务端等待提示、次数与总耗时上限。

收到 429 先区分分钟窗口、日额度、订阅周限额、支出速率或结算问题。按 Retry-After/reset 复查；缺少提示则恢复时间未知，到期也不保证请求被接受。日额度、结算限制不靠秒级重试解决。

## Gemini CLI 认证额度

Gemini CLI OAuth、AI Studio API、Vertex AI/企业认证分别核验，不套用订阅额度或固定免费层数字。发现环境变量或认证冲突时先读取当前 CLI 官方认证说明及本机 help，再确认实际选中路径；不一律删除 GOOGLE_CLOUD_PROJECT，不因升层而无依据重新生成密钥。

## 错误对照

| 观察 | 结论与动作 |
|---|---|
| 429 RESOURCE_EXHAUSTED | 限流/配额/适用支出限制；查对应面板和等待提示，停止当前任务重试 |
| 401/403，无明确封禁说明 | 认证/权限/资格/端点等原因待查，不认定封禁 |
| 明确 ToS service disabled | 服务受到限制；暂停相关调用并使用官方反馈/申诉，不承诺自动恢复 |
| 503/超时 | 可能是暂时性容量或链路问题；按当前调用方授权处理，不自动归类账号风险 |

重试风暴增加负载、消耗和重复副作用风险；没有证据支持“反复重试必然升级成封号”。
