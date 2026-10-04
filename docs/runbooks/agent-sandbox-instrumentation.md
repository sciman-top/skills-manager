# Agent 沙箱仪表化：指纹、实测影响与操作规则

**定位**：runbook。记录 agent 会话中进程被注入的沙箱仪表化（shim / 代理 / 守卫）的**可检测指纹**、**实测影响**与**必须遵守的操作规则**。目的是防止"把沙箱开销误读成代码成本"这一类问题反复出现。
**核实日期**：2026-10-04（本机 Windows / WorkBuddy 桌面版）。

---

## 1. 问题现象

同一份代码、同一份测试，**在 agent 工具里跑和在普通终端/CI 里跑，耗时可能差一个数量级**。历史实例：

- 本仓 full 门禁顺序运行记录为 **19303s（≈5.4h）**。
- 分片全量：agent 工具启动的分片 **1319.6s**（361 用例）vs 另一路启动的**同分片 124.9s**（同样 361 用例）——**10.6 倍**。
- 若照字面采信，会得出"门禁太慢、需要砍测试"的错误结论。

---

## 2. 可检测指纹

### 2.1 环境变量（命中任一项即说明进程被仪表化）

| 变量 | 含义 |
| --- | --- |
| `CODEBUDDY_SAFE_DELETE_ENABLED=1` | 安全删除 shim 已启用 |
| `CODEBUDDY_SAFE_DELETE_SANDBOX=1` | 运行在沙箱删除通道 |
| `CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD=50` | 单次删除超过该文件数即要求**宿主弹窗确认** |
| `CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR` | 守卫状态目录 |
| `CODEBUDDY_SAFE_DELETE_BROKER_DELETE` | 删除 broker 脚本（**每次删除的 IPC 目标**） |
| `CODEBUDDY_SAFE_DELETE_BIN_DIR` | shim 的 `safe-bin`（Git Bash 的 `rm` 包装在此） |
| `CODEBUDDY_SAFE_DELETE_REPORT_PATH` | 删除审计 jsonl |
| `NODE_OPTIONS=--require=<...>/node-language-shim.cjs` | Node 进程经此注入 |
| `PYTHONPATH=<...>/cli/vendor/shim` | Python 进程经此注入（`sitecustomize`） |
| `HTTP_PROXY` / `https_proxy` = `http://127.0.0.1:<port>` | **所有 HTTP 走本机沙箱代理** |
| `SANDBOX_CENTER_IPC_ADDRESS` / `SANDBOX_CENTER_UID` | 沙箱控制面 IPC |

> ⚠️ 同一环境里还包含**长期凭据**（网关口令、GitHub token 等）。任何被 agent 启动的子进程都能读到它们 ⇒ **不要把完整 `env` 输出粘进聊天/日志/提交**；若已外泄，轮换凭据。

### 2.2 PowerShell 侧

```powershell
(Get-Command Remove-Item).CommandType   # 被仪表化时是 Function（正常是 Cmdlet）
```

---

## 3. 实测：慢在哪（不是"所有 I/O"）

本机 2026-10-04 实测：

| 操作 | 结果 |
| --- | --- |
| 纯创建 40 个小文件 × 5 轮 | **71–109 ms/轮**（≈400–560 files/s）⇒ **通用文件 I/O 正常** |
| 创建 40 文件 + `Remove-Item -Recurse -Force` | **第一轮即无输出，整个调用 exit 1** ⇒ 删除是被拦路径 |

**结论**：开销集中在**删除**（shim 函数 → broker IPC → 状态记账；超阈值还要宿主确认），**不在创建/读取**。所以**删除密集型**负载（反复建/删 git fixture 的测试、`TemporaryDirectory` 清理）受害最重；纯计算/纯创建负载几乎不受影响。

**尚未定论**：`HTTP_PROXY` 对**联网测试**的额外延迟未实测。含网络调用的测试应单独怀疑。

---

## 4. 操作规则（防重现）

1. **agent 内测得的耗时不得当作成本结论。**
   任何"门禁要 5 小时 / 测试太慢"的判断，必须先在**沙箱外**（用户终端或 CI）复核。本仓 CI 已有 45 分钟预算，是真实全量的锚点。
2. **重活（full 门禁、性能基准、大批量删除）交给沙箱外。**
   agent 内只跑 focused、受控抽样与功能验证。
3. **报告耗时必须带条件。**
   写明"经 agent 工具启动 / 命中 shim 指纹"，否则读者会默认它是代码成本。
4. **测试与夹具避免大批量递归删除。**
   删除次数本身是成本；批量 `Remove-Item -Recurse` 还会触发守卫（阈值 50）并要求**宿主弹窗确认**——而 agent **不能自我批准**，结果是进程组被杀。
   ⚠️ **不得**以"拆小批删除 / 删失败就静默放弃"来规避守卫——那属于绕过安全控制。
5. **不要从 agent 内关闭或绕过 shim / 代理。** 需要干净环境时，换执行位置，而不是改安全配置。

---

## 5. 上报上游所需的复现材料

若要让**产品侧**彻底修复（而不是每次靠人识别），带上以下最小证据：

1. 指纹：`env` 中 `CODEBUDDY_SAFE_DELETE_*`、`NODE_OPTIONS`、`PYTHONPATH`、`HTTP_PROXY` 的**存在性**（值可脱敏）。
2. `(Get-Command Remove-Item).CommandType` 的输出。
3. 对比数据：**纯创建 N 文件耗时** vs **创建+递归删除同批耗时**（本次：创建正常，删除被杀）。
4. 期望的修复方向：删除 shim 应**按需介入**（仅在实际发生批量删除时走 broker），而不是每次删除都 IPC；或提供**文档化的干净测量模式**。

---

## 6. 边界

- 本文是**本机 2026-10-04 的实测**，指纹与阈值随客户端版本可能变化；复用前重新探测。
- 未测：`HTTP_PROXY` 对联网测试的量化影响；其他语言运行时（Go/Java）的注入方式。
- 本文不构成对任何宿主配置、shim 或代理的修改授权。
