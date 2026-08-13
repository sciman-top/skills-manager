# 安装、绿色运行与迁移

本文面向使用者。开发者发布流程见 [RELEASING.md](RELEASING.md)。

## 选哪一种包

| 目标 | 推荐包 | 首次动作 | 是否写入宿主目录 |
| --- | --- | --- | --- |
| 新电脑正式安装 | `bootstrap.zip` | 解压后运行 `setup.cmd` | 是，安装配置中的技能目标；MCP 需显式 `-SyncMcp` |
| U 盘/临时目录直接查看和运行 | `portable.zip` | 解压后运行 `skills.cmd` | 否；仅显式执行安装/同步命令时写入 |
| 开发或贡献 | Git clone | `pwsh -File .\install.ps1` | 是 |

两种包都要求 Windows 与 PowerShell 7。`bootstrap` 安装和任何上游更新需要 Git 与网络；`portable` 已内置构建好的 `agent/`，可离线打开菜单、浏览本地内容，但联网型技能及外部工具仍取决于各自环境。

## 新电脑一键安装

1. 安装 [PowerShell 7](https://aka.ms/powershell) 和 [Git](https://git-scm.com/download/win)。
2. 从 GitHub Release 下载 `skills-manager-<version>-bootstrap.zip` 和 `SHA256SUMS.txt`。
3. 可选但推荐：核对 ZIP 的 SHA-256。

```powershell
Get-FileHash .\skills-manager-<version>-bootstrap.zip -Algorithm SHA256
```

4. 解压到不频繁移动的目录，例如 `D:\Tools\skills-manager`。
5. 双击 `setup.cmd`，或在终端运行：

```powershell
.\setup.cmd
# 同时同步已配置的 MCP（会修改对应宿主配置）
.\setup.cmd -SyncMcp
```

安装器按 `skills.lock.json` 重建锁定来源，构建技能目录，投影到 `skills.json` 中的目标，然后运行 `doctor --strict`。它不安装 PowerShell、Git、Node/Python 等技能自己的依赖，也不接管模型、provider、auth、session 或插件缓存。

## 绿色包直接运行

解压 `portable.zip` 后运行：

```powershell
.\skills.cmd
.\skills.cmd help
```

绿色运行不会自动写入 `~/.agents`、`~/.claude`、`~/.codex` 或 MCP 配置。要把绿色包正式投影到当前用户，仍须显式运行 `setup.cmd`。因此“解压即用”和“安装进宿主”是两个清晰动作。

## 从旧电脑迁移

推荐迁移配置意图，不复制宿主缓存或目录链接：

1. 在旧电脑备份自己修改过的 `skills.json`、`skills.lock.json` 和 `overrides/`。
2. 若没有定制，直接在新电脑使用相同版本的官方 Release，无需搬运 `vendor/`、`agent/`、`reports/`、`.txn/` 或宿主 plugin cache。
3. 若有定制，把上述文件覆盖到新解压目录；先审查差异和其中是否有凭据，再运行 `setup.cmd`。
4. MCP 清单可随 `skills.json` 迁移，但 token、登录态和环境变量应通过各宿主/系统重新配置，不能打进发布包。
5. 在新电脑开启一个全新宿主会话验证技能是否加载。`doctor --strict` 只证明仓库与本机基础环境健康，不等于 `host_loaded` 或 `live_accepted`。

如需完全离线迁移，可在可信电脑生成 `portable.zip` 并传输；仍应保留 `SHA256SUMS.txt`，且不要把凭据、ignored runtime reports 或用户目录一起打包。

## 更新与回滚

```powershell
# 查看将更新什么
.\skills.cmd 更新 -Plan
# 明确升级上游并重建
.\skills.cmd 更新 -Upgrade
# 回到 release 锁定版本
.\skills.cmd 更新 -Locked
```

升级前保留旧 ZIP 或整个旧解压目录。回滚时关闭使用相关文件的进程，换回旧目录，再运行旧版 `setup.cmd`。项目只负责其配置声明的技能/MCP 投影；宿主自身的升级、认证和配置回滚不在本项目范围内。

## 常见问题

- 双击窗口闪退：在终端运行 `pwsh -NoProfile -File .\install.ps1` 查看完整错误。
- 提示找不到 `pwsh`：安装 PowerShell 7；Windows PowerShell 5.1 不受支持。
- 安装时提示找不到 Git：`bootstrap` 需按锁文件取回来源，请安装 Git；纯绿色查看改用 `portable`。
- 长路径失败：启用 Windows Long Paths，并尽量解压到较短目录。
- 公司网络无法访问 GitHub：使用在可信联网环境生成的 `portable` 包，或配置组织允许的镜像；不要跳过来源与哈希审查。
