# 发布指南

每个版本的本机 staging 根目录是 `artifacts/deliveries/<version>/`，固定交付树如下：

```text
artifacts/deliveries/<version>/
├─ standard-install/  # bootstrap.zip：公共、无 skills/MCP
├─ portable/          # portable.zip：公共、无 skills/MCP
├─ source/            # source.zip：公共源码开发快照、无 skills/MCP
├─ private-snapshot/  # private-all.zip：仅私用、完整 skills/MCP 状态
└─ SHA256SUMS.txt     # 三项公共 ZIP 的校验清单
```

前三项由以下命令生成，均包含公共工具源码；`source.zip` 额外包含开发测试、工作流和 `rules/global/` 源。三个公共包都不含 `agent/`、MCP 声明、目标仓画像、`vendor/`、`imports/` 或宿主目录状态。

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\scripts\release\build-release.ps1 -Version <version>
```

随后只在本机生成第四项：

```powershell
.\skills.ps1 迁移 --mode private-all --version <version>
```

私用快照不得上传到 GitHub Release、公共仓库或公共网盘。它携带仓库规则源 `rules/global/`，但不携带也不自动覆盖各宿主已经生效的用户级规则。任何全局规则恢复仍应按 `global-rules-plan`、`global-rules-apply` 与 rollback receipt 的受控流程执行。

公共 Release 资产只上传 `standard-install/`、`portable/`、`source/` 中的 ZIP 和根部 `SHA256SUMS.txt`。公共源码的持续开发真值仍是 Git clone/fork/tag；`source.zip` 不含 `.git` 历史。构建、checksum、attestation 成功只证明 `repo_verified` 和制品来源，不证明宿主已经 `host_loaded` 或得到 `live_accepted`。

如制品有误，使用新的递增版本；不要覆盖已公开的 Release 资产或移动既有 tag。
