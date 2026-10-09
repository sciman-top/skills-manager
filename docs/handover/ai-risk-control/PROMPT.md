# 提示词：Antigravity × Gemini × WorkBuddy 风控加固（在新电脑上复现）

> 用法：把**本文件全文**复制粘贴到新电脑上的 WorkBuddy / CodeBuddy 对话里。
> 若同时带上了 `tools/` 目录，按文末「交付物落位」那张表放好脚本再开始（含 `tools/workbuddy/`）。

---

## 0. 你的任务

在一台 **Windows** 电脑上复现一套已验证通过的加固方案，解决三件事：

1. **Antigravity（Google 的 AI IDE）在不开 TUN 时的代理穿透** —— 让 Sign In、`language_server.exe`、`daily-cloudcode-pa.googleapis.com` 等流量确实走代理。
2. **核验 Google 出口一致性、可达性与错误来源** —— 记录出口及第三方分类，不把分类结果视为账号安全或模型质量证明。
3. **WorkBuddy（腾讯）的网络配置与错误分诊** —— 核验直连覆盖、配额与重试，结合真实错误记录排查，见第 14 节。

**最重要的设计原则（务必遵守）**：
> **不要把全部流量切到「干净出口」。**
> 用户日常联网软件依赖某条 CN 优化线路（延迟更低、吞吐更高）。正确做法是**按目标域名分流**：Google 系域名走干净出口，其余全部原样走原有线路。整机全局切换会明显拖慢日常使用，已被否决过一次。

**执行纪律**：每一步都要**先测量、后动手**，不要凭猜测改配置。所有改动前先备份并记录 SHA-256。做完必须跑验收。

---

## 1. 第 0 步：侦察（不要跳过，不要先改任何东西）

先摸清本机实际情况，把结果列出来：

1. **Antigravity 是否安装、什么版本、装在哪**
   - 常见路径：`%LOCALAPPDATA%\Programs\Antigravity`
   - 版本看 `%APPDATA%\Antigravity\logs\main.log` 里的 `Starting app (vX.Y.Z)`
2. **antigravity-proxy 是否已部署**
   - 判据：Antigravity 安装目录下同时存在 `version.dll` 和 `config.json`
   - `config.json` 里 `_version` 字段是版本号；到 <https://github.com/yuaotian/antigravity-proxy/releases> 核对是否最新
   - **若未部署**：先按下节安装，再继续
3. **代理客户端是什么、装在哪、监听哪些端口**
   - 本方案以 **v2rayN** 为参考实现（配置文件在 `<v2rayN目录>\guiConfigs\guiNConfig.json` 与 `guiNDB.db`）
   - 若用户用的是 Clash / Mihomo / sing-box 等，**第 4 步的分流器实现方式需要相应调整**，但第 3、5、6 步思路不变
4. **有哪些节点可用**，各自域名/地址是什么
5. **记录当前状态**：系统代理开关、用户级代理环境变量、当前出口 IP

---

## 2. 第 1 步：测量出口，判定哪条线路是「干净出口」

对**每一条**可用线路，实测它的出口 IP 及其风控属性。用 v2rayN 逐个切换节点，或用临时 xray 实例隔离测试（推荐后者，不影响现有配置）：

```bash
# 出口 IP 及归属
curl -s -m 20 -x http://127.0.0.1:<本地端口> https://ipinfo.io/json

# 风控属性（关键）
curl -s -m 20 -x http://127.0.0.1:<本地端口> \
  "http://ip-api.com/json/?fields=status,country,city,isp,org,as,hosting,proxy"
```

**判定规则**：

| 字段 | 含义 |
|---|---|
| `hosting: true` | 机房 / 托管 IP —— 风控高危 |
| `proxy: true` | 已被公开识别为代理 / VPN 出口 —— 风控高危 |

- **`hosting` 与 `proxy` 都为 `false` 的那条 → 定为「干净出口」**
- 全部线路都被标记 → 选标记最少的那条，并在报告里明确写「这只是降低命中概率，不是消除；彻底解决需要住宅 / ISP 出口」
- **只有一条线路** → **不要做分流**，跳过第 4 步，只做第 3、5、6、7 步，并在报告里说明原因

同时记录延迟与吞吐做取舍依据：

```bash
# 延迟（各跑 5 次取中位数）
for i in 1 2 3 4 5; do curl -s -m 20 -x <代理> -o /dev/null -w "%{time_total} " https://daily-cloudcode-pa.googleapis.com/; done
# 吞吐
curl -s -m 40 -x <代理> -o /dev/null -w "%{speed_download} B/s\n" "https://speed.cloudflare.com/__down?bytes=10000000"
```

> 实测参考：CN 优化线路 vs 普通线路的差距通常只有 **延迟 ±0.07s、吞吐 ±15%**，不要因为这点差距就放弃分流。

---

