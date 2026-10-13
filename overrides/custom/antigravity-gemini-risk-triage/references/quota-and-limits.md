# Antigravity 与 Gemini 的额度、429 和退避

先确认调用发生在哪个产品。Antigravity 订阅、Gemini API、Gemini CLI/Code Assist 的额度合同不同，不能把一个产品的配额数字搬到另一个产品。

## Antigravity 计划额度

[官方 Plans 页面](https://antigravity.google/docs/plans/)（2026-10-13 复核）当前概述：

- Google AI Ultra：额度最高，每 5 小时刷新，并有更高的周限额。
- Google AI Pro：较高额度，每 5 小时刷新，直到触及周限额。
- 其他计划：基础额度按周刷新。
- 官方说明额度与 agent 实际完成的工作量相关，复杂任务可能消耗更多；容量与服务稳定性也可能导致规则调整。
- Pro/Ultra 可用购买的 AI credits 做超额用量，AI Credit Overages 可设置为 Never 或 Always；不希望自动产生超额消费时可选择 Never。

以上仅是页面的概括，不是固定请求数、账号安全等级或保证值。以当前 plan、模型选择器、Settings/Usage 和官方页面为准。AI Studio 的 API 限额不能查看 Antigravity 订阅余量。Antigravity 当前也不支持通过 BYOK 或自定义 endpoint 提高额度。

## Gemini API（Google AI Studio）

[Gemini API rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) 说明：

- RPM、TPM、RPD 等限额随 project、模型、使用层级和账号状态变化；同一 project 内的多个 API key 不会增加 project 配额。
- RPD 按太平洋时间午夜重置；模型和实验/预览状态可能有不同限制。
- 当前 project/model 限额以 [AI Studio 用量页](https://aistudio.google.com/rate-limit) 和 API 返回为准。
- 429 RESOURCE_EXHAUSTED 可能来自某个速率窗口、project spend cap 或其他限额；先查看错误细节、用量页和计费状态。不要把它直接当作封号，也不要用切账号或新建 project 掩盖消耗。

## Gemini CLI / Code Assist

Gemini CLI 的认证额度与 Gemini API key 配额分开；官方 [Gemini Code Assist quota 页面](https://developers.google.com/gemini-code-assist/resources/quotas) 说明 CLI/agent mode 的请求计量和限制。以所用认证方式、计划、当前版本和官方页面为准，不套用 AI Studio 的 RPM/TPM/RPD 数字。

## 429 的处理

- **Antigravity 或交互式 CLI**：停止重复提交，查看应用显示的当前模型、额度及刷新信息，等待服务指示的窗口。额度恢复前不要切账号继续相同自动化任务或脚本循环请求。
- **Gemini API 客户端**：遵守响应中的 Retry-After/reset 提示；仅在错误可重试、操作可安全重放时，使用有次数/总时长上限的指数退避和随机抖动。避免在 SDK 和应用两层各自无限重试。认证失败、权限错误、无效请求或明确条款拒绝应先修正原因，不重试。
- **降低合法用量**：缩短不必要的上下文和输出、拆分大任务、减少不必要并发；若所用产品支持低成本模型，可根据任务选择。不要压力测试额度。

Google 的通用客户端指南建议对瞬时错误采用有界指数退避和抖动；Gemini API 文档对 spend-based 429 建议等待、降低昂贵请求速率，必要时申请限额提升。产品 UI 应按其自身提示操作，不自行编写重放循环。

| 错误 | 分诊 |
|---|---|
| 429 / RESOURCE_EXHAUSTED | 查对应产品/model/project 的实际 quota、billing、reset 或容量信息；不是封号结论。 |
| 403 / PERMISSION_DENIED | 查认证、权限、资格、地区、project、计费和服务状态；没有明确 service-disabled/ToS 文本时不归为封号。 |
| 5xx / 临时连接失败 | 确认服务状态与网络；程序端只按有界、幂等的重试策略处理。