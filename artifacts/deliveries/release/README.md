# 公共 Release staging

每个版本使用独立的 `<version>/` 子目录，存放 bootstrap、portable 和
SHA-256 清单。GitHub Actions 只从对应版本目录签名并创建 Release；这些
本地文件不会提交到 Git。
