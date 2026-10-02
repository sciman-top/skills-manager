# 自检脚本内部机制与本机环境限制

> 本文件是 `workbuddy-risk-triage` 的参考材料，按需读取。

## 脚本位置与用法

```
bash "<风控工具目录>/workbuddy-risk-selfcheck.sh"      # 自检（只读）
bash "<风控工具目录>/workbuddy-risk-selfcheck.test.sh" # 受控验收
```

> `<风控工具目录>` = 本仓 `docs/handover/ai-risk-control/tools/workbuddy/`；部署落位与资产清单见同目录 `ASSETS.md`。

覆盖 9 项：hosts 劫持、自定义模型/反代进程、客户端第三方指向、多账号共用设备指纹、
代理例外规则、**代理例外覆盖缺口（WinINET vs 环境变量）**、重启频率、
**实际服务错误日志（403/11140/429）**、**活动自动化与 MCP 认证重试**。
**有高危项返回 1。** 只读，不修改任何文件。

同目录另有 `workbuddy-risk-selfcheck.ps1` —— 那是**刻意简化的便携版**，
**不含 MCP 认证检测**（因为它没有精确分类逻辑），并在输出里明确指向 `.sh` 版本。
本机 PowerShell 工具不可用，实际一律跑 `.sh`。

## 第 9 项「MCP 认证失败」的四重陷阱

都已修掉，理解为什么才能不误判：

1. **不能数行数**：会话日志记录了你跑过的测试夹具，每跑一次受控验收计数就 +18，看起来像"持续增长"，**完全是假的**。→ 改为**按连接器 id 去重后列名单**。

2. **不能扫全部日志**：真实 MCP 状态只在客户端主线程日志 `workbuddyMainThread__*.log` 里；项目会话日志（`<项目名>__<hash>.log`）含你自己执行过的命令，会把**测试夹具的假 id 当成真实连接器**。→ 扫描面收到主线程日志（找不到时退回全量）。
   实测：夹具 `custom-mcp:acme-crm` 就出现在 `logs/sandbox/*` 与测试脚本回显里。

3. **内置插件 ≠ 自加连接器**：`plugins/cache/workbuddy-builtin/` 下随客户端分发的插件（`mcp-ardot-mcp-app`、`mcp-miora`）在未配置令牌时返回 `HTTP 422 {"code":10101,"msg":"access token not found"}` —— 这是**预期行为，不是风控信号**。把它判 [高危] 会造成"永久狼来了"，淹没真实高危。→ 按内置插件目录归类降为 [注意]。
   ⚠️ id → 目录名**不是固定变换**（`ardot`→`mcp-ardot-mcp-app`，`miora`→`mcp-miora`），用子串匹配。

3b. **官方网关连接器同样不是自加连接器**（与 3 同类，必须一起降级）：URL 落在自家域名下，如
   `https://www.workbuddy.ai/console/agent-gateway/{netdrive,genie-baas}/mcp`，未授权返回
   `{"error":"access_denied","error_description":"not_authorized"}` —— 只是没配令牌，**属预期行为**。
   实测踩过：`netdrive` / `genie-baas` 被误判成「自加连接器认证失败」长期占据 [高危]。
   **判别方法：按 URL 判，不要按 id 猜。** 两种日志形态都要抓：
   ① `[MCP-Connect] begin configId=<id> … url=<url>`（同时带 id 与 url）；
   ② OAuth 探测行的 `"target":"…/agent-gateway/<name>/mcp"`（**只带地址，用地址里的 `<name>` 反推 `custom-mcp:<name>`**）。
   ⚠️ **探测面不能只取"近 3 天"** —— 连接器→URL 的映射长期不变，而这些行往往只出现在**更早的日志或 `daemon.log`** 里。
   实测：`netdrive` 的 MCP-Connect 行只在 2026-09-24/25 的日志里，`genie-baas` 的 target 行只在 `daemon.log` 里 ——
   只看近 3 天会**静默失效**（表现为「改了逻辑却没生效」）。→ 用**全量主线程日志 + daemon 日志**建映射。
   受控验收已覆盖 4 个用例：MCP-Connect 形态、target 形态、**非官方 URL 仍判高危**（防过度降级）、URL 仅在旧 daemon 日志。

