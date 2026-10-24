# WorkBuddy 国内/国际版双开部署 Runbook

## 1. 目的与适用边界
- 场景：同一 Windows 用户下并排安装 WorkBuddy 国内版与国际版，两个账号同时在线、登录各自持久。
- 已验收组合：国际版 5.8.4（`WorkBuddyAI.exe`）+ 国内版 5.8.3（`WorkBuddy.exe`）。同代或更新版本按第 2 节来源替换即可，机制不变。
- 本篇是机器级部署档案，不涉及本仓代码与投影变更；跨机迁移时在目标机按本篇重做（`~/.workbuddy*` 登录数据不入 git，跨机不同步）。

## 2. 版本与来源
| 渠道 | 包名 | 端点/登录站 | 认证会话文件 |
| --- | --- | --- | --- |
| 国际 | `WorkBuddyAI.exe`（productName=WorkBuddy AI） | `https://www.workbuddy.ai`（登录仅 Google/GitHub/X） | `workbuddy-desktop-ai.info` |
| 国内 | `WorkBuddy.exe`（productName=WorkBuddy） | `https://www.workbuddy.cn`（微信/手机号等） | `workbuddy-desktop.info` |

- 国际版：workbuddy.ai 官方包或其自更新（当前 5.8.4，安装于 `%LOCALAPPDATA%\Programs\WorkBuddyAI`）。
- 国内版：`https://www.workbuddy.cn/v2/update?platform=workbuddy-win32-x64-user&version=<当前版本>` 获取（返回 JSON 含 `url` 与 `sha256hash`）；也可用 codebuddy.cn「Download-History」页。5.8.3 包 SHA256：`824de10f3196c501004f540eb84ee881292fef2f5df9fb3fc48af9ea5366c03c`，腾讯签名。
- 会话文件目录（两版各自独立，双开互不顶号的机制核心）：`%LOCALAPPDATA%\CodeBuddyExtension\Data\Public\auth\`。

## 3. 安装步骤
1. 国际版：官方包常规安装，默认目录 `%LOCALAPPDATA%\Programs\WorkBuddyAI`，数据目录 `~/.workbuddy-ai`。
2. 国内版：NSIS 静默安装到**独立目录**（勿与国际版同目录）：

   ```powershell
   Start-Process -FilePath '<国内版包>.exe' -ArgumentList '/S', "/D=$env:LOCALAPPDATA\Programs\WorkBuddyCN" -Wait
   ```

   国内包默认数据目录 `~/.workbuddy`，与国际版 `~/.workbuddy-ai` 天然分离；两版认证 id 不同（`workbuddy-desktop` vs `workbuddy-desktop-ai`），登录会话文件互不共享——这是双开成立的核心，任何"改配置伪装"的路线都改不动它（见第 7 节）。
3. 桌面快捷方式两个，分别直接指向两个 exe（勿指向包装脚本）：`WorkBuddy AI` → `WorkBuddyAI.exe`；`WorkBuddy 国内登录` → `WorkBuddyCN\WorkBuddy.exe`。
4. 国内版补登记（其渠道不写卸载注册表项，安装器可能不建开始菜单项）：

   ```powershell
   $dir = "$env:LOCALAPPDATA\Programs\WorkBuddyCN"
   $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WorkBuddyCN'
   New-Item -Path $key -Force | Out-Null
   Set-ItemProperty $key -Name DisplayName -Value 'WorkBuddy 5.8.3 (国内版)'
   Set-ItemProperty $key -Name DisplayVersion -Value '<版本>'
   Set-ItemProperty $key -Name InstallLocation -Value "$dir\"
   Set-ItemProperty $key -Name DisplayIcon -Value "$dir\WorkBuddy.exe,0"
   Set-ItemProperty $key -Name UninstallString -Value "`"$dir\Uninstall WorkBuddy.exe`""
   Set-ItemProperty $key -Name Publisher -Value 'Tencent Technology (Shenzhen) Company Limited'
   Set-ItemProperty $key -Name NoModify -Value 1 -Type DWord
   ```

## 4. 更新与升级
- 两版各自经自己的通道自更新（国际：workbuddy.ai；国内：workbuddy.cn update API；国内查询返回 204 = 已是最新）。
- 国内版若经官方包升级，本篇第 3.4 步注册表项中的 `DisplayVersion` 需手动同步。
- 自动更新会重写安装目录内文件；任何对安装目录内配置的手工改动都会被还原（见第 7 节）。

## 5. 疑难排查
- **登录页跳到错误的站点**：登录站点由各版内置产品配置的 `endpoint` 决定，与运行环境变量无关。检查当前运行的进程路径即可判断版本归属（进程名 `WorkBuddy`=国内、`WorkBuddyAI`=国际；`~/.workbuddy` 与 `~/.workbuddy-ai` 都可能被国际版双写日志，勿据目录日志判归属）。
- **"安装文件损坏或缺失"启动修复弹窗**：安装清单按构建内置文件名单校验，混装/改名/手改安装目录内文件会触发（非阻塞弹窗，应用可继续启动）。恢复官方原版文件或重装即消失；`WB_E2E_DISABLE_STARTUP_REPAIR=true` 环境变量可压制预检。
- **一边登出另一边也掉**：仅发生在两处登录同一账号时（单会话槽）。双开各登不同账号即无此现象。
- **卸载**：国际版走控制面板；国内版运行安装目录内 `Uninstall WorkBuddy.exe`（若建过第 3.4 步注册表项，卸载后该键为孤儿需手动删除）。`~/.workbuddy*` 数据目录卸载不会删除，含登录态与用户数据，按需保留。

## 6. 死路清单（已实测，勿重试）
- 对国际构建注入 `ACC_PRODUCT_CONFIG_PATH` / `CODEBUDDY_COPILOT_INTERNET_ENVIRONMENT` / 改写缓存文件：登录站点不受影响——产品配置每次启动按内置默认重新生成，且 ACC 环境变量进不了 daemon（子进程环境白名单净化）。
- 注入配置修改 `authentication.id` 以分离会话文件：authentication 段以内置配置为准，覆盖无效。
- 替换 `resources\app.asar.unpacked\cli\product.json` 可让国际二进制以国内身份启动，但会触发安装清单校验误报且 daemon 路径未完全验证——已被"真国内构建并排安装"取代，弃用。
- 官方文档（codebuddy.cn/docs/workbuddy）对多开/双账号零说明；本篇为唯一机制档案。
