# 安装、绿色运行与迁移

本文面向使用者。开发者发布流程见 [RELEASING.md](RELEASING.md)。

## 选哪一种包

| 目标 | 推荐包 | 首次动作 | 是否写入宿主目录 |
| --- | --- | --- | --- |
| 新电脑正式安装 | `bootstrap.zip` | 解压后运行 `setup.cmd` | 是，安装配置中的技能目标；MCP 需显式 `-SyncMcp` |
| U 盘/临时目录直接查看和运行 | `portable.zip` | 解压后运行 `skills.cmd` | 否；仅显式执行安装/同步命令时写入 |
| 开发或贡献 | Git clone | `pwsh -File .\install.ps1` | 是 |
| 私用全量迁移 | `private-all` ZIP | 解压后运行 `migration-apply` | 是；MCP 凭据仅在加密包中恢复 |

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

对外产品形态固定为：公共 `general` Release 安装版、公共 Git 源码开发版、私用 `all` 快照包。`rescan` 只是辅助迁移清单，不是开发发行物。旧电脑还可以直接生成这些迁移包：

只有公共 `general` Release 安装版与公共 Git 源码开发版可以 push 到公共 GitHub。`private-all`（以及任何携带私用 MCP 凭据的 `private-*` 包）只能通过可信私有介质或用户控制的私有存储转移；不得 push 到公共仓库、公共 Release 或公共网盘。

```powershell
.\skills.ps1 迁移 --mode all --out .\artifacts\migration-all.zip       # 全部已构建 skills + MCP 意图
.\skills.ps1 迁移 --mode general --out .\artifacts\migration-general.zip # core 通用 skills + default MCP
.\skills.ps1 迁移 --mode private-general --encrypt --out .\artifacts\migration-private-general.zip # 私用加密：core + default MCP 凭据
.\skills.ps1 迁移 --mode private-all --encrypt --out .\artifacts\migration-private-all.zip # 私用加密：全部 skills + MCP 凭据
.\skills.ps1 迁移 --mode rescan --out .\artifacts\migration-rescan.zip   # 不带 skills/MCP，只带重扫指引
```

迁移包内的 `MIGRATION-MANIFEST.json` 是范围和后续动作的真值。`all`、`general`、`private-general` 和 `private-all` 会携带对应的 `agent/`、配置、锁文件、`src/`、测试、脚本、文档和 MIT `LICENSE`，解压后可继续开发；`rescan` 只携带清单，不会复制任何 skill 或 MCP 声明。所有迁移包都不携带 `.git` 历史，若要继续使用版本控制，请在新电脑重新 clone，或在副本中自行 `git init`。使用 `rescan` 时，先在新电脑安装同版本的 skills-manager，再按清单重新发现和安装。

### 私用 + general / all（携带 MCP 凭据）

旧电脑执行打包命令时会交互输入并确认一次加密口令。口令不会写入命令行、日志或 `MIGRATION-MANIFEST.json`；ZIP 中的 `MIGRATION-MCP-CREDENTIALS.enc.json` 使用 PBKDF2-SHA256 + AES-256-GCM 保护。

```powershell
# 旧电脑
.\skills.ps1 迁移 --mode private-general --encrypt --out .\artifacts\migration-private-general.zip
Get-FileHash .\artifacts\migration-private-general.zip -Algorithm SHA256

# 全部 skills + 全部 MCP；同样加密 env/header
.\skills.ps1 迁移 --mode private-all --encrypt --out .\artifacts\migration-private-all.zip
Get-FileHash .\artifacts\migration-private-all.zip -Algorithm SHA256
```

把 ZIP 和 SHA-256 通过可信介质传到新电脑。新电脑先安装 PowerShell 7，解压到稳定目录，然后在解压目录执行一键流程：

```powershell
# 新电脑：恢复凭据、重建/投影 skills，并同步 MCP（交互输入同一口令）
.\skills.ps1 migration-apply
# 如暂时不想改宿主 MCP 配置：
.\skills.ps1 migration-apply --skip-mcp
```

`migration-apply` 会调用包内 `install.ps1 -SkipRebuildLocked`；私用包会先调用 `migration-unlock --yes`，再把配置写入已声明的宿主目标。手动等价流程是 `migration-unlock`（写包内 `skills.json`，随后需输入 `RESTORE`）再执行 `setup.cmd -SkipRebuildLocked -SyncMcp`。新电脑需要自行具备 MCP 的外部依赖（例如 Node.js、npx）和新的宿主登录环境；本流程不迁移 provider/auth/session 或插件缓存。

### 从 GitHub 下载、安装与后续更新

公开分发使用 GitHub Releases：`bootstrap.zip` 是按锁文件联网重建的安装包，`portable.zip` 是带预构建 `agent/` 的绿色包；两者包含运行所需源码、更新脚本、文档和 MIT `LICENSE`，但不包含 `.git` 历史或完整测试树。公共源码开发版应从 GitHub clone、fork 或 tag 获取，才保留完整 Git 历史和测试。下载后先核对 release 提供的 `SHA256SUMS.txt`，再运行 `setup.cmd` 或 `skills.cmd`。日后上游技能的更新可用 `check-updates --json`、`更新 -Plan` 和 `更新 -Upgrade`；仓库还提供 `scripts/weekly-skills-update.ps1` 作为可由用户自行调度的 skills-only runner。

公共 `general` Release 安装版可以检查并更新 skills-manager 本体。它只适用于带 `RELEASE-MANIFEST.json` 的未修改 Release 安装目录，先下载 GitHub Release 元数据、再验证 `SHA256SUMS.txt`，并在独立更新进程中切换目录；旧目录会被保留为同级 backup，安装失败会自动回滚。

```powershell
.\skills.ps1 release-update --check --json
.\skills.ps1 release-update --apply --yes

# 当前交互用户每天 09:00 检查并通知
.\skills.ps1 release-update-schedule --enable --time=09:00
# 同时允许自动启动经过校验的更新
.\skills.ps1 release-update-schedule --enable --time=09:00 --auto-apply
.\skills.ps1 release-update-schedule --disable
```

计划任务不是默认副作用，只有显式 `--enable` 才会创建。它不更新 Git 源码开发版，不带走登录态或凭据，也不因网络可达、下载成功或本地文件替换而声称 `host_loaded` / `live_accepted`。

推荐迁移配置意图，不复制宿主缓存或目录链接：

1. 在旧电脑备份自己修改过的 `skills.json`、`skills.lock.json` 和 `overrides/`。
2. 若没有定制，直接在新电脑使用相同版本的官方 Release，无需搬运 `vendor/`、`imports/`、`agent/`、`reports/`、`.txn/` 或宿主 plugin cache。
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
