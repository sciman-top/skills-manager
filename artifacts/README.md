# 本机交付产物目录

`artifacts/` 是本机和 CI 的可重建输出目录，不是源码或长期证据仓库。
根层禁止放生成文件；除本说明外，各分类目录的 README 是 Git 中的固定锚点。

## 固定布局

```text
artifacts/
├─ README.md
├─ deliveries/                         # 当前可交付物
│  ├─ README.md
│  ├─ release/<version>/               # bootstrap/portable/校验清单
│  └─ migration/<run-id>/              # general/private-all/rescan 迁移包
├─ history/                            # 人工明确保留的历史副产物
│  └─ README.md
└─ work/                               # 可删除的构建、验证和 evidence
   └─ README.md
```

`deliveries/`、`history/`、`work/` 三类禁止混放：

- `deliveries/release/<version>/` 由 `build-release.ps1` 创建，正式公共下载以 GitHub Release 为准。
- `deliveries/migration/<run-id>/` 由 `迁移` 默认创建；`private-*` 包应立即转移到可信私有存储。
- `history/` 从不由脚本自动填充；只有明确需要保留的旧版本或审计副本才允许人工复制进去。
- `work/` 用于 smoke 解压、临时报告、截图和验证 evidence，完成后应清理。

仓库内的脚本会拒绝把 Release 或 migration 输出写到 `artifacts/` 根层或其他分类目录；测试可以使用仓库外临时目录。

当前已验证公共 Release 为 `v2026.08.27.1`，其公共资产位于 [GitHub Releases](https://github.com/sciman-top/skills-manager/releases)，不是本地 `artifacts/` 目录。
