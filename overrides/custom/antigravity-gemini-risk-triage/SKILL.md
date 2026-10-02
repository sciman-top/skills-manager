---
name: antigravity-gemini-risk-triage
description: 诊断并处置 Google Antigravity（IDE/CLI/SDK）与 Gemini（CLI/Code Assist/应用/API）的封号、限流（429 RESOURCE_EXHAUSTED / Quota exceeded）、降智三类问题。触发词：Antigravity、反重力、Gemini 封号、Gemini 限流、Gemini 降智、429 RESOURCE_EXHAUSTED、service has been disabled、ToS 违规、OAuth 接入第三方、CLIProxyAPI、OpenClaw、OpenCode、Zerogravity、Antigravity Rotator、配额耗尽、模型降级。
---

# Antigravity / Gemini 风控分诊

## 核心认知：封号判的是「用法画像」，不是单次行为

官方条款《Google Antigravity Additional Terms of Service》**第 6 条**（2026-09-07 修订版）原文：

> "You must not abuse, harm, interfere with, or disrupt the Service. This includes, but is not limited to, using the Service in connection with products not provided by us. **Using third party software, tools, or services to access the Service (e.g. using OpenClaw with Antigravity OAuth) is a breach of this Agreement.** Such actions may be grounds for suspension or termination of your **Antigravity and/or Gemini CLI accounts**."

三个必须读准的点：

1. 禁止的是**「谁在访问」**（是否官方客户端），不是禁止自动化、不是禁止多开。
2. 官方把 **OpenClaw + Antigravity OAuth** 当成教科书级违规案例写进条款。
3. 处罚范围是 **Antigravity / Gemini CLI 账号**，**不连坐整个 Google 账号**（这是 2026-09 新增的边界澄清）。

官方 FAQ 给了一条合法替代路径：**要用第三方 coding agent 调用 Gemini，改用 Gemini Enterprise 或 Google AI Studio API Key。**

## 三类报错的判别（先分清再处置）

| 报错 | 性质 | 判据 | 处置 |
|---|---|---|---|
| `403 This service has been disabled in this account for violation of Terms of Service` | **封号** | Gmail 网页能上、Antigravity 不能上 | 停用违规工具 → 申诉 → 等自动解封/走再认证表单 |
| `429 RESOURCE_EXHAUSTED` / `Quota exceeded` | **限流** | 给准确恢复时间；AI Studio 可查额度 | 等刷新 + 切模型 + 长任务切段 + 买 AI credits |
| 「感觉变笨」 | **降智** | 无显式报错 | 先查模型与配额，再查上下文（见下） |

**永远不要把 429 当封号处理。** 反复重试是把「限流」升级为「封号」的唯一本地动作（二振制下尤其致命）。

## 封号

### 触发条件（按危险度）

| 等级 | 行为 | 依据 |
|---|---|---|
| 极高 | 第三方工具经 Antigravity OAuth / Gemini CLI 订阅接入 | 条款第 6 条明文 |
| 极高 | 多账号池 + 自动轮换 | 实测 40 账号全封，独立代理也无效 |
| 高 | 同 PC 多账号 account switcher 切号 | 实测 4 Pro 号封 3 |
| 高 | 相同 GCP project 跨多个账号 | 社区明确指认的封号模式 |
| 中 | 异常 token 消耗 / 高频调用 | 订阅制前提是「个人使用」 |
| 中 | 请求指纹与官方客户端不一致 | 社区逆向推断（**不要依赖它规避**） |

### 处置梯度：二振制（**最关键**）

官方 2026-03 公告（gemini-cli GitHub Discussions `#20632`）：

1. **全面解封**——受影响账号 1–2 天内自动恢复
2. **再认证流程**——违规时收到邮件 + 重新认证表单，填完恢复
3. **二振制**——**初犯填表单可恢复，二犯直接永久封号**
4. 条款未变，第三方工具/proxy 依然违规

→ **「被封了就换号继续用同一套工具」是最差策略**：浪费掉唯一一次再认证机会，还让新号预置同一套画像。

### 申诉

