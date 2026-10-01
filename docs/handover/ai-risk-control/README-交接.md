# 交接包 — Antigravity × Gemini × WorkBuddy 风控加固

在另一台 Windows 电脑上复现同一套加固方案。

> 版本：2026-10-01（第三版，并入 WorkBuddy 风控并收敛为**唯一版本**）　·　受控验收 **PASS 16 / FAIL 0**　·　受控实战验收 **PASS 10 / FAIL 0**
> 唯一落位：`D:\CODE\skills-manager\docs\handover\ai-risk-control\`（原 `D:\TOOL\v2rayN\` 下副本与 WorkBuddy 独立交接包已退役删除）

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
   ├─ ensure-split.test.ps1           **受控验收**：夹具注入，16 个用例，离线、不碰真实状态
   ├─ ag-split-live-acceptance.ps1    **受控实战验收**：真故障注入，10 个用例，可自动收尾
   ├─ ag-health-check.ps1             只读自检脚本（23 项，有 FAIL 返回 1）
   ├─ ensure-patches.ps1              **核心**：代理 + 汉化 + 分流器 一体化幂等自愈
   ├─ register-task.ps1               注册/更新「每 30 分钟 + 登录」的自愈计划任务
   └─ workbuddy\
      ├─ workbuddy-risk-selfcheck.ps1     WorkBuddy 只读风控自检（PowerShell 版）
      ├─ workbuddy-risk-selfcheck.sh      同一套检查逻辑的 Git Bash 版
      ├─ workbuddy-risk-selfcheck.test.sh 脚本自身的离线验收夹具
      ├─ workbuddy-triage-prompt.md       分诊提示词（429/403/11140 分诊流程与红线清单）
      └─ skill\
         └─ workbuddy-risk-triage\        分诊技能（SKILL.md + 4 份参考，装入宿主技能目录即用）
```

## 怎么用

1. 把整个文件夹拷到新电脑（U 盘 / 网盘均可）。
2. 把 `tools\` 里的文件放到：
   - `gen-config.py`、`wire-split.ps1` → `D:\TOOL\v2rayN\ag-split\`
   - `ensure-split.ps1`、`ensure-split.test.ps1`、`ag-split-live-acceptance.ps1`、`register-split-task.ps1` → `D:\TOOL\v2rayN\ag-split\`
   - `ag-health-check.ps1` → `D:\TOOL\v2rayN\ag-health-check.ps1`
   - `ensure-patches.ps1`、`register-task.ps1` → `D:\TOOL\antigravity-ensure\`
   - `workbuddy\` 的脚本与分诊材料 → `D:\TOOL\workbuddy-risk\`（只读，位置不敏感；要装分诊技能时取 `skill\workbuddy-risk-triage\` 放入宿主技能目录）
3. 打开 `PROMPT.md`，**全文复制**，粘贴到新电脑上的对话里。
4. 按提示词的节奏走：**先侦察 → 测量出口 → 再动手**。
5. **按顺序验收**（提示词第 8 节有完整说明）：
   ```
   pwsh -File D:\TOOL\v2rayN\ag-split\ensure-split.test.ps1            # ① 受控验收（离线夹具）
   pwsh -File D:\TOOL\v2rayN\ag-split\ag-split-live-acceptance.ps1     # ② 受控实战验收（真故障注入）
   pwsh -File D:\TOOL\v2rayN\ag-health-check.ps1                       # ③ 全量自检
   pwsh -File D:\TOOL\workbuddy-risk\workbuddy-risk-selfcheck.ps1      # ④ WorkBuddy 自检（只读）
   ```
   ② 约需 4–5 分钟（含等真实看门狗），结束会自动把系统恢复原状。

## 这套方案在解决什么

| 问题 | 做法 |
|---|---|
| Antigravity 不开 TUN 时代理不生效 | `antigravity-proxy`（`version.dll` 注入）+ 系统代理 + 环境变量三者对齐 |
| Gemini 账号风控（封号 / 限流 / 降智） | 让 **Google 系流量走「未被标记为机房/代理」的出口** |
| 日常软件依赖 CN 优化线路 | **按目标域名分流**，其余流量原样走原线路（国内站仍直连，不绕代理），不整机切换 |
| WorkBuddy 封号 / 限流 | **直连是硬规则（走代理=官方红线）**：例外表 / `NO_PROXY` / 路由 / 不接管系统代理四层固化，加行为面纪律（网关类工作移出会话、控制并发与重试） |

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
6. **⚠️ WorkBuddy 的红线与 Google 相反。** Google 侧是「让流量走干净代理出口」，WorkBuddy 是「**绝不走代理**」——
   官方错误码页明写「关闭网络代理」，协议把反代/共享列为红线，封禁是账号级且无解封案例；换号**不清**设备指纹，重装无效。
   好消息是两个领域只在「系统代理例外表」交汇，`ensure-split.ps1` 已把 WorkBuddy 五域例外纳入守护（缺失即 FAIL 并补回）。
   深度材料（六份报告原件）在源机 `C:\Users\sciman\WorkBuddy AI\`；分诊提示词与技能已并入本包 `tools\workbuddy\`。

## 计划任务注册的权限坑（实测）

本机**未提权**时，`Register-ScheduledTask` 只有 **`Interactive` + `Limited`** 能注册成功；
`S4U` / `Highest` / `ServiceAccount(SYSTEM)` 全部报「拒绝访问」。
（源机后已提权升级为 `S4U`，见提示词第 12 节。）

## 包外的收尾动作（提示词里也会提）

- 若发现明文存放的服务器密码，**轮换密码后**再删除备份。
- Antigravity 设置内 **AI Credit Overages → Never**（应用内 UI，需手动）。
- 若新电脑上只有一个可用线路，**跳过分流**，只做其余加固 —— 提示词里写了判定规则（WorkBuddy 直连部分不受此影响，照做）。
- **回滚顺序**：停用分流时**先把系统代理改回常驻前端（10808），再停任务**；顺序反了会断网。
