# 参考仓刷新记录

这个目录只保留外置参考仓刷新机制的稳定说明。刷新结果属于运行时状态，写入 ignored `reports/reference-refresh/<run-id>/receipt.md`。

使用约定：

- `references/reference-shelf.manifest.json`：稳定的来源、分层与消费关系
- `reports/reference-refresh/<run-id>/receipt.md`：每次显式刷新的现场结果（不入 Git）

默认关注：

- `core` 参考仓是否已存在
- `core-default` 刷新集合是否能完成
- 哪些仓是 `updated` / `fetch-only` / `missing` / `cloned` / `fetch-failed` / `pull-failed`

刷新 receipt 不作为普通 build/test/update/projection 的 freshness gate。
