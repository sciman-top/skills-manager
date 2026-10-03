# 交接包 — Antigravity × Gemini × WorkBuddy 风控加固

在另一台 Windows 电脑上复现同一套加固方案。

> 版本：2026-10-01（运行身份与出口证据修订）　·　受控验收 23/0；实战验收 11/0（看门狗恢复 115.2 秒）。
> 技能源唯一落位：`D:\CODE\skills-manager\overrides\custom\`；本目录只保留交接说明、运行脚本和分诊提示词，按 SHA256 校验同步。

## 包里有什么

```
交接包-Antigravity风控\
├─ PROMPT.md            提示词 —— 全文复制粘贴到新电脑的对话里
│                       （§0–13 Antigravity/Gemini 分流加固；§14 WorkBuddy 风控）
├─ README-交接.md       本文件
├─ MANIFEST.sha256      全部内容的 sha256 清单（投影校验用）
└─ tools\
   ├─ gen-config.py                   分流器配置生成器（从本机 v2rayN 数据库读节点凭据）
   ├─ wire-split.ps1                  前门接线脚本（系统代理 + 环境变量 + 开机自启）
   ├─ register-split-task.ps1         **注册分流器任务**：AgSplitEgress + AgSplitWatchdog
   ├─ ensure-split.ps1                **核心**：分流器幂等自愈（含「代理指向死端口」安全阀
   │                                  与 WorkBuddy 五域例外表守护）
   ├─ ensure-split.test.ps1           **受控验收**：夹具注入，23 个断言，离线、不碰真实状态
   ├─ ag-split-live-acceptance.ps1    **受控实战验收**：真故障注入，11 个断言，可自动收尾
   ├─ ag-health-check.ps1             只读自检脚本（23 项，有 FAIL 返回 1）
   ├─ ag-egress-probe.ps1             按需测量 Google 节点出口（临时实例，自动清理）
   ├─ ensure-patches.ps1              **核心**：代理 + 汉化 + 分流器 一体化幂等自愈
   ├─ register-task.ps1               注册/更新「每 30 分钟 + 登录」的自愈计划任务
   └─ workbuddy\
      ├─ workbuddy-risk-selfcheck.ps1     WorkBuddy 只读风控自检（PowerShell 版）
      ├─ workbuddy-risk-selfcheck.sh      同一套检查逻辑的 Git Bash 版
      ├─ workbuddy-risk-selfcheck.test.sh 脚本自身的离线验收夹具
      ├─ workbuddy-triage-prompt.md       分诊提示词（429/403/11140 分诊流程与红线清单）
      └─ （技能不在交接包中重复携带；由项目唯一真源构建投影）
```

## 与 skills-manager 主链的关系

本目录是跨机器复现用的**交接包**，不是本项目运行时技能的第二份真源。
在 `D:\CODE\skills-manager` 内，相关能力沿现有技能管理主链进入宿主：

```text
overrides/custom/antigravity-gemini-risk-triage/
overrides/custom/workbuddy-risk-triage/
        │  唯一技能源
        ▼
skills.json
  skill_projection.projection_profiles.profiles.core-ops
  hosts.antigravity.default_profile = core-ops
  hosts.workbuddy.default_profile    = core-ops
        │  core-lean 7 项 + 两份风控技能 = 9 项
        ▼
build.ps1 / skills.ps1 构建生效
        ▼
agent/ 物化 → ~/.gemini/config/skills
             ~/.workbuddy-ai/skills
