# 本机交付产物目录

`artifacts/` 是 ignored 的本机/CI 输出目录，不是源码真值或公共下载地址。

```text
artifacts/
├─ deliveries/<version>/
│  ├─ standard-install/
│  ├─ portable/
│  ├─ source/
│  ├─ private-snapshot/
│  └─ SHA256SUMS.txt
├─ history/<kind>/<version-or-date>/
└─ work/<kind>/<run-id>/
```

同一版本的四类交付物必须在同一个 `deliveries/<version>/` 根下：三个公共、空状态包与一个只限私用的完整快照。`rescan/<run-id>/` 可以作为辅助清单位于相同版本根中，但不属于四类交付物。不得把制品直接写入 `artifacts/` 根层；正式公共下载仍以 GitHub Release 为准，私用快照永不公开上传。
