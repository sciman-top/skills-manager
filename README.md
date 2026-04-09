# skills-manager

中文 | [English](README.en.md)

`skills-manager` 是一个面向 Windows 和 PowerShell 的 AI agent skills 管理器，用来把多个上游技能仓库收敛成一套可构建、可覆盖、可同步的本地工作区。

它解决的是同一类问题：你可能同时在用 Claude、Codex、Gemini、Trae，也可能同时维护多个 skills 来源，但不想继续手工复制目录、追踪漂移、处理覆盖冲突。

## 一句话定位

一个本地优先的 skills 装配层：

- 向上聚合多个上游仓库
- 向下分发到多个 agent 目标目录
- 中间用一份 `skills.json` 管理启用、映射、导入、同步和 MCP 配置

## 为什么用它

- 不再手工维护多个 `~/.xxx/skills` 目录
- 只启用你真正需要的 skills，而不是整仓照搬
- 本地修补放进 `overrides/`，不污染上游缓存
- 构建结果统一落到 `agent/`，便于审阅和回滚
- `link` / `sync` 两种同步模式可切换，适应不同 Windows 环境

## 核心模型

- 单一入口：`skills.ps1`
- 单一配置源：`skills.json`
- 单一构建输出：`agent/`

输入层分为三类：

- `vendors`：整仓上游来源
- `imports`：按技能或子路径的定向导入
- `overrides`：本地覆盖和修补

## overrides 分组约定

建议在 `overrides/` 下按用途分组，统一命名前缀：

- `custom-*`：纯自定义技能（不依赖上游同名技能）
- `patch-*`：对上游技能的本地补丁/变体
- `<skill-name>`：需要直接覆盖同名技能时使用（同名覆盖）

推荐做法：优先使用 `custom-*` / `patch-*` 提高可读性；只有明确要“同名覆盖”时才使用 `<skill-name>` 目录名。

## 仓库结构

```text
repo/
  skills.ps1        # 主入口
  skills.json       # 唯一配置源
  build.ps1         # 从 src/ 重建 skills.ps1
  src/              # 主脚本源码
  tests/            # 单元与端到端验证
  overrides/        # 本地覆盖层
  imports/          # 定向导入来源
  vendor/           # 上游缓存，构建期生成
  agent/            # 构建输出，生效期生成
```

## 典型流程

```powershell
.\skills.ps1 发现
.\skills.ps1 构建生效
.\skills.ps1 doctor --strict
```

首次使用时，也可以直接运行交互菜单：

```powershell
.\skills.ps1
```

推荐顺序：

1. 新增一个或多个上游仓库
2. 选择要启用的 skills
3. 构建并生效
4. 用 `doctor --strict` 检查契约和目标状态

## 同步方式

`skills.json` 里的 `sync_mode` 支持两种模式：

- `link`：优先使用 Junction，把目标目录直接指向 `agent/`
- `sync`：用 `robocopy /MIR` 做镜像复制

前者更适合长期本地使用，后者适合不允许链接的环境。

## 版本与导入

常用操作：

- 单技能导入：`.\skills.ps1 add <repo> --skill <name>`
- 生成锁文件：`.\skills.ps1 锁定`
- 严格构建：`.\skills.ps1 构建生效 -Locked`
- 预览升级：`.\skills.ps1 更新 -Plan`
- 升级并刷新锁：`.\skills.ps1 更新 -Upgrade`

## 开发门禁

本仓库按固定顺序执行：

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict
./skills.ps1 构建生效
```

新增提交前，至少应跑完这组门禁。

## 仓库边界

远端仓库不接收本地专用状态，包括但不限于：

- `.claude/`、`.codex/`、`.gemini/`、`.trae/`
- `AGENTS.md`、`CLAUDE.md`、`GEMINI.md` 等本地代理规则文件
- 日志、备份、临时文件
- import 过程产生的 `_probe_*`、`_debug_*`、`_tree_*` 调试快照

这些内容允许本地存在，但不应成为仓库契约的一部分。CI 也会检查这条规则。

## 相关文档

- [英文版 README](README.en.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [行为准则](CODE_OF_CONDUCT.md)
- [PR 模板](.github/pull_request_template.md)