- 邮箱：`gemini-code-assist-user-feedback@google.com`（社区反馈回复率低）
- 2026-03 那轮的恢复主要靠**官方统一解封**，不是逐个申诉

### 地区与年龄（中国大陆用户必看）

- **中国大陆不在官方支持地区列表内** → 属**服务不可用**，不是「违规」。只能靠代理访问，而**代理出口 IP 与账号归属地不一致**是画像里的一个信号（但绝不是封号主因）。
- 官方提示：以 Google 服务条款页显示的国家为准，可通过官方表单修改关联地区。
- 硬门槛：**仅限 18 岁以上**（需年龄验证）；Workspace 账号可能验证失败，建议用 `@gmail.com`。

### 三类「代理」必须分开看（**最常被混淆**）

| 类型 | 目的 | 判定 |
|---|---|---|
| **① 网络出口代理**（VPN / 系统代理 / 分流） | 让客户端**能连上** | **低—中**。条款没单独禁代理，但风险有二：出口 IP 与账号归属地不一致；共享出口 IP 上的其他用户带来关联风险 |
| **② 反代 / OAuth 复用**（CLIProxyAPI / Zerogravity / OpenClaw） | 把订阅额度**挪到别的客户端** | **红线**。条款第 6 条明文 |
| **③ 客户端注入 / 篡改**（DLL 劫持 / asar 注入 / 改客户端 config） | 改变客户端自身行为 | **中**。属「修改客户端」，实践上普遍且极少单独追责，**但目的若是绕过配额或身份校验就落红线** |

**判据一句话**：这个东西改变的是「**我怎么连上**」，还是「**我以谁的身份、用多少额度**」？
- 只改「怎么连上」→ 出口代理，风险来自**出口 IP 质量与共享度**，不是「用了代理」本身。
- 改「身份 / 额度」→ **红线**。

**出口 IP 实操**：优先独享或低共享度出口；同一账号固定出口、不要短时间横跳多国节点；验证要看**对端看到的出口**（如 `dns.google` 的 EDNS Client Subnet），不是只看本地配置。

细节见 `references/ban-mechanics.md`。

## 限流

### Antigravity 配额（官方 plans 页）

| 计划 | 配额 |
|---|---|
| Ultra | 最高，**每 5 小时刷新**，最高周限，可访问第三方模型 |
| Pro | 高，**每 5 小时刷新直至周限** |
| 非 Pro/Ultra | 「有意义」的配额，**按周刷新** |

- **额度与 agent 实际工作量相关，不是「次数」**——复杂任务消耗更多配额。
- 官方保留修改权：「Usage limits are subject to modification」。
- 超额：Pro/Ultra 可用购买的 **AI credits**（按 Gemini Enterprise 标准定价）。设置项 `AI Credit Overages`：`Never` / `Always`。
- **官方明确不支持 BYOK / BYOE**——任何「配个自带端点就能扩容」的方案都是在跟设计对着干。

### Gemini API 三维度

- `RPM` / `TPM` / `RPD`，**按 project 计（不是按 API Key）** → 多建 Key 无效。
- 任一项超限即报错。
- **RPD 在太平洋时间午夜重置** → 对国内用户是**下午**，别误判成「没恢复」。
- preview / experimental 模型限速更严。
- 消费型限流（滚动 10 分钟）：Tier 1 = $10 / Tier 2 = $50 / Tier 3 = $200。
- Priority inference = 标准限速的 **0.3 倍**。
- 层级：Free / Tier 1（$250 上限）/ Tier 2（$100+3 天） / Tier 3（$1000+30 天）。

### Gemini CLI 免费层

- 约 **60 RPM / 1000 RPD**（OAuth 路径，口径可能随版本变）。
- **agentic 会话里每次工具调用都是一次请求** → 一句「帮我修好这个仓库」可能触发几十次请求。免费层是按聊天场景设计的，不是按 agent 循环。
- 旧版（约 0.1.4 之前）限速后会**循环切模型卡死** → 升级到最新版。
- 权威自检入口：**AI Studio 的 Rate Limit 页**（可按最近 28 天查）。**不要用第三方仪表盘。**

