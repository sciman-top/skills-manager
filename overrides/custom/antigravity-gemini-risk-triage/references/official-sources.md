# 官方来源与社区反馈

本页于 **2026-10-13** 在线复核。Google 会调整产品、条款、模型和额度；每次分诊都应重看对应产品页面。官方政策优先于社区帖和旧的本地缓存。

## 官方资料

| 主题 | 来源 | 可支持的结论 |
|---|---|---|
| Antigravity Additional Terms | https://antigravity.google/terms | 第 6 节禁止使用第三方软件、工具或服务访问服务；可能暂停或终止 Antigravity 和/或 Gemini CLI 账号。 |
| Antigravity FAQ | https://antigravity.google/docs/faq/ | 当前登录资格、支持地区、第三方 agent 边界、agy -p 直接脚本/CI 和自动轮换账号的边界；外部 agent 使用 Gemini 的官方替代路径。 |
| Antigravity Plans and AI credits | https://antigravity.google/docs/plans/ | 各计划额度刷新方式、agent 工作量与额度的关系、credits 超额设置及限制可能变化。 |
| Antigravity Models | https://antigravity.google/docs/models | 当前各计划模型可用性；不证明服务端是否对某次请求静默换模。 |
| Gemini API rate limits | https://ai.google.dev/gemini-api/docs/rate-limits | Gemini API project/model 限额、使用层级和 429；这些不是 Antigravity 订阅或 Gemini CLI 的额度。 |
| AI Studio rate limits | https://aistudio.google.com/rate-limit | 当前 Gemini API project 的用量视图。 |
| Gemini CLI / Code Assist quotas | https://developers.google.com/gemini-code-assist/resources/quotas | Gemini CLI 与 Code Assist 的相应个人/产品额度；不要套用 AI Studio API 数值。 |
| API retry guidance | https://cloud.google.com/storage/docs/retry-strategy | Google Cloud 通用客户端建议：分类可重试错误、指数退避加抖动、限制重试并避免叠加；不是 Antigravity 私有重试合同。 |
| Antigravity support | https://antigravity.google/support | 当前产品反馈/支持入口；不要依赖未由当前官方页面确认的历史邮箱或申诉时限。 |

## 社区反馈（仅作症状样本）

| 反馈 | 用法边界 |
|---|---|
| Gemini CLI issue [#24937](https://github.com/google-gemini/gemini-cli/issues/24937)，2026 年 4 月创建的 429/capacity 汇总 | 用户报告说明容量错误会出现；不代表 Antigravity 账号封禁，也不证明当前仍有同一故障。 |
| Gemini CLI issue [#29504](https://github.com/google-gemini/gemini-cli/issues/29504)，2026 年 9–10 月报告 spend-cap 429 被界面反复显示为 high demand | 说明具体错误文本和客户端分类值得保留；是 issue 报告，不是账号处罚规则。 |
| 社区 issue [#1637](https://github.com/router-for-me/CLIProxyAPI/issues/1637)，用户报告第三方代理使用期间服务不可用 | 时间相关不等于因果证明。只能说明社区有人报告此类症状，不能据此推断检测机制、其他账号是否关联或恢复流程。 |

社区报告有选择偏差、客户端/计划/地区差异，状态也会变化。不得从这些样本推导账号关联算法、共享 IP 风险、设备指纹、固定出口有效性、重试次数阈值、所谓“二振制”或自动解封承诺。