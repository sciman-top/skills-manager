# skills-manager

[English](README.en.md) | 中文

`skills-manager` 是一个 Windows 优先的 PowerShell 工具，用来把分散在多个来源的 AI agent skills 汇总到一个可控的本地工作区。

它适合这些场景：

- 你同时使用 Claude、Codex、Gemini、Trae 等多个 agent。
- 你需要从多个仓库导入 skills，但不想手工复制和同步目录。
- 你希望本地补丁放在 `overrides/`，而不是直接改上游缓存。
- 你需要把最终产物统一生成到 `agent/`，再同步到各 CLI 的 skills 目录。

## 核心模型

- `skills.ps1`：唯一命令入口。
- `skills.json`：唯一配置源。
- `agent/`：生成产物和同步源。
- `vendors`：完整上游仓库。
- `imports`：按技能或子路径导入的来源。
- `overrides`：本地补丁和自定义 skills。

## 快速开始

中文命令：

```powershell
.\skills.ps1
.\skills.ps1 发现
.\skills.ps1 doctor --strict
.\skills.ps1 构建生效
```

English aliases：

```powershell
.\skills.ps1
.\skills.ps1 doctor --strict
```

`发现`、`构建生效` 当前无英文别名（N/A）。

首次使用建议运行交互菜单：

```powershell
.\skills.ps1
```

推荐顺序：

1. 新增技能库，或用 `add` / `npx` 命令导入单个技能。
2. 运行 `发现` 查看可用技能。
3. 安装需要的技能，写入 `mappings`。
4. 运行 `构建生效` 生成 `agent/` 并同步到目标目录。
5. 用 `doctor --strict` 检查配置和同步状态。

## 常用命令

中文命令：

```powershell
.\skills.ps1 add <repo> --skill <name>
.\skills.ps1 锁定
.\skills.ps1 构建生效 -Locked
.\skills.ps1 更新 -Plan
.\skills.ps1 更新 -Upgrade
```

English aliases：

```powershell
.\skills.ps1 add <repo> --skill <name>
```

`锁定`、`构建生效`、`更新` 当前无英文别名（N/A）。

说明：

- 未指定 `--skill` 时，`add` 只新增技能库，不会安装整库技能。
- 指定 `--skill` 时，默认按 `manual` 导入到 `imports`；可用 `--mode vendor` 改为 vendor 管理。
- `更新` 会访问上游仓库；只想重新输出本地配置时用 `构建生效`。

## 同步模式

`skills.json` 通过 `sync_mode` 选择同步方式：

- `link`：Windows 推荐；用 junction 让目标目录指向 `agent/`。
- `sync`：用 `robocopy /MIR` 镜像 `agent/`。

本地迭代优先用 `link`。受限环境无法创建链接时用 `sync`。

## overrides 命名

`overrides/` 建议使用清晰前缀：

- `custom-*`：完全自定义的 skill。
- `patch-*`：基于上游 skill 的本地补丁版本。
- `<skill-name>`：有意覆盖同名生成产物时使用。

优先使用 `custom-*` 和 `patch-*`，只有需要同名替换时才直接使用 `<skill-name>`。

## 目标仓技能审查

外层 AI 代理可以让脚本生成目标仓审查包，再由 AI 自行研究官方文档、社区最佳实践、`skills.sh`、GitHub Trending 或 `find-skills` 结果，并把推荐写回 `recommendations.json`。

中文命令：

```powershell
.\skills.ps1 审查目标 初始化
.\skills.ps1 审查目标 添加 my-repo ..\my-repo
.\skills.ps1 审查目标 扫描 --target my-repo
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
```

默认 `应用` 只做 dry-run。只有同时传入 `--apply --yes` 才会安装新增技能、构建生效并运行 doctor。重叠技能只写入报告，不会自动卸载。

English aliases：

```powershell
.\skills.ps1 audit-targets init
.\skills.ps1 audit-targets add my-repo ..\my-repo
.\skills.ps1 audit-targets scan --target my-repo
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
```

## 仓库结构
```text
repo/
  skills.ps1        # 主入口，由 src/ 生成
  skills.json       # 单一配置源
  build.ps1         # 从 src/ 重新生成 skills.ps1
  src/              # 源模块
  tests/            # 单元与端到端验证
  overrides/        # 本地覆盖层
  imports/          # 定向导入来源
  vendor/           # 上游缓存，本地生成
  agent/            # 生成产物，本地生成
```

## 本地门禁

提交前按固定顺序运行：

中文命令：

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

English aliases：

```powershell
./build.ps1
./skills.ps1 doctor --strict --threshold-ms 8000
```

`发现`、`构建生效` 当前无英文别名（N/A）。

## 仓库卫生

不要提交本地 agent 状态、日志、缓存或临时产物，包括：

- `.claude/`、`.codex/`、`.gemini/`、`.trae/`
- 本地规则文件，例如 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md`
- 日志、备份和临时文件
- `_probe_*`、`_debug_*`、`_tree_*` 导入快照

这些文件可以存在于本机，但不属于仓库契约。

## 相关文档

- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

MIT