4. **重试要按 id 计数，不能全局计**：全局口径会把**内置插件的重试算到自加连接器头上**。实测：`ardot`(内置) 有 628 次重试，而 `genie-baas`/`netdrive` 重试为 **0** —— 全局口径却把它们报成"含 335 次重试"的高危。→ 只统计**自加连接器自身**的重试。

> 另：连接器状态文件里若是 `connectors: {}` / `enabled: []`，说明它们**并未启用**，**无实际动作可做**，不要照着修。

## 第 8 项「实际服务错误日志」的自污染陷阱

**扫描面必须限定在 API 响应文件 `*/sdk/conversations/*.log`，不能扫全量日志。**

会话日志（`<项目名>__<hex>.log`、`workbuddyMainThread__<hex>.log`）记录的是
**你自己执行过的命令与写过的文档**。只要那些文本里出现 `429 Too Many Requests` / `403 request illegal`，
就会被当成真实错误命中。

> 实测（2026-10-01）：写了一份含 `429 Too Many Requests` 的审查报告后，
> 429 计数从 **14 直接涨到 27** —— 增量全是自污染，没有一条是真实限流。

**回退面也要排除会话日志**：当 `sdk/conversations/` 不存在而退回全量时，
必须用 `grep -v -E '__[0-9a-f]{8,}\.log$'` 把会话日志剔掉，否则回退路径会重新引入污染。

**判据**：如果 403/429 的计数在你**写文档/跑命令之后**突然上涨，先怀疑自污染，不要怀疑账号。
核对方法 —— 看命中行的**行首是否是 ISO 时间戳**：真实 API 响应行以 `2026-…Z` 开头；
你自己写进日志的文本没有。

## 本机环境限制（踩过的坑）

- `reg.exe` / `wmic.exe` 被沙箱 Program Blacklist 拦截 → 读注册表改用 Python `winreg`
- **PowerShell 工具在本机不可用**（无 stdout、无副作用）；Bash 调 PowerShell 被明确拒绝 → 用 Git Bash 跑 `.sh` 版本
- 端口 `6677` 属于 `sandbox-cli.exe`（沙箱自身），**不是用户代理** —— 别据此判断用户走了代理
- 长命令可能被环境 SIGTERM 中断，**重跑确认再判脚本有问题**
- **`xargs` 必须带 `-d '\n'`**：Windows 下 `mktemp -d` 返回 `C:\Users\...\Temp/tmp.X` 这种混合形式，
  `xargs` 默认把反斜杠当转义符吃掉 → 文件名被破坏 → 文件找不到，表现为「明明有日志却报未命中」。
- **两个「shell」的 `/tmp` 不是同一个目录**：Git Bash 的 `/tmp` = `%TEMP%`，而托管/系统 Python 把 `/tmp` 解析成「当前盘符 `:\tmp`」。跨 Bash/Python 传临时文件时不要用 `/tmp`。
- 沙箱下每个外部命令约 100ms，完整受控验收（35 用例）约 15 分钟，**是环境开销不是脚本缺陷**。
- Git Bash 里 `rm` 是被注入的 safe-delete 包装函数，**拒绝带盘符前缀的路径**（`SAFE_DELETE_INVALID_PATH`）→ 给 Git Bash 传路径用 MSYS 形式 `/c/...`。

## 写脚本时的两个纪律

- **不要用 `/tmp` 在 Bash 与 Python 之间传文件**（见上）。
- **不要在 `logs/` 里写自己的临时夹具再 grep 它** —— 会污染后续所有取证（自污染陷阱）。
