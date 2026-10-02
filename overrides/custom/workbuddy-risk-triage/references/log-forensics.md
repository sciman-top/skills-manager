# 日志取证：判断「是否真的发生过」

> 本文件是 `workbuddy-risk-triage` 的参考材料，按需读取。

## 真实错误体在哪、怎么读（**最高价值**）

之前一直查 `~/.workbuddy/logs/` 只能看到会话标题，**看不到真实 API 响应**。真实错误体在这里：

```
~/.workbuddy-ai/logs/<日期>/sdk/conversations/<会话-UUID>.log
```

形如（已脱敏）：

```
... runtime.applyStopReason {"instanceId":"ci-1","event":"TURN_ERROR",
 "stopReason":"refusal","requestState":"error",
 "errorMessageMetaPreview":"{\"code\":-32603,\"message\":\"Internal error\",
 \"data\":{\"statusCode\":403,\"displayMsg\":{\"zh\":\"内容未通过安全审核，请调整后重试。\"},
 \"details\":\"403 request illegal (<32位hex>/<会话UUID>)\",
 \"code\":11140,\"category\":\"internal\"}}"}
```

**三个决定性推论：**

1. **`"category":"internal"`** —— 不是内容审核类目。显示的「内容未通过安全审核」是**通用包装文案**，不能照字面理解成内容违规。
2. **`details` 里的 UUID = 该会话自己的 UUID**（逐个会话比对确认，每个会话各自的 hex 前缀也不同）。所以它**不是用户级令牌**；「同一 UUID 跨多日出现」通常只是用户把报错原文粘贴进了新会话标题。
3. **连只发「你好」「用户简单打招呼」的会话也是同一条 11140/403/category=internal** → 内容变量排除 → **只能是账号级风控**。

> 判据一句话：**看 `category`，不看 `displayMsg`。** trivial 输入同样报错 + `category:internal` = 账号级。

```
grep -riE 'bizCode=11140|statusCode.?":?403|refusal classified' \
  ~/.workbuddy-ai/logs/*/sdk/conversations/*.log
```

⚠️ **不要在 `~/.workbuddy-ai/logs/` 全目录搜**：会话日志记录用户/AI 自己执行过的命令，
你 grep 过这些字符串，就会被自己命中（实测：全量搜 112 条 → 真实仅 14 条）。
`*/sdk/conversations/*` 是 API 响应，`*/sandbox/*` 是工具输出回显，必须分开。

## 假阳性陷阱（必踩）

直接 `grep -E '429|403'` 会命中大量无关文本：

- `rss=429.5MB`、`heap=187.5/242.1MB`（内存日志）
- 时间戳尾号 `.429`、字节计数 `received=138025`
- **会话标题里被用户粘贴的报错原文**（最容易骗人）

先过滤再计数：

```
grep -r -h -o -E '11140' ~/.workbuddy/logs | wc -l                        # 精确 token
grep -r -h -o -E '"(code|status)": *(403|429|11140)' ~/.workbuddy/logs    # 真实响应字段
grep -r -h -E '11140|request illegal' ~/.workbuddy/logs | cut -c1-200     # 看是否 title= 里的文本
```

命中行若形如 `[CREATE_ENTER] sid=… title=…11140…`，那是**会话标题**，不是错误。

## 403 里的 UUID → 会话归属（可定位到具体任务，实战验证有效）

`403 request illegal (32位hex/UUID)` 中，**UUID 是会话 ID**。两步定位：

```
# 1. 在客户端日志中查它，拿创建时间 / title= / cwd=
grep -r -h '<UUID>' ~/.workbuddy/logs | head
# 2. 确认归属哪个账号（命中哪个账号的快照，报错就发生在该账号上下文）
for d in ~/.workbuddy-ai/*/; do echo "$(basename $d): $(grep -c '<UUID>' "$d/sidebar-list-snapshot.json")"; done
```