```

`core-lean` 仍是 Codex、Claude、ZCode 的 7 项常驻 profile；风控技能不并入
`core-lean`，只通过 `core-ops` 投递给 Antigravity 和 WorkBuddy。仓库内修改技能时，
只改 `overrides/custom/`，再运行构建和投影；不要手改 `agent/`、宿主技能目录或本目录的
便携副本。投影回执位于 `reports/skill-projection/`，它们只证明文件投影状态，不能替代
宿主新会话加载或真实业务验收。

只有在没有仓库检出、需要离线迁移到另一台电脑时，才使用下面的 `tools\` 运行脚本和分诊提示词；
技能本身不再在交接包中重复携带。目标机取得本项目后，必须由 `overrides/custom/` 经
`skills.ps1 构建生效` 生成并投影 `core-ops`。

## 怎么用

1. 把整个文件夹拷到新电脑（U 盘 / 网盘均可）。
2. 如果目标机有本仓库检出，先按上面的主链运行构建和投影，不要手工复制技能目录。
   只有使用本交接包进行离线迁移时，才把 `tools\` 里的文件放到：
   - `gen-config.py`、`wire-split.ps1` → `D:\TOOL\v2rayN\ag-split\`
   - `ensure-split.ps1`、`ensure-split.test.ps1`、`ag-split-live-acceptance.ps1`、`register-split-task.ps1` → `D:\TOOL\v2rayN\ag-split\`
   - `ag-health-check.ps1`、`ag-egress-probe.ps1` → `D:\TOOL\v2rayN\`，两者放在同一目录
   - `ensure-patches.ps1`、`register-task.ps1` → `D:\TOOL\antigravity-ensure\`
   - `workbuddy\` 的脚本与分诊材料 → `D:\TOOL\workbuddy-risk\`（只读，位置不敏感）
3. 打开 `PROMPT.md`，**全文复制**，粘贴到新电脑上的对话里。
4. 按提示词的节奏走：**先侦察 → 测量出口 → 再动手**。
5. **按顺序验收**（提示词第 8 节有完整说明）：
   ```
   pwsh -File D:\TOOL\v2rayN\ag-split\ensure-split.test.ps1            # ① 受控验收（离线夹具）
   pwsh -File D:\TOOL\v2rayN\ag-split\ag-split-live-acceptance.ps1     # ② 受控实战验收（真故障注入）
   pwsh -File D:\TOOL\v2rayN\ag-health-check.ps1                       # ③ 全量自检
   pwsh -File D:\TOOL\workbuddy-risk\workbuddy-risk-selfcheck.ps1      # ④ WorkBuddy 自检（只读）
   ```
   ② 已在本机完成一次真实故障注入并自动收尾：PASS 11 / FAIL 0；日常先运行 ①、③、④。

   如需测量配置中 `googleapis.com` 对应节点的出口，按需运行：
   ```powershell
   pwsh -NoProfile -File D:\TOOL\v2rayN\ag-egress-probe.ps1
   # 或在健康检查中附加测量
   pwsh -NoProfile -File D:\TOOL\v2rayN\ag-health-check.ps1 -ProbeGoogleEgress
   ```
   探针将所选节点放入短暂的独立本地实例，通过该节点查询 IP 分类，结束后清理。
   看门狗每三分钟只做本地自愈，附带 `-NoEgressProbe`，避免周期性外网探测。

## 这套方案在解决什么

| 问题 | 做法 |
|---|---|
| Antigravity 不开 TUN 时代理不生效 | `antigravity-proxy`（`version.dll` 注入）+ 系统代理 + 环境变量三者对齐 |
| Google 出口一致性与可达性 | 按域名分流，并按需记录节点出口及第三方分类；分类结果无法证明账号安全或模型质量 |
| 日常软件依赖 CN 优化线路 | **按目标域名分流**，其余流量原样走原线路（国内站仍直连，不绕代理），不整机切换 |
| WorkBuddy 网络与错误分诊 | 检查例外表、`NO_PROXY`、路由及代理配置；结合真实错误、配额与重试节奏定位问题 |

## 六个必须知道的点

1. **不要整机切换到干净出口。** 那会拖慢日常所有软件，本方案已因此被否决过一次。
2. **分流器是新单点。** 它没起来 = 全部代理流量断。包里已包含**双向**自愈：
   起不来就拉起；**拉不起来就把系统代理回退到常驻前端**（否则整机断网）。
3. **`tools\` 里没有凭据。** 分流器配置必须在新电脑上现场生成（`gen-config.py` 从本机 v2rayN 数据库读取），不要跨机器拷贝 `config.json`。
4. **⚠️ 快速启动会让 Startup 文件夹项静默失效。** `HiberbootEnabled=1` 时，「关机」是混合休眠，
   下次开机是恢复会话，**Startup 里的快捷方式不会执行**。判断自启是否有效**不能看文件在不在，要看进程实际有没有跑起来**。
5. **⚠️ 自建内核必须换名。** v2rayN 启动/升级时会**按镜像名**清理旧的 `xray.exe` 进程；
   自建分流器若也叫 `xray.exe`，会被一起杀掉 → 系统代理指向死端口 → 断网。
   本包用**换过名的副本** `ag-split-core.exe`。
6. **WorkBuddy 直连配置需要独立检查。** 当前部署用例外表与 `NO_PROXY` 保持相关域名直连。
   `ensure-split.ps1` 已把 WorkBuddy 五域例外纳入检查；缺失返回 1，人工确认后追加，脚本不覆写例外表。
   全局代理变量暂时保留；分流器失效时不再写入失效端口，但已有环境变量和已启动进程不会自动迁移。
   深度材料（六份报告原件）在源机 `C:\Users\sciman\WorkBuddy AI\`；分诊提示词与技能已并入本包 `tools\workbuddy\`。

## 检测结论的边界

- `wrong_listener_owner`：监听进程路径或绑定地址不符，停止自愈写入；`wrong_task_action`：任务动作或启用状态不符。
- Google DNS 的 ECS 网段只是解析侧线索，不能作为实际请求出口 IP 或分流成功证明。
- Google 端点返回 HTTP 404 仅说明收到服务响应；未验证登录账号、模型生成、配额或长期接受情况。
- `hosting=False`、`proxy=False` 是第三方分类结果，不能承诺减少封禁、限流或改善模型质量。
- 403/11140、429 应结合时间和服务上下文分诊；历史记录、话题相关性或设备多账号记录都不足以单独证明封禁原因。
- WorkBuddy PowerShell 自检省略 MCP 认证细分；需要该证据时运行 Bash 版。退出码 1 表示发现脚本定义的高危项，0 不代表已验证服务端账号状态。

## 计划任务注册的权限坑（实测）

本机**未提权**时，`Register-ScheduledTask` 只有 **`Interactive` + `Limited`** 能注册成功；
`S4U` / `Highest` / `ServiceAccount(SYSTEM)` 全部报「拒绝访问」。
（源机后已提权升级为 `S4U`，见提示词第 12 节。）

## 包外的收尾动作（提示词里也会提）

- 若发现明文存放的服务器密码，**轮换密码后**再删除备份。
- Antigravity 设置内 **AI Credit Overages → Never**（应用内 UI，需手动）。
- 若新电脑上只有一个可用线路，**跳过分流**，只做其余加固 —— 提示词里写了判定规则（WorkBuddy 直连部分不受此影响，照做）。
- **回滚顺序**：停用分流时**先把系统代理改回常驻前端（10808），再停任务**；顺序反了会断网。