细节见 `references/quota-and-limits.md`。

## 降智：四类归因（Google 比 WorkBuddy 多一类）

### 类型 1 · 配额驱动型（Google 独有，最常见）

- **2026-05-17 起**，Gemini 应用把「固定消息数」改为**基于计算资源的配额制**。
- **达到大型模型上限后，系统引导使用更轻量模型。** 高峰时段选 Pro 时，实际可能跑 Flash / Flash Extended。
- Antigravity 同理走**降级链**（第三方工具把 `ANTIGRAVITY_MODEL_FALLBACK_CHAIN` 当卖点就是利用这点）。
- **这意味着「降智」很多时候不是 bug，是官方设计。**
- 合规解法：确认当前模型 → 重任务避高峰 → 轻任务主动用 Flash → 配额耗尽就**等刷新 / 买 credits**（官方认可的唯一扩容路径）。

### 类型 2 · 上下文型

长对话堆积冲突条件；实测**第 20 轮左右开始遗忘早期变量、重复改同一段代码**。→ 开新会话 + 压缩摘要。

### 类型 3 · 提示词型

「帮我分析一下」没有对象/材料/读者/标准 → 补足输入范围、输出结构、证据要求、读者、篇幅。

### 类型 4 · 调度型 / 风控型

- 调度型：高峰算力紧张。→ 避高峰、固定模型版本。
- 风控型：**无官方承认、缺硬证据**。可确证的惩罚是显式 403/429，不是静默降智。

**顺序：先怀疑上下文，再怀疑配额/调度，最后才考虑风控。**

### 十分钟排查法

记录模型 → 新建对话做对照 → 固定测试题 → 查额度提示 → 补足约束 → 要求标注依据 → 重新生成比较。

**判据：只有「新对话 + 同一模型 + 同一材料 + 同一提示词」仍连续出现相同错误，才值得怀疑产品侧。**

细节见 `references/degradation.md`。

## 评估第三方「账号管理器 / 网关」（如 Antigravity Tools / Rotator / Manager、Cockpit Tools 类）

遇到一个常驻的第三方 AI 账号管理工具，**不要一上来就判定它违规**，用五个问题定位它的实际暴露面：

| # | 问题 | 看哪里 |
|---|---|---|
| 1 | 它的**账号槽位**里有没有你要保护的平台？ | `*_accounts/` 目录、`*_accounts.json` 是否非空 |
| 2 | 它有没有**本地网关**把该平台额度对外暴露？ | `gatewayMode` / `local_access` / `inheritAccountPool` / 监听端口 |
| 3 | 它有没有**伪造官方客户端身份**？ | `*-official-client-identity.txt`、日志里的 `user-agent=` |
| 4 | 它有没有**多账号轮换 / 回收站**？ | `*_recycle_bin`、`*_tombstones`、`account switcher`、`rotator` |
| 5 | 它对目标平台的**轮询频率**是多少？ | 数日志里的端点调用次数 |

**分级结论**：

- **槽位为空** → 当前无直接风险（但机制在位，是潜在暴露面）。
- **有账号 + 有本地网关暴露额度** → 属 **② 反代 / OAuth 复用**，红线。
- **只有身份伪装 / 高频轮询，没有把额度转出去** → 属 **③ 客户端身份伪装**，中风险。

**只切断「某一平台」的实操技巧**：

- 这类工具通常有 `<平台>_auto_refresh_minutes` 一类的**平台级**配置键。
- 若**目标平台没有独立键、回落到全局键**，那么改全局只会影响「没有独立键的平台」——正好是最小改动面。
  （实测：17 个平台各有独立键，antigravity / gemini 没有 → 改全局只影响这两个，其余不受影响。）
- 用 `-1` 作关闭语义（先找已存在的 `-1` 值确认语义，别自创）。
- ⚠️ 这类应用**通常不热加载配置**，改完要**重启**才生效；验证方法是重启后在日志里数端点调用次数是否为 0。
- ⚠️ 改配置**只动配置**。账号数据的增删是另一回事，不要顺手去动它。