**同时读该账号 `sidebar-list-snapshot.json` 里的 `"title"` 列表 —— 会话主题分布本身就是触发画像的直接证据。**
实战案例：被拦截账号的会话高度集中在「fq 网关客户端 key / CPA 网关 / CLIProxyAPI / SSE 超时 429 / Direct OAuth」，即反代·网关·密钥一族。

一次性列出 `state` 与 `title`（比 grep 更直观）：

```
python -c "import json;d=json.load(open(r'<账号UUID>/sidebar-list-snapshot.json',encoding='utf-8'));[print(i.get('state'),'|',i.get('title')) for i in d.get('items',[])]"
```

> ⚠️ **最大的推理陷阱（真实踩过，务必避开）**：**不要把「同一个 UUID 跨多日出现」当作账号级 flag 的证据。**
>
> UUID 是**会话 ID**，不是账号令牌。它在后续日期再次出现在日志里，绝大多数是因为**用户把报错原文粘贴进了新会话标题**——命中行形如
> `[CREATE_ENTER] sid=<另一个id> title=…<粘贴的报错原文>…`。
> 逐日分类命中行的日志类型（`CREATE_ENTER`/`EB_SYNC_ADDED` = 标题文本；`EB_CONV_CREATED_EVENT`+`CREATE_OK` = 真实创建）即可区分。
>
> **正确的账号级判据**（二选一，都硬）：
> 1. 快照里**只发了「你好」这类极简打招呼的会话也是 `state=error`** → 内容审核变量被排除，只能是账号级；
> 2. 同机换测试号立即恢复。
>
> 快照 `items[].state` 字段（`error` / `idle`）是现成的判据，直接列出来看。

## 账号切换时间线

```
for d in ~/.workbuddy-ai/*/; do echo "$(basename "$d") $(stat -c %y "$d" | cut -c1-19)"; done
```

配合 `device-id` 判断是否同设备多账号；结合 `last-launch.json` 拿客户端版本。

## 两个日志根必须都查，只查一个会漏

| 根 | 内容 | 用途 |
|---|---|---|
| `~/.workbuddy/logs/` | 客户端网络日志（仅 419 条域名记录） | 域名频次直方图 |
| `~/.workbuddy-ai/logs/` | **34061 条**域名记录 + `sdk/conversations/` + 主线程日志 | 真实错误体、MCP 状态、`.cn` 判定 |

- **`.cn` 域名只出现在 `~/.workbuddy-ai/logs/` 一侧**（实测 `~/.workbuddy/logs` 里一条都没有）→ 只扫一个根会漏检。
  ⚠️ **`.cn` 出现 ≠ 国内版**：国际版客户端同样会访问 `www.workbuddy.cn`(102次) / `www.codebuddy.cn`(53次) / `tencent.sso.codebuddy.cn` / `static.workbuddy.cn` / `download.codebuddy.cn`(461次)。
  所以应按「**实际访问到**」补例外，而不是按「版本」补 —— 这些域名不在例外表里就会走代理出口。
- 账号计数要区分「0」与「1」：**`ACN=0` 只说明没找到账号目录，不等于单账号**，不能据此宣称"无风险"，应报"无法判定"。
  （注：5.6.2 **仍会**写 UUID 账号目录 —— `sidebar-list-snapshot.json` 持续更新中，"新版不再落盘"的说法不成立。）

## 一个重要的复查结论

报错期若反复重试/重启，本地「今日启动次数」会明显偏高（实战：报错日 6 次 vs 恢复后 1 次）。
这个数字本身就是行为特征的自证，也是优化是否生效的量化指标。

## 文件 mtime ≠ 事件时间

自检脚本按**文件 mtime** 划「近 3 天」窗口，而窗口内事件的真实时间以行首 ISO 时间戳为准。
两者通常接近（文件 mtime ≈ 最后写入），但**跨日边界时会有几小时偏差**。
若一条 [高危] 的实际事件已超出窗口，它会在下一个自然日自动降级为「历史记录未复发」——
**看到高危先核对行首时间戳，别急着改配置。**
