# 网络出口与代理：官方错误码页、双层例外、进程级归因

> 本文件是 `workbuddy-risk-triage` 的参考材料，按需读取。

## 官方错误码页

**官方错误码清单在专门的页，不在 FAQ**：
`https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Error-Code`
（FAQ 里一个数字错误码都没有）。

| 码 | 官方判断 | 官方建议 |
|---|---|---|
| 6003 / 6004 | 请求频率受限，**专业版也会出现** | 切换模型重试 |
| 3002 / 3003 / 3007 | 多与网络环境有关 | 确认公司/家庭网络；**参照「网络代理」关闭网络代理** |
| 1001 / 11133 / 11134 / 14003 | 多与模型侧状态有关 | 新开会话或切换模型 |
| 11115 | 输入内容过长 | 精简输入 / 换大上下文模型 |

**`11140` 与 `403 request illegal` 均不在官方清单内** —— 官方对账号级风控不公开细则，只能靠本流程分诊。
同页说明：WorkBuddy ≥5.3.0 内置网络代理切换，不了解就用「跟随系统」。

**429 与 6003/6004 同族** —— 都是频率受限，切模型是官方认可的分流手段。

## 代理必须查两层，只查一层会漏（实战踩过）

```
# 系统层（WinINET）—— reg.exe 被拦时用 Python winreg 读
#   HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
#   ProxyEnable / ProxyServer / ProxyOverride / AutoConfigURL
# 环境变量层
#   HKCU\Environment -> HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY
```

- 两层的「直连例外」**语义不同**：`ProxyOverride` 用通配符 `*.workbuddy.ai`；`NO_PROXY` 用**裸域名** `workbuddy.ai`。
- ⚠️ **不要把 `NO_PROXY` 改成 `*.` 通配符形式——会帮倒忙。** Python `urllib`、Node `proxy-from-env`、Go `httpproxy` 走的是「主机名以 `.域名` 结尾」的后缀匹配，裸域名本就覆盖子域；写成 `*.workbuddy.ai` 后它们去找字面量 `.*.workbuddy.ai`，**永远匹配不上，等于取消了例外**。裸域名写法是对的。
- 因此「系统代理有例外」≠「环境变量代理也有例外」。**认 `HTTP_PROXY` 但不认 `NO_PROXY` 的组件会把流量送去代理出口**。
- 加固方向：**不设全局 `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`**（但注意 git/npm/pip 依赖它们，删前先确认），或保证两层例外都覆盖全部必需域名；内置代理设「跟随系统」。
- **两层必须都覆盖同一份域名清单**。实战缺口：`lkeap.cloud.tencent.com` 在 `NO_PROXY` 里、却不在 `ProxyOverride` 里 → Chromium 侧走代理、Node 侧走直连，同一产品流量两个出口。修法是**双写**（注册表 + v2rayN 的 `SystemProxyItem.SystemProxyExceptions`，否则 v2rayN 重启会把注册表改回去）。
- 验证出口：`curl -s --noproxy '*' https://myip.ipip.net`（直连）对比 `curl -s -x http://127.0.0.1:<port> https://ipinfo.io/json`（代理）。

### 本机当前已验证一致的例外清单（2026-10-01）

| 层 | 位置 | 值 |
|---|---|---|
| WinINET | 注册表 `ProxyOverride` | `<local>;localhost;127.*;10.*;…;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com;*.workbuddy.cn;*.codebuddy.cn` |
| v2rayN | `guiConfigs/guiNConfig.json` → `SystemProxyExceptions` | 同上（**双写一致**） |
| 环境变量 | `HKCU\Environment` → `NO_PROXY` | `fq.sciman.top,workbuddy.ai,codebuddy.ai,lkeap.cloud.tencent.com,workbuddy.cn,codebuddy.cn`（**裸域名，正确**） |

## 进程级出口归因（判断「谁在走代理」的关键手段）

只看 netstat 分不清哪条连接属于哪个组件。把 PID 与进程角色对上，结论会反转：

```
netstat -ano | awk '$NF=="<PID>"'      # 先看该 PID 连的是 127.0.0.1:<代理端口> 还是远端 IP
```

再用 Python 读各进程命令行（`NtQueryInformationProcess` 取 PEB → `ReadProcessMemory` 读 `RTL_USER_PROCESS_PARAMETERS` 的 CommandLine），拿到 `--type=`：

| `--type=` | 角色 | 出口由谁决定 |
|---|---|---|
| `utility --utility-sub-type=network.mojom.NetworkService` | Chromium 网络服务 | **系统代理（WinINET `ProxyOverride`）** |
| `renderer` / `gpu-process` | 渲染 / GPU | 不发网络请求 |
| 无 `--type=` 且子进程含 `sandbox-cli.exe` | Node 侧宿主 | **环境变量代理（`HTTP_PROXY`/`NO_PROXY`）** |

**判定要点**：若网络服务的命令行里**没有** `--proxy-server` / `--proxy-bypass-list`，它就完全受 `ProxyOverride` 约束 —— 于是「网络服务在走代理」只说明它连的是**例外表之外的域名**，未必是自家业务流量。**别看到"有连接走代理"就断定业务流量被代理了**（这是真实踩过的误判，警报下重过一次）。

正确顺序：
① 先确认客户端实际使用的域名清单（查配置里的 endpoint 与日志域名频次）
→ ② 核对这些域名是否都在例外表内
→ ③ 再用 netstat + 进程角色交叉验证。