## 3. 第 2 步：antigravity-proxy 部署 / 加固

若尚未安装，按官方 Release 说明部署：
- 桌面端把 `ide/` 里的 `version.dll` + `config.json` 复制到 **`Antigravity.exe` 同级目录**
- 架构必须匹配（x64 对 x64）；`version.dll` 与 `config.json` 必须来自**同一次构建**
- 启动后安装目录 `logs\proxy-YYYYMMDD.log` 里应出现 `使用全量模式` 与 `所有 API Hook 安装成功`

### ⚠️ 必读：Antigravity 自动更新会清掉劫持文件

实测踩过：一次自动更新把安装目录从 `%LOCALAPPDATA%\Programs\Antigravity` 换成了 `%LOCALAPPDATA%\Programs\antigravity`（**连目录名大小写都变了**），旧目录整个删除，`version.dll` 与 `config.json` 一并消失，**代理静默失效**。

所以必须做两件事：

1. **在安装目录之外留一份主副本**（建议 `D:\TOOL\antigravity-proxy\v2.4-x64\`，同时保留原始 release zip 用于核对哈希）。
2. **准备一键恢复脚本**（见 `tools/redeploy.ps1`）：自动定位安装目录 → 退出 Antigravity → 把 `version.dll` + `config.json` 复制回去 → 回读校验。

部署后**务必记录 `version.dll` 的 SHA-256**。下次恢复时用它确认拿到的是同一次构建（本次实测下载包与原部署哈希完全一致：`40f037232a180da8dff7611021270549fcc4e208580d8bf0f70bc9975f871b5f`）。

**另外**：定位安装目录时**不要硬编码大小写**（用大小写不敏感的匹配），否则更新后会找不到。

然后编辑 `config.json`：

```diff
   "proxy": {
     "type": "socks5",
     "host": "127.0.0.1",
-    "port": 10808
+    "port": 10810          ← 指向第 4 步的分流器；若不做分流则保持代理客户端端口
   },
   "diagnostics": {
-    "agent_ip_probe": false
+    "agent_ip_probe": true   ← 开启出口 IP 持续自检，命中机房特征时写进 proxy 日志告警
   },
```

**不要改的项**（改了会坏事）：
- `dns_mode` —— 它**只管 TCP 53 端口**，`direct`（透传）才是官方推荐值
- `allowed_ports: [80, 443]`、`fake_ip`、`udp_mode: auto`、`ipv6_mode: proxy`
- `target_processes` —— 需包含 `Antigravity.exe`、`language_server.exe`、`node.exe`、`agy.exe`

### ⚠️ `agent_ip_probe` 在 v2.4 上无法持久开启（实测）

DLL 运行时会**周期性重写 `config.json`**，并把 `diagnostics.agent_ip_probe` 写回 `false`（文件修改时间会刷新）。也就是说这项自检能力在当前版本上**不可用**，不要指望它。所以：

- 自检脚本要把这一项降级为 **INFO**，不要做成 WARN / FAIL —— 否则就是永久误报。
- 出口 IP 的判断改用外部探测（见第 1 步与第 7 步的分流验证）。
- 更重要的推论：**DLL 会重写 `config.json`**，所以对它的任何手工修改都可能在 Antigravity 运行后被覆盖。改完必须**回读确认**，并尽量在 Antigravity 完全退出时改。

**必须理解的注入行为**（排障时要用）：
- 宿主 `Antigravity.exe` 与 `language_server.exe` 走**全量模式**（装网络 Hook）
- **Chromium 网络服务子进程走「旁路模式」**（只装进程创建 Hook）→ **Sign In 等 Chromium 侧流量完全依赖系统代理**，DLL 不接管
- `language_server.exe` 实际是**读环境变量 `HTTPS_PROXY` 自己连代理**的（DLL 日志里表现为 `本地目标全透明旁路 → 127.0.0.1:<代理端口>`）
- **推论**：要让 Antigravity 全部流量走同一条出口，**系统代理 + 用户级环境变量 + DLL 上游三者必须一致**

---

## 4. 第 3 步：搭建 Google 专用分流器

一个独立的 xray 实例，前端 `127.0.0.1:10810`（socks + http 混合入站）：

```
                        ┌─ Google 系域名 ─→ 干净出口节点
所有联网软件 ─→ 10810 ─┤
             (分流器)   └─ 其余全部 ─────→ 代理客户端本地入站 ─→ 原线路
