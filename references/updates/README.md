# 参考仓刷新记录

这个目录保存 `skills-manager` 外置参考仓刷新后的摘要。

使用约定：

- `reference-refresh-latest.md`：当前稳定入口，永远指向最近一次验证过的刷新结果
- `reference-refresh-YYYYMMDD-HHMMSS.md`：历史留档，保留当次刷新时的现场结果

默认关注：

- `core` 参考仓是否已存在
- `core-default` 刷新集合是否能完成
- 哪些仓是 `updated` / `fetch-only` / `missing` / `cloned` / `fetch-failed` / `pull-failed`

稳定入口规则：

- `reference-refresh-latest.md` 只保留默认 `core-default` 结果
- 自定义 `RepoNames` 或 `Tier` 运行只生成新的历史文件，不覆盖 `latest`
