# 风控资产清单（AI Risk Control Assets）

> 本文件是 `docs/handover/ai-risk-control/` 的**语义清单**：声明每个资产的唯一真源、角色、
> 部署落位与校验方式。字节级校验以同目录 `MANIFEST.sha256` 为准，本文件只描述结构与关系。
> 范围：Antigravity × Gemini × WorkBuddy 的封号 / 限流 / 降智风险控制。

## 1. 真值层级

| 层 | 位置 | 角色 | 是否随构建投影 |
|---|---|---|---|
| **技能源** | `overrides/custom/antigravity-gemini-risk-triage/`<br>`overrides/custom/workbuddy-risk-triage/` | **唯一真源**（`SKILL.md` + `references/`） | 是 —— `构建生效` 物化进 `agent/`，再投影到各宿主 |
| **冷发现域** | `skills.json` → `skill_projection.discovery_catalog.domain_memberships.ai-risk-control` | 域注册（成员为上面两份技能） | 是 —— 生成 `agent/.skills-manager/catalog.json` |
| **部署载荷** | `docs/handover/ai-risk-control/tools/` | 跨机复现用的**便携副本**（脚本，不含凭据） | 否 |

判据：**改能力改 `overrides/custom/`；改跨机部署改 `tools/`。** 两者职责不同，不要反向同步。

## 2. 已知重复与同步规则

`tools/workbuddy/skill/workbuddy-risk-triage/` 与 `overrides/custom/workbuddy-risk-triage/`
**是同一份技能的两份拷贝**，服务不同目的：

- `overrides/custom/` 是**构建源**：已去掉 `agent_created` 未知字段（元数据校验会判 error），
  并把写死的机器绝对路径改成可移植形式。
- `tools/...` 是**交接包快照**：供新机器离线落盘，保持自包含。

**同步规则**：技能内容变更时改 `overrides/custom/`，再把两份对齐并刷新 `MANIFEST.sha256`。

当前**有意保留**的差异（2 个文件）：

| 文件 | 差异 |
|---|---|
| `SKILL.md` | 去 `agent_created: true`；自检脚本路径 `C:/Users/sciman/...` → `<风控工具目录>/...` |
| `references/selfcheck-internals.md` | 同上路径可移植化 |

## 3. 工具资产

| 资产 | 角色 | 部署落位 |
|---|---|---|
| `tools/gen-config.py` | 分流器配置生成器（从本机 v2rayN 数据库读节点凭据，**现场生成，不跨机拷贝**） | `D:\TOOL\v2rayN\ag-split\` |
| `tools/wire-split.ps1` | 前门接线（系统代理 + 环境变量 + 开机自启） | `D:\TOOL\v2rayN\ag-split\` |
| `tools/ensure-split.ps1` | **核心**：分流器幂等自愈，含「代理指向死端口」安全阀与 WorkBuddy 五域例外表守护 | `D:\TOOL\v2rayN\ag-split\` |
| `tools/ensure-split.test.ps1` | 受控验收（离线夹具，23 断言） | `D:\TOOL\v2rayN\ag-split\` |
| `tools/ag-split-live-acceptance.ps1` | 受控实战验收（真故障注入，11 断言，可自动收尾） | `D:\TOOL\v2rayN\ag-split\` |
| `tools/register-split-task.ps1` | 注册分流器任务（`AgSplitEgress` + `AgSplitWatchdog`） | `D:\TOOL\v2rayN\ag-split\` |
| `tools/ag-health-check.ps1` | 只读自检（23 项，有 FAIL 返回 1） | `D:\TOOL\v2rayN\` |
| `tools/ag-egress-probe.ps1` | 按需测量 Google 节点出口（临时实例，自动清理） | `D:\TOOL\v2rayN\` |
| `tools/ensure-patches.ps1` | **核心**：代理 + 汉化 + 分流器一体化幂等自愈 | `D:\TOOL\antigravity-ensure\` |
| `tools/register-task.ps1` | 注册/更新「每 30 分钟 + 登录」自愈计划任务 | `D:\TOOL\antigravity-ensure\` |
| `tools/workbuddy/workbuddy-risk-selfcheck.sh` | WorkBuddy 只读风控自检（Git Bash 版，含 MCP 认证细分） | `D:\TOOL\workbuddy-risk\` |
| `tools/workbuddy/workbuddy-risk-selfcheck.ps1` | 同上，PowerShell 简化版（不含 MCP 认证细分） | `D:\TOOL\workbuddy-risk\` |
| `tools/workbuddy/workbuddy-risk-selfcheck.test.sh` | 自检脚本自身的离线验收夹具 | `D:\TOOL\workbuddy-risk\` |
| `tools/workbuddy/workbuddy-triage-prompt.md` | 分诊提示词（429 / 403·11140 分诊与红线清单） | `D:\TOOL\workbuddy-risk\` |
| `tools/workbuddy/skill/workbuddy-risk-triage/` | 技能便携副本（装入宿主技能目录即用） | 见 §2 |

部署顺序与三层验收见 `PROMPT.md` 第 8、13 节；日常只需跑受控验收 ①、全量自检 ③、WorkBuddy 自检 ④。

## 4. 不纳入仓库的第三方件（**刻意**）

按项目决定，**只内置脚本，不 vendored 二进制**。以下件留在本机工具目录，按 sha256 与版本对齐规则引用：

| 件 | 位置 | 对齐规则 |
|---|---|---|
| `antigravity-proxy`（`version.dll` + `config.json`） | `D:\TOOL\antigravity-proxy\v2.4-x64\` | 与 `Antigravity.exe` **同一次构建**；x64 对 x64；记录 `version.dll` SHA-256 用于恢复核对 |
| 汉化工具（`localize.js` 等） | `D:\TOOL\antigravity-cn\` | Release 版本与 Antigravity 版本对齐；**只用 `localize.js --now`**，绝不覆盖预打包 `app.asar` |
| 分流器内核 | `D:\TOOL\v2rayN\ag-split\ag-split-core.exe` | **必须换名**（不能叫 `xray.exe`，会被 v2rayN 按镜像名清理） |

未纳入原因：上游许可未确认允许再分发、体积、以及与宿主版本强绑定（vendored 后会迅速过期）。

## 5. 校验

```powershell
# 字节级：核对 tools/ 与源机一致、无漂移
cd docs\handover\ai-risk-control
Get-Content MANIFEST.sha256 | ForEach-Object {
  $p,$h = $_ -split '\s+',2
  $a = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
  if ($a -eq $h.ToLower()) { "OK   $p" } else { "DRIFT $p" }
}
```

- **技能源无漂移**：`pwsh -File build.ps1 -Check`（核对生成物）+ 质量门禁。
- **物化无漂移**：`skills.ps1 构建生效` 后核对 `agent/<skill>/SKILL.md` 与源一致。
- **真值边界**：本清单与 `MANIFEST.sha256` 最多证明 `repo_verified / filesystem_projected`；
  `host_loaded` 需要 fresh host probe，`live_accepted` 只能由用户真实长会话完成（见 `风控日检记录.md`）。

## 6. 红线边界（不在本资产集内）

以下**不是**本项目的功能，也不应被内置：反代 / OAuth 复用、多账号池 / 自动轮换、account switcher 切号、
伪造请求指纹、Token 提取（`workbuddy2api` 类）。它们是把「限流」升级为「封号」的加速器，
跨平台会同时触发 Google 与 WorkBuddy 两侧风控。判据见两份技能：
**改「我怎么连上」= 可做；改「我以谁的身份、用多少额度」= 红线。**