```

- 若 `tools/gen-config.py` 已就位：把它放到 `D:\TOOL\v2rayN\ag-split\gen-config.py`，然后：
  ```bash
  # 先列出本机有哪些节点
  python gen-config.py --list
  # 用第 1 步选出的「干净出口」节点的 IndexId 生成
  python gen-config.py --node <IndexId>
  ```
  路径 / 端口与默认值不同时，用环境变量覆盖：`V2RAYN_DIR`（默认 `D:\TOOL\v2rayN`）、`AG_SPLIT_PORT`（默认 10810）、`AG_SPLIT_UPSTREAM_PORT`（默认 10808）。
  要增减走干净出口的域名，改脚本里的 `GOOGLE_DOMAINS`。
- 否则手写一份 xray 配置，结构照抄 `tools/gen-config.py` 生成的结果

**走干净出口的域名**（后缀匹配）：
```
domain:googleapis.com        ← daily-cloudcode-pa / cloudcode-pa / generativelanguage / oauth2
domain:google.com            ← accounts.google.com / clients6.google.com
domain:google
domain:gstatic.com
domain:googleusercontent.com
domain:withgoogle.com
domain:gvt1.com
domain:ggpht.com
domain:google.dev
```
**刻意不含** `youtube.com` / `googlevideo.com` —— 避免把大带宽视频流量挪到较慢的线路。

**WorkBuddy 五域直连规则**（`WORKBUDDY_DIRECT_DOMAINS`，2026-10-09 新增，防回归守护见 `ag-health-check.ps1`）：
WorkBuddy（Electron）带 `HTTP_PROXY` 就硬编码代理并短路一切例外表（§14.1），因此分流器还须有
第二道防线——`workbuddy.ai` / `workbuddy.cn` / `codebuddy.ai` / `codebuddy.cn` / `lkeap.cloud.tencent.com`
→ `direct(freedom)`，流量即使被 env 送进分流器也从本机线路直连发出。

路由规则（顺序不能错）：
1. `port=443 network=udp → block`（封 QUIC，保证出口一致）
2. `domain=[上面的列表] → 干净出口`
3. `domain=[WorkBuddy 五域] → direct(freedom)`（env 短路兜底）
4. `network=tcp,udp → 代理客户端本地入站`（**兜底，必须存在**）

**从 v2rayN 数据库取节点凭据的字段映射**（v2rayN 7.x 的 `ProfileItem` 表）：
| xray 需要 | v2rayN 列 |
|---|---|
| UUID | **`Password`** 列（不是 `Id`） |
| `flow`（如 `xtls-rprx-vision`） | `ProtoExtra` JSON 里的 `Flow` |
| `encryption` | `ProtoExtra` JSON 里的 `VlessEncryption` |
| `network` | `Network` 列，**`raw` 要映射成 `tcp`** |
| `security` / `sni` / `fingerprint` / `publicKey` / `shortId` | `StreamSecurity` / `Sni` / `Fingerprint` / `PublicKey` / `ShortId` |

**不要用 `geosite:google`** —— 依赖 `geosite.dat` 资源路径，容易加载失败；用显式 `domain:` 更确定。

启动前必须做语法校验（否则会静默失败）：
```bash
<v2rayN目录>\bin\xray\xray.exe run -test -c "<分流器配置路径>"
# 期望输出：Configuration OK.
```

---

## 5. 第 4 步：把「前门」接到分流器

用 `tools/wire-split.ps1`（放到 `D:\TOOL\v2rayN\ag-split\`），或手工做这四件事：

1. **系统代理 → `127.0.0.1:10810`**（`HKCU\...\Internet Settings` 的 `ProxyEnable=1`、`ProxyServer=127.0.0.1:10810`；**例外表保持不动**）
2. **用户级环境变量**：`HTTP_PROXY`/`HTTPS_PROXY` → `http://127.0.0.1:10810`，`ALL_PROXY` → `socks5h://127.0.0.1:10810`；**`NO_PROXY` 保持不动**
3. **广播 `WM_SETTINGCHANGE`**，否则已运行的进程和新启动的进程看不到新环境变量
4. **开机自启**：在 `[Environment]::GetFolderPath('Startup')` 放一个指向 xray 的 `.lnk`，参数 `run -c "<分流器配置路径>"`，窗口样式设为最小化

**同时必须让代理客户端交出系统代理控制权**（否则它每次启动会把系统代理改回自己的端口，Chromium 侧就绕过分流）：

- v2rayN：把 `guiNConfig.json` 的 `SystemProxyItem.SysProxyType` 改成 **`2`（Unchanged）**
- ⚠️ 枚举值是 `0=ForcedClear（清除）`、`1=ForcedChange（设置）`、`2=Unchanged（不改变）`、`3=Pac`。**填 0 会把系统代理清掉，不是「不改变」**，别搞错。

---

## 6. 第 5 步：代理客户端路由加固

在 v2rayN 的**激活路由项**（`guiNDB.db` 的 `RoutingItem` 表，`IsActive=1` 那行）里，把「代理Google」那条规则的 `Domain` 数组补上显式域名（防 `geosite` 分类随上游更新变动）：

