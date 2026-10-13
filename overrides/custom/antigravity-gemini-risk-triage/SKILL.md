---
name: antigravity-gemini-risk-triage
description: 只读分诊 Antigravity/Gemini 的服务资格、账号拒绝、429 配额限流、网络和输出质量变化；按官方入口核验，不轮换账号或绕过服务限制。
---

# Antigravity / Gemini 风险分诊

## 证据与执行边界

把服务资格/条款、认证权限、产品配额、网络连通性和输出质量分开。单条 403、429、代理可达、第三方 IP 分类和社区案例都不能单独证明账号被封、受到隐形降级或处于安全状态。Google 未公开可供用户核验的封号评分、检测阈值或通用恢复时间。

按 2026-10-13 在线复核的 [Antigravity 条款](https://antigravity.google/terms) 与 [FAQ](https://antigravity.google/docs/faq/)：使用第三方软件、工具或服务访问 Antigravity 违反条款，可能导致 Antigravity 和/或 Gemini CLI 账号被暂停或终止。FAQ 说明 **agy -p** 可用于直接脚本和 CI；消费计划不支持把它包进第三方 agent/应用，也不支持自动轮换账号。第三方 coding agent 调用 Gemini 时，官方建议使用 Gemini Enterprise 或 Google AI Studio API key。

只用产品当前支持的客户端、认证、地区和额度路径；不提取/共享订阅 OAuth token，不把订阅额度做成网关，不自动切号，不伪造设备或请求指纹。没有任何本地工具能保证账户不被服务端限制或替用户解封。

网络探测只证明相应端点在该时刻的可达性。固定出口、hosting/proxy 标签和第三方 IP 数据库都不是 Google 公布的账号风险指标。DLL 注入等客户端改造不是防封措施；条款是否覆盖某项纯网络改造不作推断，默认不推荐。

## 只读入口

在已知项目检出内可运行：

~~~powershell
.\skills.ps1 ai-risk-control --platform antigravity --plan --json
.\skills.ps1 ai-risk-control --platform antigravity --event antigravity-ban --json
.\skills.ps1 ai-risk-control --platform antigravity --event antigravity-rate-limit --retry-after 60 --json
.\skills.ps1 ai-risk-control --platform antigravity --event antigravity-degradation --json
~~~

该命令只列出仓库控制并按需生成分诊计划；它不运行宿主自检脚本、不读取 Google 账号服务端状态、不拦截请求、不强制并发，也不改代理、客户端或凭据。找不到项目时，只读取已知技能入口或用户明确给出的路径；不得扫描个人目录代替缺失输入。

## 分诊

| 观察 | 结论与动作 |
| --- | --- |
| 明确 service disabled / ToS 提示 | 停止被拒服务上的请求；保留脱敏错误、时间、请求 ID 和客户端版本；使用当前官方支持/反馈入口。不要承诺恢复时间。 |
| 普通 403 / permission denied | 核对登录态、权限、地区/资格、API key 或 project、计费、端点和服务状态；单条 403 不等于账号封禁。 |
| 429 / RESOURCE_EXHAUSTED | 确认发生在哪个产品/额度面，查看该产品官方用量页和服务端等待提示；停止重复提交，等待恢复窗口。不要切号规避或自动重放 agent 工作流。 |
| 连接失败、TLS、DNS 或代理异常 | 只按网络连通性故障排查；成功探测不等于认证、模型请求或账号状态通过。 |
| 输出质量变化 | 核对实际选择的模型、计划/额度、上下文和输入；做低负载、同条件对照。没有服务端证据时不认定“静默降智”。 |

分别核对 Antigravity 计划额度、Gemini API 的 project/model 限额和 Gemini CLI 的认证额度。AI Studio API 限额不能验收 Antigravity 订阅，也不能代表 Gemini CLI 的个人额度；具体限额会变化，以当前产品界面和官方文档为准。

遇到 429 时，用户界面使用官方提示和恢复时间；API 客户端遵守 Retry-After，只对可安全重试的瞬时错误做有上限的指数退避和随机抖动。不要叠加多层重试，不要自动重放有副作用的 agent 任务。403、认证失败、条款拒绝和无效请求应先调查原因，不盲目重试。

## 参考与停止

`references/official-sources.md` 汇总官方入口及有限的社区案例；`references/ban-mechanics.md`、`quota-and-limits.md`、`prevention-ops.md`、`degradation.md` 分别说明服务资格、额度、日常控制和质量对照。

报告只写实际检查的产品面、脱敏证据、未证明层级和恢复条件。需要用户登录、Google 支持处理或新的宿主会话时，明确保留该边界；达到当前检查目标后停止。
