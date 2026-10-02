# 封号机制详解

## 一、官方条款原文

**《Google Antigravity Additional Terms of Service》**（`https://antigravity.google/terms`）

- 生效结构：Universal Terms（Google 服务条款）+ Antigravity Additional Terms + Privacy Policy 三者共同构成 Agreement。
- **若通过 Gemini Enterprise（Google Cloud）/ Gemini Enterprise for Business / Google Workspace 订阅（Google Cloud Pre-GA Offering Terms）或 Gemini Enterprise API Key 访问，则不适用本 Additional Terms**，而适用你管理员签署的条款。→ 企业通道是另一套规则，这也是官方推荐「想用第三方 agent 就走 Gemini Enterprise」的原因。

### 第 6 条（**红线条款**）

> "You must not abuse, harm, interfere with, or disrupt the Service. This includes, but is not limited to, using the Service in connection with products not provided by us. Using third party software, tools, or services to access the Service (e.g. using OpenClaw with Antigravity OAuth) is a breach of this Agreement. Such actions may be grounds for suspension or termination of your Antigravity and/or Gemini CLI accounts."

### 其他相关条款

- **第 3 条**：Google 会记录并存储用户数据、交互数据、相关元数据与反馈（"Interactions"），可在多用户间聚合，仅在服务运行时收集。可申请删除，邮箱 `antigravity-support@google.com`。
- **第 5 条**：Interactions 用于评估、开发、改进 Google 与 Alphabet 的研究/产品/服务/机器学习技术；**Google 员工与承包商可能访问、查看、审查、使用 Interactions**。可在设置里更改偏好。
- **第 4 条**：AI Agent 的行为、任务、数据/应用/系统授权、生产环境监督，**由你自行负责**。
- **第 8 条**：若选第三方或开源模型作主 agent 模型，受该模型条款约束；Anthropic 特指其 Commercial Terms。

### 2026-09-07 修订的背景

- 此前条款只写 "your account"，被开发者社区解读为「可能连带封掉整个 Google 账号」。
- 争议由 Theo Browne（T3 Code 创始人）与 Gergely Orosz（The Pragmatic Engineer）带起。
- Antigravity 负责人 **Varun Mohan**（DeepMind 工程师、前 Windsurf CEO）回应：说法不对，是条款写得不够清楚，承诺修改。
- 修订后明确：处罚边界是 **Antigravity 和/或 Gemini CLI 账号**，不是整个 Google 账号。
- **但核心限制一点没松**：FAQ 仍明确禁止 Claude Code、OpenClaw、OpenCode 等第三方工具使用 Antigravity 登录。

## 二、官方 FAQ 的相关问答

`https://antigravity.google/docs/faq/`

**Q：为什么我不能用第三方软件（如 Claude Code、OpenClaw、OpenCode）配合 Antigravity 登录？**

> A：使用第三方软件、工具或服务访问 Antigravity 违反我们的服务条款，并**严重损害合法用户的产品体验**。此类行为可能导致账号被暂停或终止。要用第三方 coding agent 调用 Gemini，我们建议使用 **Gemini Enterprise 或 Google AI Studio 的 API Key**。

**地区可用性**：Antigravity 仅在「approved geographies」可用。不在列表中则无法使用。**中国大陆不在列表内。** 官方提示以 Google 服务条款页显示的国家为准，可用 `https://policies.google.com/country-association-form` 申请修改关联地区。

**年龄**：仅限 18 岁以上；需在 `myaccount.google.com/age-verification` 完成年龄验证。

**账号类型**：建议用 `@gmail.com`，Google Workspace 账号可能验证失败。

**数据收集**：可在 Settings 面板随时退出。

## 三、封号检测机制（社区逆向推断，**非官方公开**）

来自社区分析（Linux.do、Reddit、开发者博客）的推断，仅供参考：

1. **请求指纹分析** —— 请求头、TLS 指纹、HTTP/2 行为特征是否与官方 Antigravity 客户端一致。
2. **使用模式分析** —— 短时间大量调用、非典型调用序列、异常高的 token 消耗。
3. **OAuth Token 追踪** —— 识别来自非官方客户端的 token 使用行为。
4. **账号关联分析** —— 多账号是否共享相同网络环境或设备指纹。

**重要反证**：CLIProxyAPI 项目协作者 luispater 明确表示：

> "Any fingerprint-level simulation is, in my view, redundant. Achieving a 1:1 simulation isn't difficult—I even have the telemetry data—but I don't think it's necessary. The root of the problem is that you need to be able to integrate it into other tools."

→ **做 1:1 指纹模拟没意义**：模拟到位后就没法在其他工具里用了，等于删掉 Antigravity 支持。所以「完美伪装」这条路本身是死路。

## 四、封号实证（CLIProxyAPI GitHub Issue #1637）

标题：*Google blocked my 3 email id at once*