```
geosite:google + domain:googleapis.com + domain:google.com + domain:gstatic.com
+ domain:googleusercontent.com + domain:withgoogle.com + domain:googlevideo.com
+ domain:gvt1.com + domain:ggpht.com
```

规则必须排在 `geosite:cn` **之前**。改完把 `RuleSet` 写回（JSON，`separators=(',',':')`），并核对 `RuleNum`。

**改 v2rayN 任何配置（`guiNConfig.json` 或 `guiNDB.db`）之前，必须先让它完全退出**，否则它退出时会用内存里的状态覆盖你的修改。

---

## 7. 第 6 步：凭据卫生

检查 `<v2rayN目录>` 及周边是否存在**明文存放服务器密码 / 密钥 / 订阅令牌**的文件（常见名如 `配置.txt`）。
- 若有：**备份一份**，然后把明文密码替换成占位符，并在最终报告里明确告知「备份中仍含明文，请轮换密码后删除」
- 不要擅自删除凭据 —— 用户可能没有第二份记录

---

## 8. 第 7 步：验收（必须做，且要给出证据）

### 8.0 验收分三层，不要跳层

| 层 | 脚本 | 证明什么 | 是否碰真实系统 |
|---|---|---|---|
| ① 受控验收 | `ensure-split.test.ps1` | **脚本的判定逻辑**正确（23 个断言） | 否（临时目录 + 临时注册表键） |
| ② 受控实战验收 | `ag-split-live-acceptance.ps1` | **整套自动化**真能自愈（11 个断言） | 是（真故障注入，自动收尾） |
| ③ 全量自检 | `ag-health-check.ps1` | 当前状态无 FAIL | 只读 |

```powershell
pwsh -File D:\TOOL\v2rayN\ag-split\ensure-split.test.ps1   # 期望 PASS 23 / FAIL 0
```

夹具覆盖的分支：分流器在跑 / 不在、代理指向它 / 别处 / 被禁用、例外表完整 / 缺失、
缺内核 / 缺配置、env 已正确 / 需修正 / 跳过、备份落盘、出口探测开关，
**以及最关键的「安全阀」—— 系统代理指向死端口时必须回退**。

> 该脚本靠**参数注入**做到不碰真实状态：`-Port` / `-ProxyRegPath` / `-EnvScope Process` /
> `-NoStart -NoEgressProbe -NoStartupLnk`。**改造被测脚本时不要删掉这些参数**，否则验收失效。

### 8.1 分流正确性 —— 决定性证据

用 Google 官方的客户端 IP 回显接口，看 **Google 侧实际看到的出口**：

```bash
curl -s -m 25 -x http://127.0.0.1:10810 \
  "https://dns.google/resolve?name=o-o.myaddr.l.google.com&type=TXT"
# 从返回里找 edns0-client-subnet，例如 38.244.39.0/24 → 这就是 Google 看到的出口
```

再对比默认出口：
```bash
curl -s -m 25 -x http://127.0.0.1:10810 "http://ip-api.com/json/?fields=query,isp,hosting,proxy"
```

**判定：两者 /24 必须不同。相同 = 分流没生效。**

### 8.2 连通性

| 类别 | 目标 | 期望 |
|---|---|---|
| Google | `daily-cloudcode-pa` / `oauth2` / `cloudcode-pa` / `generativelanguage` | HTTP **404**（正常，证明 TLS + 路由通） |
| Google | `www.google.com/generate_204` | HTTP 204 |
| 日常 | github.com / registry.npmjs.org | HTTP 200，且出口 = 原线路 |
| 协议 | 经 10810 用 **socks5h** 也通（DLL 用的是 socks5） | 通 |

### 8.3 全量自检

运行 `tools/ag-health-check.ps1`（放到 `D:\TOOL\v2rayN\ag-health-check.ps1`），按本机实际改端口/路径常量。它应输出 **0 FAIL**。覆盖 23 项：代理进程、三个入站端口、系统代理与例外表、`NO_PROXY`、三个代理环境变量、**分流正确性**、Google 端点、DLL 与配置、开机自启、应用日志风控特征串。

### 8.4 应用日志

