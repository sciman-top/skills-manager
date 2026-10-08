---
name: workbuddy-risk-triage
description: 只读排查 WorkBuddy 国际版/CodeBuddy 的 11140、403、429、未知错误、代理例外与输出质量变化；区分账号、认证权限、内容、网络和连接器问题，不换号测试或绕过服务限制。
---

# WorkBuddy 风控分诊

## 先分诊，后归因

`11140`、`403 request illegal` 和“未知错误暂无响应”是拒绝或失败线索。单条错误不能确认账号封禁；必须结合结构化服务响应、Trace ID、客户端版本和当前官方说明，排除认证、权限、内容、服务故障及连接器错误。

`category=internal` 或简单问候也失败，仍不能独自证明请求未到模型、内容已被排除或账号级风控。不同网络的受控对照只能缩小范围，不能证明 IP 被封；不通过换账号实验归因，不轮换账号继续请求。

保留时间、错误码、Trace ID 和脱敏响应；不要输出 token、cookie、device-id、账号目录名或完整会话内容。优先读真实响应字段，区分日志中的用户引用、工具回显和服务事件。历史案例的主题关联不是因果证据。

## 统一只读入口

在已知项目检出内优先使用：

```powershell
.\skills.ps1 ai-risk-control --platform workbuddy --plan --json
.\skills.ps1 ai-risk-control --platform workbuddy --checks --json --out .\reports\ai-risk-control.json
.\skills.ps1 ai-risk-control --platform workbuddy --event workbuddy-account-risk --json
.\skills.ps1 ai-risk-control --platform workbuddy --event workbuddy-rate-limit --retry-after 60 --json
.\skills.ps1 ai-risk-control --platform workbuddy --event workbuddy-degradation --json
```

无项目时可使用已知的 `docs/handover/ai-risk-control/tools/workbuddy/workbuddy-risk-selfcheck.ps1 -NoFile`；实际部署目录需由当前任务确认，不遍历个人目录猜测路径。输出范围和敏感字段必须在转发前检查。

## 常见情况与动作

| 观察 | 动作与边界 |
| --- | --- |
| 403 / 11140 | 暂停被拒请求，排查认证、权限、内容、连接器和网络；通过官方客户端反馈附脱敏 Trace ID；不承诺自动恢复 |
| 429 / 服务频率限制 | 遵守 Retry-After/reset 或官方额度界面；没有恢复信息时停止自动重试并查询官方状态；不切号或立即切模型绕过窗口 |
| models.json 非空 | 核对当前官方客户端是否支持该自定义模型、来源与条款；非空本身不证明反代或违规 |
| 官方内置 MCP 未授权 | 按连接器认证问题处理；422/10101 不自动等于账号风控 |
| 系统代理与环境变量不一致 | 核对国际版/国内版真实端点和当前部署路由；保留已有例外，修改需备份、授权与回读 |
| 输出质量变化 | 固定模型、上下文、任务和输入作低频对照，记录额度和响应差异；无证据时不归因于静默惩罚 |

国际版常用 workbuddy.ai/codebuddy.ai，国内版常用 .cn；具体域名以当前客户端官方资料及脱敏服务事件为准，不能根据品牌或旧清单覆盖所有流量。直连是既有部署选择，不是账号安全保证。用户级 NO_PROXY 更新不会自动改变运行中客户端的环境。

## 日常防范与恢复

使用官方客户端、稳定身份和合理并发，任务分段，尊重服务限制。禁止 token 提取、订阅配额网关、设备指纹伪造、删除凭据或多账号轮换；不因报错盲目重装、清缓存、重启或改变模型配置。错误恢复走当前官方支持渠道，不承诺“根治”或免封。

依据：[WorkBuddy 国际版条款](https://www.workbuddy.ai/document/term)（2026-10-08 读取）。条款、官方模型能力和配额可能变化，执行前核实。

## 参考与停止

`references/log-forensics.md`、`selfcheck-internals.md` 提供日志分层和检测方法；`network-and-proxy.md`、`official-sources.md`、`prevention-ops.md` 提供来源和操作背景。历史参考中的“只能是账号级”“换号止血”、画像决定封禁或唯一有效操作等说法不是已证实判据，不得执行或继承。

结论分清 repo_verified、filesystem_projected、host_loaded、live_accepted。自检通过不等于服务恢复或真实长会话验收；需要真人登录、官方处理或新宿主会话时注明恢复条件并停止相关请求。