- 用户一次被封 **3 个** Google 账号，Gemini 与 Antigravity 双双不可用，「Pro 计划用几天就没了」。
- 错误原文：`Failed to refresh quota for "xxx@gmail.com-project-<uuid>.json": 403 This service has been disabled in this account for violation of Terms of Service. If you believe this is an error, contact gemini-code-assist-user-feedback@google.com.`
- 另一用户报 **40 个账号全被封**，「i used proxy, separate proxy for each account」——**独立代理不能规避**。
- 有用户 4 个 Pro 账号，**同一台 PC 上**用 account switcher 跑 Antigravity IDE，封掉 3 个。
- 社区共识：**「same projects across different accounts」+「request fingerprints」才是封号模式**；单纯多账号通常会得到不同类型的封禁。
- 该用户澄清：**是真金白银买的 Pro 计划（18 个月），Gmail 还能用，但 Gemini 与 Antigravity 的 Pro 服务不可用。**
- 多人反映**申诉邮件无回复**。

## 五、封号时间线

| 时间 | 事件 |
|---|---|
| 2026-02（春节前后） | 首轮大规模封号。起因：OAuth 授权滥用——第三方工具（Zerogravity、OpenClaw、OpenCode、Claude Code、CLIProxyAPI 等）让订阅账号被其他 AI 客户端调用 |
| 2026-02-13 ~ 02-19 | 社区集中讨论恢复方法；申诉邮箱 `gemini-code-assist-user-feedback@google.com` |
| 2026-03-01 前后 | 官方在 gemini-cli Discussions `#20632` 发公告：全面解封 + 再认证流程 + 二振制 |
| 2026-08-30 | **新一轮封号**（Linux.do topic 2830699）：针对反代工具用户，谷歌加强非官方 API 调用风控检测 |
| 2026-09-07 | **条款修订**：明确处罚范围为 Antigravity / Gemini CLI 账号，不连坐整个 Google 账号；第三方工具禁令不变 |

## 六、封号时的表现（自查用）

- Antigravity **登不上**，或报模糊提示「设置你的账户时出现了意料之外的问题」
- CLIProxyAPI / CPA 侧显示 `Failed to load quota`
- 反代侧报 `403 ... service has been disabled ... for violation of Terms of Service`
- **Gmail 网页仍可用**（2026-09 修订后这一点被条款明确为「不连坐」）

## 七、处置梯度（2026-03 官方公告）

1. **全面解封** —— 受影响账号 1–2 天内自动恢复
2. **再认证流程（recertification）** —— 违规时收到通知邮件 + 重新认证表单，填完恢复
3. **二振制** —— **初犯填表单可恢复，二犯直接永久封号**
4. **条款未变** —— 第三方工具/proxy 依然违规，解封只是补救措施

## 八、三类「代理」的风险分级（**最常被混淆，必须分开**）

社区里「用代理会不会被封」吵不出结论，是因为把三件事都叫「代理」：

### ① 网络出口代理（VPN / 系统代理 / 按域名分流）

- **目的**：让客户端**能连上**。地区不可用时的实际必需手段。
- **判定：低—中。** 条款没有单独禁止使用代理（否则所有跨境用户都要被封）。真实风险有两条：
  1. **代理出口 IP 与账号归属地不一致** —— 是画像里的一个信号（但**不是封号主因**）。
  2. **共享出口 IP 上的其他用户** —— 同一 IP 上若有其他违规用户，可能带来关联风险。
- **实操建议**：
  - 优先**独享或低共享度**的出口，避免和大量同类用户挤同一 IP。
  - 同一账号**固定出口**，不要短时间来回横跳不同国家/地区的节点。
  - **验证要看对端看到的出口**，不是只看本地代理配置。例如：
    `curl -x http://127.0.0.1:<port> "https://dns.google/resolve?name=o-o.myaddr.l.google.com&type=TXT"`
    读返回里的 `edns0-client-subnet` = Google 侧看到的出口；再 `curl -x ... https://ipinfo.io/json` 对比默认出口。
  - **分流器是新的单点**：它没起来 = 全部代理流量断。要做健康检查。

### ② 反代 / OAuth 复用（CLIProxyAPI / Zerogravity / OpenClaw / OpenCode）

- **目的**：把订阅额度**挪到别的客户端**用。
- **判定：红线。** 条款第 6 条明文禁止，官方点名 OpenClaw + Antigravity OAuth。
- 这类工具**不是代理，是身份复用**。无论套几层代理都改变不了它违规的性质。

### ③ 客户端注入 / 篡改（DLL 劫持 / asar 注入 / 改写客户端 config）

- **目的**：改变客户端自身行为（网络路由、界面语言、功能开关）。
- **判定：中。** 属于「修改客户端」，实践上普遍存在、极少被单独追责（如界面汉化补丁）。
- **但有一条硬边界**：**一旦其目的是绕过配额或身份校验，就落入第 6 条红线。**
- 注意区分：**DLL 只做网络路由**（等价于系统代理，属①）与 **DLL 篡改身份/配额校验**（属红线）是两回事。
- 实务提醒：这类注入往往**被客户端自动更新清掉**，需要幂等自愈机制；且**注入后要回读校验**（客户端可能周期性重写自己的 config）。