## 红线

**绝对不要做：**
- 第三方工具 + Antigravity OAuth 接入
- 多账号池 / 自动轮换 / account switcher 切号
- 相同 GCP project 跨多账号
- 伪造请求指纹 / 模拟官方客户端（协议禁止；且 CLIProxyAPI 作者自己承认模拟到位后工具就没意义了）
- 购买、租借、共享账号
- **被封后换号重试同一套用法**（二振直接永久封）

**应该做：**
- 第三方工具里要用 Gemini → **AI Studio API Key / Gemini Enterprise**
- 配额耗尽 → **等刷新 / 买 credits / 换低阶模型**
- 被封 → **停用违规工具 → 申诉 / 再认证表单 → 恢复后改用官方通道**
- 主号与实验号分离；跑过反代的 Google 账号不要挂重要资产

## 信息污染：封号加速器黑名单

搜「Antigravity 封号/限流」「Gemini 降智」会命中大量软文（掘金/知乎/CSDN/独立站，内容雷同）。共同卖点词：**多账号池、自动轮换、配额自动降级链、无限使用、绕过限制、稳流、把 OAuth 接到 Claude Code/OpenCode**。

**看到就划走**：`CLIProxyAPI`、`Zerogravity`、`OpenClaw`、`OpenCode`、`Claude Code（配合 Antigravity OAuth）`、`Antigravity Tools`、`Antigravity Rotator`、`Antigravity-Manager`、`gcl2api-plus`。

### 与 WorkBuddy 侧的镜像

| WorkBuddy | Antigravity / Gemini |
|---|---|
| FlowRebound「稳流器」→ 把自定义模型地址换成工具本地地址 | Antigravity Rotator / gcl2api-plus → 多账号池 + 配额降级链 + 反代 |
| 话术：「不会破解、绕过官方限流策略」（与步骤自相矛盾） | 话术：「多账号自动运维」「优先级调度」「会话热更新」 |

**两者都是封号加速器，都不是限流解决方案。**

## 跨平台交叉风险（**最重要的判据**）

**同一套「反代 + 多账号 + OAuth 复用」的行为模式会同时触发两个平台的风控。**

实证：WorkBuddy 的触发画像是「CLIProxyAPI / CPA 网关 / Direct OAuth / 反代」；而 **CLIProxyAPI 正是 2026-02 与 2026-08 两轮 Antigravity 封号潮中被点名最多的工具**（其 GitHub Issue `#1637`：有人一次被封 3 个 Google 账号，另一人 40 个账号全灭）。

→ **在 WorkBuddy 换号躲过的用法，会在 Google 侧以更硬的方式再收一次账**（真金白银的订阅 + 二振永久封）。

配套动作：**把反代 / 网关 / 密钥 / 绕过类工作彻底移出所有 AI 客户端会话**，放到本地终端里做。

## 与 WorkBuddy 技能的配合

本技能与 `workbuddy-risk-triage` 是姊妹技能，共享四条不变量：

1. 封号是「行为画像」判定，换号只换身份不换画像。
2. 限流与封号是两套机制，处置路径相反。
3. 降智第一嫌疑人是自己的上下文与配额。
4. 所有「帮你绕过限制」的第三方工具都是封号加速器。

## 参考材料（按需读取）

| 文件 | 内容 |
|---|---|
| `references/ban-mechanics.md` | 条款原文、检测机制推断、封号实证、处置梯度、申诉、地区与年龄门槛 |
| `references/quota-and-limits.md` | Antigravity 配额模型、Gemini API 三维度、层级、CLI 免费层、429 与封号对照 |
| `references/degradation.md` | 四类降智归因、配额驱动型机制、排查法、网上流传的「恢复满血」方案判定 |
| `references/acceptance-and-projection.md` | **改完之后怎么证明可靠**：真值层级、三层验收（离线夹具 / 真故障注入 / 全量自检）、投影与 sha256 无漂移、可注入改造要点、用例设计的坑 |
| `references/official-sources.md` | 官方页面链接、条款编号、社区实证出处、时效声明 |
