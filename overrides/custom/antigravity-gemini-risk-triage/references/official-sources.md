# 官方来源与社区实证

## 官方页面（权威，优先引用）

| 主题 | 链接 |
|---|---|
| Additional Terms of Service（**红线第 6 条**） | `https://antigravity.google/terms` |
| FAQ（第三方工具禁令、地区清单、年龄、数据收集） | `https://antigravity.google/docs/faq/` |
| Plans and AI credits（配额模型、Overages、不支持 BYOK） | `https://antigravity.google/docs/plans/` |
| Models（各计划模型可用性） | `https://antigravity.google/docs/models` |
| Enterprise（企业通道） | `https://antigravity.google/docs/enterprise` |
| Support（社区入口） | `https://antigravity.google/support` |
| Gemini API Rate limits（RPM/TPM/RPD、层级、消费型限流） | `https://ai.google.dev/gemini-api/docs/rate-limits` |
| AI Studio 实时额度自检 | `https://aistudio.google.com/rate-limit` |
| Google 服务条款（Universal Terms） | `https://policies.google.com/terms` |
| 关联地区修改申请 | `https://policies.google.com/country-association-form` |
| 年龄验证 | `https://myaccount.google.com/age-verification` |
| 删除 Interactions 请求 | `antigravity-support@google.com` |

## 官方公告与条款修订

| 事件 | 出处 |
|---|---|
| 2026-03 解封公告：全面解封 + 再认证流程 + 二振制 | gemini-cli GitHub Discussions `#20632` |
| 2026-09-07 条款修订：处罚边界 = Antigravity / Gemini CLI 账号，不连坐 Google 账号 | `antigravity.google/terms`（对照修订前版本） |

## 社区实证（可信度中等，需交叉验证）

| 主题 | 出处 |
|---|---|
| 封号实证：3 账号同封 / 40 账号全封 / 4 Pro 号封 3 / 相同 project 是封号模式 / `403 service disabled` 原文 | CLIProxyAPI GitHub Issue `#1637` |
| 2026-08-30 新一轮封号 | Linux.do topic `2830699` |
| 封号特征与挽救方案 | Linux.do topic `1618883` |
| 解封流程与申诉邮箱 | Linux.do topic `1613359`；知乎「Antigravity账号被封的恢复方法」 |
| 解封后续（二振制、条款未变） | 开发者博客（laplusda.com，2026-03-01） |
| 封号事件深度分析（检测机制推断、影响面） | 路由之外（im.awsl.app，2026-02-20） |
| 薅羊毛翻车始末（OAuth 漏洞原理） | blog.swifttools.eu（2026-02-24） |
| Gemini 降智五类原因、排查表 | 知乎「Gemini为什么降智了？」（2026-07-28） |
| Gemini 2026-05 配额制改革、Pro 默认降级 | 什么值得买（2026-07-10） |
| 地区限制解决（**仅作现象参考，其解法多为代理，注意合规**） | 阿里云开发者社区、博客园、独立博客（2026） |

## 社区点名的高危工具（**封号加速器**）

`CLIProxyAPI`、`Zerogravity`、`OpenClaw`、`OpenCode`、`Claude Code（配合 Antigravity OAuth）`、`Antigravity Tools`、`Antigravity Rotator`、`Antigravity-Manager`、`gcl2api-plus`

**识别特征**：宣称多账号池、自动轮换、配额自动降级链、无限使用、绕过限制、稳流、把 OAuth 接到 Claude Code/OpenCode。

## 时效与可信度声明

1. 本技能事实以 **2026-10-01** 时点为准。**Google 的模型版本、配额与条款变化很快**，使用前请回官网复核。
2. 「检测机制」一节为**社区逆向推断**，非官方公开说明，**不要当成可依赖的规避依据**。
3. 「降智」中除「配额驱动型」有官方文档依据外，其余多为用户主观描述。**不要把单次输出波动当成平台结论。**
4. 本技能**刻意不提供任何绕过手段**。所有可执行建议都落在官方明示的合法路径内——这不是保守，而是唯一真正能降低封号概率的做法。
5. 所有社区来源都可能含推广软文，**遇到「多账号轮换」「反代接入」类方案一律视为封号加速器**。
