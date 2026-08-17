# 发布指南

## 推荐发布模型

最佳方式是 GitHub Release + 两个版本化 ZIP + SHA-256 清单：

- `bootstrap` 是默认推荐下载：小、可复现，按 `skills.lock.json` 拉取锁定来源并安装。
- `portable` 是完整绿色包：内置当前构建好的 `agent/`，适合离线、演示和机器迁移。
- 源码归 Git tag；ZIP 是便利交付物，不替代仓库历史。

项目自身代码采用根目录 [MIT License](../LICENSE)。发布包必须包含该文件；引入的第三方技能、源码和依赖仍保留各自许可证，MIT 不会覆盖或重许可第三方内容。

## 本地一键打包

先冻结并验证源码、配置、锁文件和生成物，再运行：

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\scripts\release\build-release.ps1 -Version 2026.08.13
```

输出到 ignored `artifacts/`：

```text
skills-manager-2026.08.13-bootstrap.zip
skills-manager-2026.08.13-portable.zip
skills-manager-2026.08.13-SHA256SUMS.txt
```

脚本只收集明确的 tracked runtime/config/docs 输入；不会打包 `.git/`、`reports/`、`.txn/`、凭据或用户宿主目录。每个 ZIP 内还有 `RELEASE-MANIFEST.json`，记录 commit、要求、文件大小和逐文件 SHA-256。

`portable` 额外包含 `THIRD-PARTY-NOTICES.json` 和 `THIRD-PARTY-LICENSES/`。它按技能记录 vendor/import/local 来源、锁定 commit、源路径、包内容 SHA-256、frontmatter license 与包内许可证路径。构建器从锁定 commit 读取上游仓库根部的 `LICENSE`/`LICENCE`/`COPYING`/`NOTICE` 文件并集中物化；同一来源的多个技能共享一份许可证，本仓自有技能引用包根 MIT `LICENSE`。只有实际进入 ZIP 的文件才算许可证证据，工作树文件、README 标签或远端口头声明都不能替代它。`unknown_review_required` 是发布阻断 finding：只要存在一项，portable 构建即 fail closed。完成来源与许可证复核、把可分发的许可证证据随包物化后，才能重新构建；不得用 tag、attestation 或人工口头确认绕过。

只构建一种包：

```powershell
.\scripts\release\build-release.ps1 -Version 2026.08.13 -Package Bootstrap
.\scripts\release\build-release.ps1 -Version 2026.08.13 -Package Portable
```

## Tag 自动发布

CI 对 `v*` tag 在 full gate 通过后生成两个 ZIP 和 checksum，为三个资产签发 GitHub artifact build provenance attestation，再创建 GitHub Release。attestation 通过 GitHub OIDC 把资产摘要绑定到当前仓库、workflow 与 tag 构建；它补充而不替代 ZIP 内 `RELEASE-MANIFEST.json` 和 `SHA256SUMS.txt`。建议版本使用 `vYYYY.MM.DD`，同日修订追加 `.N`。

发布顺序：

1. 确认 `main` 干净且与 `origin/main` 一致。
2. 运行 full gate；检查 `build.ps1` 未产生生成物漂移。
3. 在本地实际构建并抽查两个 ZIP。
4. 确认 MIT `LICENSE` 已进入制品，检查 `THIRD-PARTY-NOTICES.json`，并复核第三方来源、所有 `unknown_review_required`、许可证与 release notes。
5. 创建并推送 annotated tag，例如 `git tag -a v2026.08.13 -m "v2026.08.13"`、`git push origin v2026.08.13`。
6. 等待 GitHub Actions 成功，再使用 `gh attestation verify <asset> --repo sciman-top/skills-manager` 验证三个资产的 provenance，并从 Release 页面下载制品复核 SHA-256 与安装烟测。

GitHub Actions 与 attestation 成功只证明 `repo_verified`、制品生成和构建来源；不证明技能已被宿主加载。至少还要在干净 Windows 用户环境中验证一次 `setup.cmd`，并用全新 Codex/Claude 会话验证 `host_loaded`。真实任务效果属于另一个 `live_accepted` 层级。

## 回滚

不要覆盖既有 Release 资产。若制品错误，保留原 tag/Release 以便审计，标记为有问题并发布递增版本。若只是 GitHub 发布步骤失败，可在相同 commit 修复 workflow 后使用新 tag；不要强推或移动已公开 tag。
