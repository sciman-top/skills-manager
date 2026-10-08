---
name: antigravity-gemini-risk-triage
description: 只读分诊 Antigravity/Gemini 的账号拒绝、429 配额限流、代理链路和输出质量变化；按官方入口核验，保留证据与停止条件，不轮换账号或绕过服务限制。
---

# Antigravity / Gemini 风控分诊

## 证据与执行边界

先区分账号/服务资格、认证权限、配额、网络和上下文问题。错误码、代理可达、出口分类或社区案例均不能单独证明封号原因、模型降级或账号安全。

[Antigravity 官方条款](https://antigravity.google/terms)（2026-10-08 读取）禁止第三方软件通过 Antigravity OAuth 访问服务，并说明可能暂停或终止 Antigravity/Gemini CLI 账号。该措辞不是对其他账号状态的保证，也不能推出统一的二振制、自动解封期限或重试一定造成封禁。

只使用用户已授权的官方客户端和认证路径；不提取 OAuth/token、不转售订阅配额、不轮换账号、不伪造设备或请求指纹。保持低并发，避免失败后的连续重试。

`antigravity-proxy` 的 DLL 注入属于社区网络改造。网络出口生效不证明 Google 批准这种改造；条款适用范围未获官方确认时明确保留合规不确定性。优先官方支持的网络配置；不得把它推荐为防封工具。

## 统一只读入口

已知项目检出内优先调用：

```powershell
.\skills.ps1 ai-risk-control --platform antigravity --plan --json
.\skills.ps1 ai-risk-control --platform antigravity --checks --json --out .\reports\ai-risk-control.json
.\skills.ps1 ai-risk-control --platform antigravity --event antigravity-ban --json
.\skills.ps1 ai-risk-control --platform antigravity --event antigravity-rate-limit --retry-after 60 --json
.\skills.ps1 ai-risk-control --platform antigravity --event antigravity-degradation --json
```

命令只输出检查/分诊，不拦截宿主请求或强制并发。找不到项目时只读取已知技能参考入口或用户给出的工具位置；不得遍历个人目录代替缺失输入。

## 分诊与恢复

| 观察 | 允许的结论与动作 |
| --- | --- |
| 明确 service disabled / ToS 提示 | 停止被拒服务的请求，保存脱敏响应、时间与版本，使用当前官方反馈/申诉渠道；不承诺恢复时间 |
| 单条 403 或 permission denied | 检查认证、权限、地区/资格、端点与服务状态；不直接认定账号封禁 |
| 429 / RESOURCE_EXHAUSTED | 读取 Retry-After/reset 和该服务官方配额界面，暂停到恢复窗口，缩小后续任务；不切号规避、不立即换模型重放 |
| 连接失败、TLS/DNS/代理异常 | 核对系统代理、用户环境、DLL 上游和监听者；端点失败不等于风控 |
| 输出质量下降 | 固定任务、材料、模型标识与上下文作低频对照；没有服务证据时不认定静默降智 |

Gemini API 的 project/model 配额、Gemini CLI 的认证额度和 Antigravity 订阅额度分别核验；AI Studio API 配额页不能验收 Antigravity 订阅。当前额度与资格以官方客户端/控制台为准，不采用历史数值作为当前上限。

不开 TUN 的既有部署中，分别核对 Sign In 的系统代理、language server 的代理环境和 DLL 上游；不得从 curl 端点可达外推为实际进程、登录或模型调用已通过。机房/代理 IP 分类不是安全或封禁证明。修改前备份并绑定哈希，宿主重启、认证和账号数据操作必须另有明确授权。

## 参考与停止

`references/official-sources.md` 提供来源定位；`network-and-proxy.md`、`quota-and-limits.md`、`degradation.md`、`prevention-ops.md` 提供按需检查方法。参考中的社区案例、历史恢复机制、固定额度和因果推测必须重新核验，不能覆盖本入口的分诊边界或用于规避限制。

报告实际检查、脱敏证据、未证明层级和恢复条件。达到当前检查目标后停止；需要真人登录、服务方处理或新宿主会话时保留明确阻塞，不伪造 live acceptance。