### 判据一句话

> **问：这个东西改变的是「我怎么连上」，还是「我以谁的身份、用多少额度」？**

- 只改「怎么连上」→ 出口代理，风险来自**出口 IP 质量与共享度**。
- 改「身份 / 额度」→ **红线**。
- 改「客户端自己」→ 看目的：纯路由/界面属中风险；目的是绕过配额或身份校验 → **红线**。

### 出口 IP 加固实操（2026-10-01 实测，含两个通用坑）

**1. 验证出口要用「对端看到什么」，不是「本地配置写什么」**

```
# 默认出口
curl -x http://127.0.0.1:<代理端口> https://ipinfo.io/ip
# Google 侧看到的出口（关键）
curl -x http://127.0.0.1:<代理端口> \
  "https://dns.google/resolve?name=o-o.myaddr.l.google.com&type=TXT"
# 读返回里的 edns0-client-subnet —— 那才是 Google 实际看到的网段
```

**2. 用 ip-api 量化 IP 质量**（`hosting` / `proxy` 两个字段）：

```
curl "http://ip-api.com/json/<IP>?fields=status,isp,org,as,hosting,proxy"
```

- 两项都 `false` → 干净出口（适合走 Google）。
- `hosting:true` / `proxy:true` → 机房/代理特征，**不要给 Google 用**。
- 实测对照：`38.244.39.84` 两项 false；`144.34.229.116` 两项 true。

**3. ⚠️ 通用坑一：判断「开机自启是否有效」，不能看文件在不在**

Windows **快速启动**（`HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power` → `HiberbootEnabled=1`）下，
「关机」是混合休眠，下次开机是**恢复会话**，**Startup 文件夹里的快捷方式不会被执行**。

→ 于是「快捷方式存在」长期给出**假保证**。正确判据：
- 看**计划任务**状态（`Get-ScheduledTask`），而不是 Startup 快捷方式；
- 更根本的是看**进程/端口实际在不在**。
- 计划任务用 `AtLogOn` 触发器，不受快速启动影响。

**4. ⚠️ 通用坑二：`netstat` 的字段顺序**

`netstat -ano` 的行格式是 **「协议 → 本地地址:端口 → 远端 → LISTENING → PID」**，
`LISTENING` 在端口**之后**。所以：

```bash
netstat -ano | grep "LISTENING.*:14185"   # ✗ 永远匹配不到，误判成「端口没在听」
netstat -ano | grep LISTENING | grep ":14185"   # ✓ 正确
```

**5. 让出口加固可持续**：把「分流器在跑 + 系统代理指向它」写成**幂等自愈脚本**，
挂进已有的周期任务（登录触发 + 定时循环）。自愈脚本里有一个关键安全设计：
**只有在代理进程已就绪时才改系统代理**，否则会把整机网络改到死端口上。

**6. ⚠️ 必须同时有「反向安全阀」—— 代理指向死端口 = 整机断网**

只有「就绪才改」还不够。如果代理进程**之后死了**，系统代理仍指着它 → 全机断网。
自愈脚本必须双向：

- 代理进程**在跑** 且 系统代理 ≠ 目标 → 设为目标；
- 代理进程**不在跑** 且 系统代理 = 目标 → **立即回退到常驻的前端**（如 v2rayN 的 10808）。

**宁可暂时走被标记的出口，也不能让整机断网。**

**7. ⚠️ 自建内核必须换名，否则会被「按名杀进程」带走**

实测事故：v2rayN **自动升级并重启**时，会按**镜像名**清理旧的 `xray.exe` 进程 ——
自建的分流器用的也是 `xray.exe`，**被一起杀掉**，于是系统代理指向死端口、断网。

→ 做法：给自建实例**复制一份换过名的内核**（如 `ag-split-core.exe`），任务与脚本都指向它。

> **通用规则：两个进程共用同一个可执行文件名，就会被任何「按名杀进程」的操作一起带走。**
> 凡是与别的软件共用内核（xray / v2ray / sing-box / mihomo）的场景，都要给自建实例换名。

**8. 受控故障注入：证明自愈不是纸面设计**

改完自愈逻辑后，**主动杀掉代理进程**，跑一次自愈脚本，验证：
端口恢复 + 出口仍正确 + 退出码 0。只在真的注入过一次之后，才能说「它是可靠的」。

**9. ⚠️ 按命令行匹配杀进程会自匹配**

`Get-CimInstance Win32_Process | Where CommandLine -like '*关键字*'` 会**把执行这条命令的宿主进程自己匹配上**
（它的命令行里就含那个字面量）→ 脚本自杀。要**排除自身 PID**，或把匹配串动态拼装出来。

**10. 回滚顺序**：停用分流时 **先把系统代理改回常驻前端，再停任务**；顺序反了会断网。

## 九、申诉

- 邮箱：`gemini-code-assist-user-feedback@google.com`
- 社区反馈：回复率低；2026-03 那轮的恢复主要靠**官方统一解封**而非逐个申诉
- 登录 Antigravity 后可能直接弹出申诉链接
