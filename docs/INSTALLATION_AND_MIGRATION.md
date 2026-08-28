# 安装、绿色运行与迁移

同一 `<version>` 的交付物统一放在 `artifacts/deliveries/<version>/`。固定四个子目录：

| 子目录 | 交付物 | skills / MCP | 用途 |
| --- | --- | --- | --- |
| `standard-install/` | `bootstrap.zip` | 不携带 | 联网标准安装；在新电脑扫描目标仓后再选择安装。 |
| `portable/` | `portable.zip` | 不携带 | 绿色使用；同样先扫描、再安装自己的 skills/MCP。 |
| `source/` | `source.zip` | 不携带 | 公共源码开发快照；完整 Git 历史仍以 clone/fork/tag 为准。 |
| `private-snapshot/` | `skills-manager-<version>-private-all-<run-id>.zip` | 携带当前完整状态 | 私用、明文、无口令的整机恢复快照；不得进入公共 Release。 |

`rescan` 只是辅助清单，不是第五种交付物。它可临时输出到版本目录的 `rescan/<run-id>/`，用于在新电脑重新发现目标仓、生成画像，再由用户确认安装 skills/MCP。

## 标准安装与绿色使用

两个公共包都含公共工具源码和文档，但不含 `agent/`、已配置的 MCP、目标仓清单、`vendor/` 或 `imports/`。解压后先用本机实际目标仓完成扫描和选择：

```powershell
.\skills.ps1 审查目标 扫描
.\skills.ps1 发现
.\skills.ps1 安装
# 需要时再明确同步 MCP
.\skills.ps1 同步MCP
```

`bootstrap.zip` 用 `setup.cmd` 标准安装；`portable.zip` 可先运行 `skills.cmd`，且不会自动写入宿主目录。二者首次安装都需要 Git 与网络，以便按用户随后选择的来源获取技能；外部工具依赖与宿主登录环境仍需新电脑自行具备。

## 私用全量快照

先用相同版本生成三个公共包，再在同一版本根目录生成私用包：

```powershell
.\scripts\release\build-release.ps1 -Version <version>
.\skills.ps1 迁移 --mode private-all --version <version>
```

私用快照内含完整 `agent/`、物化来源、仓库内 `rules/global/` 规则源和 MCP `env`/`headers` 明文 companion file `MIGRATION-MCP-CREDENTIALS.json`，不询问口令。它不打包、更不自动覆盖各宿主已经生效的 `~/.codex`、`~/.claude`、`~/.zcode` 全局规则；恢复后仍需走规则计划、确认与回滚投影。它只限你的本机或可信私有介质，不能上传公共 GitHub、公共 Release 或公共网盘；它不含 Git 历史，也不替代公共源码开发真值。

新电脑在解压后的快照目录运行：

```powershell
.\skills.ps1 migration-apply
# 如暂时不改宿主 MCP：
.\skills.ps1 migration-apply --skip-mcp
```

`migration-apply`、文件校验成功或 `doctor --strict` 至多证明 repo/filesystem 层面的结果；请在新宿主的全新会话中单独验证 `host_loaded`，真实任务效果仍是 `live_accepted` 的另一个层级。