扫 `%APPDATA%\Antigravity\logs` 与 Antigravity 安装目录的 `logs`，确认**没有**这些串：
```
location is not supported        ← 出口被 agent mode 拒绝的头号信号
FAILED_PRECONDITION
RESOURCE_EXHAUSTED
PERMISSION_DENIED
```
⚠️ **不要扫 `%USERPROFILE%\.gemini\antigravity\brain\`** —— 那里是会话记录，会把你自己的讨论文本当成命中，属于自污染。

### 8.5 受控实战验收（真故障注入，必做）

```powershell
pwsh -File D:\TOOL\v2rayN\ag-split\ag-split-live-acceptance.ps1   # 期望 PASS 11 / FAIL 0
```

它在真机上做故障注入，约 4–5 分钟（含等真实看门狗）：

| 项 | 注入 | 断言 |
|---|---|---|
| L2 手动自愈 | 杀掉分流器内核 | 跑 `ensure-split.ps1` 后端口恢复、exit 0 |
| **L3 看门狗自愈** | 杀掉内核 | **等真实看门狗（≤3 分钟）自动拉起**（本次实测 115.2 秒） |
| **L4 安全阀** | 系统代理临时指向死端口 | `ensure-split.ps1` 应**回退到 10808** |
| L5 出口证据 | — | 默认出口可达，并按需测量 Google 节点出口；测量不证明账号安全 |

需要节点出口证据时，按需运行同目录部署的 `ag-egress-probe.ps1` 或
`ag-health-check.ps1 -ProbeGoogleEgress`。临时实例测量所选节点的出口与第三方分类，
不能证明已登录客户端的请求路由、模型接受情况或账号安全。
`AgSplitWatchdog` 应附带 `-NoEgressProbe`，每三分钟只做本地自愈。

**安全设计**：全程 `try/finally`，结束时**无条件**把系统恢复到「分流器在跑 + 代理指向它」；
若分流器起不来则回退代理，**绝不把机器留在断网状态**。

> **为什么要做 L3 而不只做 L2**：L2 证明「脚本能修」，L3 证明「**没人看着的时候也会被修**」。
> 这两件事完全不同 —— 自动化真正的价值在 L3。

---

## 9. 硬约束与已知坑（踩过的，照做）

1. **改代理客户端配置前必须先让它完全退出**，否则退出时覆盖。
2. **不要强杀 v2rayN**：它来不及清理，会留下 `ProxyEnable=1` 指向**死端口**的系统代理，浏览器直接断网。真要强杀，杀完必须立刻拉起新实例或手动清系统代理。
3. **拉起 GUI 进程可能失败**：在部分受限环境里，用 `cmd /c start`、`Start-Process`、`explorer.exe` 拉起的进程会被沙箱回收；`schtasks.exe` 可能被程序黑名单拦截。**可行做法**：用受管后台任务方式启动（`run_in_background`），它能跨多次工具调用存活。如果观察不到存活，就明确告诉用户「请手动双击启动」。
4. **写 `.ps1` 文件必须带 UTF-8 BOM**，否则 PowerShell 5.1 会把中文读成乱码。用 `encoding='utf-8-sig'` 写。
5. **`.ps1` 里避免非 ASCII 路径**，并且只用 PowerShell 5.1 语法（不要 `&&`、`||`、三元 `?:`、`??`）。
6. **Git Bash 与 Python 的 `/tmp` 不是同一个目录**，跨两者传临时文件用绝对路径。
7. **不要用 `geosite:` 依赖外部数据文件**做分流器规则（路径问题会让 xray 起不来）。
8. **xray 的兜底路由规则必须带至少一个字段**（如 `"network":"tcp,udp"`），否则报 `this rule has no effective fields`。
9. **不要把 `NO_PROXY` 写成 `*.` 通配符** —— Python/Node/Go 走后缀匹配，裸域名本就覆盖子域，写 `*.` 反而永远匹配不上。
10. **分流器是新的单点**：它没起来 = 全部代理流量断。所以开机自启 + 自检 + 明确的手动拉起命令，三样都要给用户。
11. **⚠️ 快速启动会让 Startup 文件夹项静默失效。** `HiberbootEnabled=1` 时，「关机」是混合休眠，
    下次开机是恢复会话，**Startup 里的快捷方式不会被执行**。
    → 判断「开机自启是否有效」**不能看文件在不在，要看进程实际有没有跑起来**；
    正解是用**计划任务**（`AtLogOn` 触发器），它不受快速启动影响。
    （本机曾因此长期报 PASS —— 一个假保证。）
12. **⚠️ 自建内核必须换名，否则会被「按名杀进程」带走。** 实测事故：v2rayN 自动升级并重启时，
    会**按镜像名**清理旧的 `xray.exe` 进程 —— 自建分流器若也叫 `xray.exe`，会被一起杀掉，
    系统代理指向死端口 → **整机断网**。
    → 做法：给自建实例**复制一份换过名的内核**（如 `ag-split-core.exe`），任务与脚本都指向它。
13. **⚠️ 光有「就绪才改代理」不够，必须配「反向安全阀」。** 代理进程**之后死了**，
    系统代理仍指着它 → 断网。自愈脚本要双向：在跑就把代理指向它；**不在跑就回退到常驻前端**。
    **宁可暂时走被标记的出口，也不能让整机断网。**
14. **`netstat` 的字段顺序**：`netstat -ano` 是「协议 → 本地地址:端口 → 远端 → LISTENING → PID」，
    `LISTENING` 在**端口之后**。所以 `grep "LISTENING.*:14185"` **永远匹配不到**，会误判成「端口没在听」。
    正确写法：`netstat -ano | grep LISTENING | grep ":14185"`。
15. **按命令行匹配杀进程会自匹配**：`Where CommandLine -like '*关键字*'` 会把**执行这条命令的宿主进程自己**匹配上
    （它的命令行里就含那个字面量）→ 脚本自杀。要**排除自身 PID**，或把匹配串动态拼装出来。
16. **回滚顺序**：停用分流时**先把系统代理改回常驻前端，再停任务**；顺序反了会断网。

---

## 10. 最终要交付给用户的东西

1. **改动清单**：每个文件的路径 + 改动前后的 SHA-256 + 原件备份位置
2. **实测数据**：两条线路的出口 IP / `hosting` / `proxy` / 延迟 / 吞吐；分流验证结果（Google 侧出口 vs 默认出口）
3. **验收结果**：自检脚本的 PASS/WARN/FAIL 汇总
4. **自检脚本**：只读、可重复运行、有 FAIL 返回非零退出码
5. **回滚步骤**：
   - 只去掉分流（系统代理 + 三个环境变量 + DLL 端口改回原值，删自启快捷方式）
   - 整体回滚（从备份恢复）
6. **仍然存在的风险**，至少包括：
   - 两条线路可能**都是机房 IP**，本次只是降低命中概率，不是消除
   - **Chromium 侧只有系统代理一条路**（DLL 对网络服务子进程是旁路），所以「系统代理常开且指向分流器」是硬约束
   - **时区 / 语言与出口地理不一致**（本机 GMT+8 / 中文 vs 出口美国）是 Google 的强特征 —— 改它会影响日常使用，**不要擅自改**，写进报告让用户决定

---

## 11. 汉化补丁（可选，但用户很可能需要）

Antigravity 的界面汉化通常用的是开源项目 **[liominsb/Antigravity-Chinese-Localization](https://github.com/liominsb/Antigravity-Chinese-Localization)**。它**不是 VS Code 扩展**，而是直接给 `resources/app.asar` 注入汉化引擎（原生菜单/托盘 + DOM 实时翻译）。

**判定汉化是否生效**：`app.asar` 里能否搜到标记 `// Antigravity 2.0 Chinese Localization Engine`。

