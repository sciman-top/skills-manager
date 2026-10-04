# 风控资产清单（AI Risk Control Assets）

> 本文件是 `docs/handover/ai-risk-control/` 的**语义清单**：声明每个资产的唯一真源、角色、
> 部署落位与校验方式。字节级校验以同目录 `MANIFEST.sha256` 为准，本文件只描述结构与关系。
> 范围：Antigravity × Gemini × WorkBuddy 的封号 / 限流 / 降智风险控制。

## 1. 真值层级

| 层 | 位置 | 角色 | 是否随构建投影 |
|---|---|---|---|
| **技能源** | `overrides/custom/antigravity-gemini-risk-triage/`<br>`overrides/custom/workbuddy-risk-triage/` | **唯一真源**（`SKILL.md` + `references/`） | 是 —— `构建生效` 物化进 `agent/`，再投影到各宿主 |
| **统一只读入口** | `src/Commands/AiRiskControl.ps1`（CLI：`.\skills.ps1 ai-risk-control`，支持 `--plan` / `--event` / `--checks` / `--out`） | 仓库资产清点、日常防范与事件分诊计划、可选的宿主只读自检；**不**切号、轮换凭据、重启进程或修改代理 | 是 —— 经 `build.ps1` 并入根 `skills.ps1` |
| **冷发现域** | `skills.json` → `skill_projection.discovery_catalog.domain_memberships.ai-risk-control` | 域注册（成员为上面两份技能） | 是 —— 生成 `agent/.skills-manager/catalog.json` |
| **宿主投影 profile** | `skills.json` → `projection_profiles.profiles.core-ops` + `hosts.{antigravity,workbuddy}` | 让两份技能真正落到所针对的两个客户端宿主 | 是 —— 建 junction 指向 `agent/` |
| **部署载荷** | `docs/handover/ai-risk-control/tools/` | 跨机复现用的运行脚本与分诊提示词（不含技能副本和凭据） | 否 |

判据：**改能力改 `overrides/custom/`；改跨机部署改 `tools/`；改统一入口行为改 `src/Commands/AiRiskControl.ps1`（改完必须 `build.ps1` 重建根 `skills.ps1`）。** 三者职责不同，不要反向同步。

### 1.1 宿主投递路径（两条并行）

| 路径 | 机制 | 覆盖宿主 |
|---|---|---|
| **热投影** | `core-ops` profile = `core-lean` 7 项 + 两份风控技能（共 9 项） | `antigravity`（`~/.gemini/config/skills`）、`workbuddy`（`~/.workbuddy-ai/skills`） |
| **冷发现** | `ai-risk-control` 域 → `agent/.skills-manager/catalog.json` | 其余宿主（codex/claude/zcode 保持 `core-lean` 7 项） |

设计约束：`core-lean` 是**冻结契约** —— `tests/Unit/SkillProjectionProfiles.Tests.ps1` 断言它恰好 7 项
（"keeps the checked-in default core-lean profile small for every host"）。因此风控技能**不进 `core-lean`**，
而走独立的 `core-ops`。判据：**`core-lean` 只放编码工作流技能。**

> ⚠️ 投影是 **fail-closed** 的：目标路径若已存在且不是指向同一 `agent/` 的 junction，
> 投影会抛 `Projection target conflict or drift` 而**不会**删除它。所以从「手放实体目录」切换到
> 「项目托管 junction」时，必须先把旧实体目录移出（移出即可，不必删除）。

## 2. 唯一真源与交接边界

`overrides/custom/workbuddy-risk-triage/` 是 WorkBuddy 风控技能的唯一真源。
交接包不再携带该技能的第二份副本，避免出现两份 `SKILL.md`、两套参考材料和人工同步流程。

目标机有本项目检出时，技能由 `overrides/custom/` 经 `skills.ps1 构建生效` 物化到
`agent/`，再由 `core-ops` 投影到 Antigravity 和 WorkBuddy。交接包中的 `tools/workbuddy/`
只保留自检脚本、受控验收脚本和分诊提示词；`MANIFEST.sha256` 只校验这些便携运行资产。

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
| `tools/workbuddy/workbuddy-risk-selfcheck.ps1` | 同上，PowerShell 双实现（**含** MCP 认证细分；与 `.sh` 的剩余差异是不做 WinINET 例外覆盖的注册表比对） | `D:\TOOL\workbuddy-risk\` |
| `tools/workbuddy/workbuddy-risk-selfcheck.test.sh` | 自检脚本自身的离线验收夹具 | `D:\TOOL\workbuddy-risk\` |
| `tools/workbuddy/workbuddy-triage-prompt.md` | 分诊提示词（429 / 403·11140 分诊与红线清单） | `D:\TOOL\workbuddy-risk\` |
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
- **载荷行为与字节（自动）**：`tests/Unit/AiRiskControlManifest.Tests.ps1`（逐字节核对 + 断言所有随包工具都已声明）
  与 `tests/Unit/AiRiskControlTools.Tests.ps1`（跑 `ensure-split.test.ps1` 受控验收；并用注入夹具验证 `.ps1` 自检的
  MCP 认证分类：自加连接器/内置插件/官方网关三分类与重试计数）。这两条路径已在 `resolve-gate-profile.ps1` 的
  `$sourceTests` 登记，载荷改动会落到 focused；**未登记的其他载荷文件仍回落 full**。
- **`.sh` 受控验收（手动）**：`bash tools/workbuddy/workbuddy-risk-selfcheck.test.sh`。它在本项目的沙箱里会被
  注册表分支终止，故**未接入门禁**，需人工运行。
- **真值边界**：本清单与 `MANIFEST.sha256` 最多证明 `repo_verified / filesystem_projected`；
  `host_loaded` 需要 fresh host probe，`live_accepted` 只能由用户真实长会话完成（见 `风控日检记录.md`）。

## 6. 红线边界（不在本资产集内）

以下**不是**本项目的功能，也不应被内置：反代 / OAuth 复用、多账号池 / 自动轮换、account switcher 切号、
伪造请求指纹、Token 提取（`workbuddy2api` 类）。它们是把「限流」升级为「封号」的加速器，
跨平台会同时触发 Google 与 WorkBuddy 两侧风控。判据见两份技能：
**改「我怎么连上」= 可做；改「我以谁的身份、用多少额度」= 红线。**
