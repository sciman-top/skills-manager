# Contributing to skills-manager

感谢你参与 `skills-manager`。

## 开发环境

- Windows 10/11
- PowerShell 5.1+（推荐 PowerShell 7+）
- Git

## 本地开发步骤

1. Fork 并克隆仓库。
2. 创建功能分支：`git checkout -b feat/<topic>`。
3. 完成修改后执行项目门禁（顺序不可变）：

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict
./skills.ps1 构建生效
```

4. 提交时写清楚变更目的、范围和影响。
5. 发起 Pull Request，并按模板补齐验证证据。

## 代码与目录约束

- `skills.ps1` 是统一入口；`skills.json` 是唯一配置源。
- `agent/` 与 `vendor/` 为生成/缓存目录，不建议手工修改。
- 自定义改动优先放在 `overrides/` 与 `imports/`。

## 提交建议

- 小步提交，保持单一主题。
- 变更说明尽量包含：
  - why（为什么改）
  - what（改了什么）
  - verification（如何验证）
  - rollback（如何回滚）