> 注意：装一个 `ms-ceintl.vscode-language-pack-zh-hans` 扩展**只覆盖 VS Code 内核文案**，覆盖不了 Antigravity 自己的界面。两者是两回事，别混淆。

**它同样会被更新清掉。** 恢复方式：

```bash
# 1) 取与当前 Antigravity 版本对齐的 Release（例：Antigravity 2.18.1 → 汉化 v2.18.1）
#    下载 default.zip + SHA256SUMS.txt，核对哈希后解压到工具目录
# 2) 完全退出 Antigravity
# 3) 执行 —— 会解包【当前】app.asar 再注入，因此跨版本安全
node localize.js --now
```

要点：

- **绝不要用 Release 里预打包的 `app.asar` 覆盖安装目录** —— 那是针对特定 Antigravity 版本的**完整应用代码**，版本不匹配会直接把客户端搞坏。**只用 `localize.js --now`。**
- 它依赖 `npx -y @electron/asar`，需要 Node.js，且**首次运行要联网**（之后走 npx 缓存）。建议先预热一次。
- 它会自动把官方原版备份成 `app.asar.bak`（且不会备份已被汉化的文件），随时可 `node localize.js --restore` 无损还原。
- 它**不会自动重启** Antigravity，需要你自己拉起。
- 编码坑：node 输出是 UTF-8，中文 Windows 控制台默认 GBK，直接捕获会乱码 —— 调用前设 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`。

---

## 12. 把「更新后自愈」做成自动化

`tools/ensure-patches.ps1` 是**幂等**自愈脚本，一次覆盖代理 + 汉化两件事：

| 检查项 | 判定逻辑 | 动作 |
|---|---|---|
| 安装目录 | 大小写不敏感地找 `%LOCALAPPDATA%\Programs\*ntigravity\Antigravity.exe` | 找不到则退出 |
| `version.dll` | 缺失 → 补；哈希不一致且未运行 → 覆盖；**运行中 → 跳过并记「待处理」**（不写正在被加载的 DLL） | 从主副本复制 |
| `config.json` | **比对「有效配置项」而不是文件哈希** —— DLL 会周期性重写这个文件（改换行符、格式、`diagnostics`），按哈希比会永远误判 | 有效项不一致时按主副本覆盖，但**保留 DLL 写入的 `diagnostics`** |
| `app.asar` | 是否含汉化注入标记 | 缺标记且 Antigravity 未运行 → 跑 `localize.js --now`；运行中 → 记「待处理」 |

再用 `tools/register-task.ps1` 注册计划任务（**每 30 分钟 + 登录时**各跑一次；间隔在脚本顶部的 `$IntervalMinutes` 改）。踩过的坑：

- **轮询间隔不用太密。** 汉化只能在 Antigravity 未运行时补（要独占 `app.asar`），而更新后通常是「秒级重启」，任何间隔都抓不到那个窗口。所以轮询真正起作用的时机是「Antigravity 关闭之后」——间隔越小收益越有限。30 分钟够用，在意响应速度可调 15，不在意可调 60。
- **不要用 `schtasks.exe`**（可能被程序黑名单拦截）；用 PowerShell 的 `New-ScheduledTask*` / `Register-ScheduledTask`。
- **不要用 `wscript.exe` / `mshta.exe` 做隐藏包装**（LOLBin，会被安全策略拦）。隐藏窗口用 `-WindowStyle Hidden`。
- 登录类型优先 `S4U`，失败回退 `Interactive`（S4U 常因权限被拒）。
- **先查有没有既存任务**（`Get-ScheduledTask | Where-Object { $_.TaskName -like '*Antigravity*' }`），**有就改造它，不要再建一个** —— 两套机制并存会互相打架。
- 脚本必须幂等，重复跑不产生副作用。

**验证方式（必做）**：人为破坏再跑一遍 —— 关掉 Antigravity，删掉 `version.dll` / `config.json`，把 `app.asar.bak` 覆盖回 `app.asar`，然后跑 `ensure-patches.ps1`，确认三项全部恢复（`version.dll` 哈希要一致、`app.asar` 要重新出现注入标记）。

### 12.1 分流器的自愈（**同样必须自动化**）

`ensure-patches.ps1` 的第 4 节会调用 `ensure-split.ps1`，所以**代理 + 汉化 + 分流器**由同一个循环覆盖。
但分流器还需要**自己的存活保障**，用 `tools/register-split-task.ps1` 一次注册两个任务：

| 任务 | 触发 | 作用 |
|---|---|---|
| `AgSplitEgress` | 登录时 | 跑分流器内核（`ag-split-core.exe`），无执行时限，崩溃自动重启 3 次 / 间隔 1 分钟 |
| `AgSplitWatchdog` | **每 3 分钟** + 登录时 | 跑 `ensure-split.ps1`：死了就拉起；**拉不起来就回退系统代理** |

```powershell
pwsh -File D:\TOOL\v2rayN\ag-split\register-split-task.ps1
```

**注册权限坑（实测）**：未提权时 `Register-ScheduledTask` 只有 **`Interactive` + `Limited`** 能成功；
`S4U` / `Highest` / `ServiceAccount(SYSTEM)` 全部报「拒绝访问」。

**为什么内核要换名**：见第 9 节第 12 条 —— v2rayN 会按镜像名杀 `xray.exe`，同名的分流器会被误杀。
`register-split-task.ps1` 里已经用 `ag-split-core.exe`，**不要改回 `xray.exe`**。

---

## 13. 交付物落位

若拿到 `tools/` 目录，按下表放置后再执行：

| 文件 | 放到 |
|---|---|
| `tools/gen-config.py` | `D:\TOOL\v2rayN\ag-split\gen-config.py` |
| `tools/wire-split.ps1` | `D:\TOOL\v2rayN\ag-split\wire-split.ps1` |
| `tools/ensure-split.ps1` | `D:\TOOL\v2rayN\ag-split\ensure-split.ps1` |
| `tools/register-split-task.ps1` | `D:\TOOL\v2rayN\ag-split\register-split-task.ps1` |
| `tools/ensure-split.test.ps1` | `D:\TOOL\v2rayN\ag-split\ensure-split.test.ps1` |
| `tools/ag-split-live-acceptance.ps1` | `D:\TOOL\v2rayN\ag-split\ag-split-live-acceptance.ps1` |
| `tools/ag-health-check.ps1` | `D:\TOOL\v2rayN\ag-health-check.ps1` |
| `tools/ensure-patches.ps1` | `D:\TOOL\antigravity-ensure\ensure-patches.ps1` |
| `tools/register-task.ps1` | `D:\TOOL\antigravity-ensure\register-task.ps1` |
| `tools/workbuddy/workbuddy-risk-selfcheck.ps1` | `D:\TOOL\workbuddy-risk\`（只读脚本，位置不敏感） |
| `tools/workbuddy/workbuddy-risk-selfcheck.sh` | 同上（Git Bash 环境用 .sh 版） |

**顺序**：先放 `ag-split\` 下的文件 → 跑 `wire-split.ps1` 接前门 → 跑 `register-split-task.ps1` 注册分流器任务 →
放 `antigravity-ensure\` 下的文件 → 跑 `register-task.ps1` 注册总自愈任务 → 最后按第 8 节三层验收。

**投影校验**：包内附 `MANIFEST.sha256`，可用它核对 `tools\` 里的文件与源机一致、无漂移：

```powershell
cd D:\TOOL\v2rayN\交接包-Antigravity风控
Get-Content MANIFEST.sha256 | ForEach-Object {
  $p,$h = $_ -split '\s+',2
  $a = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
  if ($a -eq $h.ToLower()) { "OK   $p" } else { "DRIFT $p" }
}
```

**注意**：

- `tools/` 里**不含**任何节点凭据。分流器的 `config.json` 必须在本机用 `gen-config.py` **现场生成**（它从本机 `guiNDB.db` 读凭据），不要跨机器拷贝。
- `ensure-patches.ps1` 需要两份主副本：
  - **代理**：`D:\TOOL\antigravity-proxy\v2.4-x64\{version.dll, config.json}`（按第 2 步部署完成后把这两个文件复制过去即可）
  - **汉化工具**：`D:\TOOL\antigravity-cn\`（第 11 步解压出来的 `localize.js` 等）
  - 路径与默认不同就改 `ensure-patches.ps1` 顶部的 `$TOOL_CN` / `$TOOL_PROXY` 常量。
- 最后跑一次 `register-task.ps1` 注册计划任务，并用第 12 节的方式做一次「人为破坏 → 自愈」验证。

---

## 14. 第二领域：WorkBuddy 风控加固（方向与 Google 侧相反）

> 本机部署选择让 WorkBuddy 相关域名直连。代理设置、多账号记录和话题相关性
> 都不足以单独解释账号封禁；具体错误应结合时间、服务响应与当前官方说明分诊。

### 14.1 硬规则

1. **WorkBuddy 相关域名必须直连出口**，不得经任何代理出口 / 分流器转发：
   `workbuddy.ai` / `codebuddy.ai` / `lkeap.cloud.tencent.com` / `workbuddy.cn` / `codebuddy.cn`。
   （"直连出口"允许"进分流器但被 direct(freedom) 规则直连发出"——2026-10-09 起这是
   ag-split 部署下的第二道防线；分流器配置缺失该规则视为未闭环。）
2. **四层固化缺一不可**（都做完才算闭环）：
   - 系统代理例外表（`ProxyOverride`）含五个域（带 `*.` 前缀）
   - 用户级 + 机器级 `NO_PROXY` 含五个域（**裸域名**，后缀匹配；写 `*.` 通配反而永远匹配不上，见第 9 节第 9 条）
   - 代理客户端路由层有 direct 规则（防只认环境变量不认例外表的客户端）
   - 代理客户端**不再接管系统代理**（v2rayN `SysProxyType=2 Unchanged`，见第 5 节）——否则它每次启动重写例外表，前两层白做
3. **控制请求与重试**：
   - 会话主题与历史错误的相关性不能证明风控原因，不据此安排跨产品迁移
   - 避免同一账号并发多会话跑同类任务
   - 按连接器来源及是否实际启用分类认证失败，排查持续重试；避免把内置连接器的预期响应计为账号高危
4. **设备记录**：本机存在两个账号共享设备标识的历史记录，不能据此证明封禁关联；保留现有标识。
5. **限流（429）**：结合 Retry-After、reset 时刻与上游状态减少请求、等待窗口，避免反复重试。

### 14.2 自检与观察窗

```powershell
pwsh -File D:\TOOL\workbuddy-risk\workbuddy-risk-selfcheck.ps1     # 只读，报告写同目录 selfcheck-report-ps1.txt
# Git Bash 环境可用 .sh 版（两版报告文件分开命名，避免互相覆盖）；.test.sh 是脚本自身的离线验收夹具
```

- 覆盖：代理覆盖（例外表 / `NO_PROXY`）、真实 API 错误日志（**只统计 conversations 侧**，403/11140 是高风险错误信号，
  429 要区分官方配额与回显假阳性）、活动自动化、MCP 认证失败重试。
- **观察窗**：记录真实 403/11140 是否复发，连续无错误只能说明观察窗内未检出；2026-10-01 自检中的最新历史记录是 2026-09-28。

### 14.3 与第一领域的关系

- 两个领域只在「系统代理例外表」这一点交汇：本方案的 `ensure-split.ps1` 把 WorkBuddy 五域例外纳入
  `REQUIRED_EXCEPTIONS` 检查（缺失返回 1，人工确认后追加，不自动覆写）。
- 若新电脑**不做分流**（只有一条线路），WorkBuddy 部分仍要完整做——它不依赖分流器存在。
- 深度材料（六份报告原件）在源机 `C:\Users\sciman\WorkBuddy AI\`；本包 `tools/workbuddy/` 只内含分诊提示词
  （`workbuddy-triage-prompt.md`：429 与 403/11140 分诊、版本与域名后缀、红线清单）。
  `workbuddy-risk-triage` 技能只从项目 `overrides/custom/workbuddy-risk-triage/` 构建并由 `core-ops` 投影，
  不再保留交接包副本。