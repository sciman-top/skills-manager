# skills-manager

中文 | [English](README.en.md)

`skills-manager` 是一个面向 Windows 与 PowerShell 的本地技能聚合、构建和分发工具，用来把多个上游技能仓库整理成一套可控、可复用、可同步的本地 AI agent skills 工作区。

它的目标不是“再造一个技能市场”，而是把多来源 skills 的日常管理收敛成一条清晰流程：

- 统一收集
- 精确启用
- 本地覆盖
- 一键构建
- 同步到 Claude / Codex / Gemini / Trae 等目标目录

## 核心价值

- 多源聚合：同时管理多个上游 skills 仓库。
- 白名单装配：只启用你明确选择的 skills。
- 覆盖优先：允许通过 `overrides/` 做本地修正，而不污染上游缓存。
- 构建产物清晰：所有组合结果统一落到 `agent/`。
- 同步方式可控：支持 `link` 和 `sync` 两种模式。
- 交互与脚本兼容：既能跑中文菜单，也能直接走命令行。

## 适用场景

- 你同时使用 Claude、Codex、Gemini 等多个 agent 工具。
- 你不想手工维护多个 `~/.xxx/skills` 目录。
- 你需要在上游 skills 基础上叠加本地规则或修补。
- 你希望更新过程可预览、可回滚、可审计。

## 仓库结构

```text
repo/
  skills.ps1        # 主入口
  skills.json       # 唯一配置源
  build.ps1         # 从 src/ 重建 skills.ps1
  src/              # 脚本源码
  tests/            # 单元测试与端到端测试
  overrides/        # 本地覆盖层
  imports/          # 手工导入或定向导入来源
  vendor/           # 上游缓存，构建期生成
  agent/            # 构建输出，生效期生成
```

## 核心模型

### 单一入口

- `skills.ps1`：统一调度发现、安装、更新、构建、doctor、MCP 等动作。

### 单一配置源

- `skills.json`：统一描述 `vendors`、`mappings`、`imports`、`targets`、`sync_mode` 与 `mcp_servers`。

### 单一构建产物

- `agent/`：由 vendor 映射、manual imports、overrides 合成后的最终技能集合。

## 快速开始

### 前置条件

- Windows 10/11
- PowerShell 5.1+ 或 PowerShell 7+
- Git
- `robocopy`

如当前 PowerShell 会话限制脚本执行，可临时放开：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### 首次使用

运行交互菜单：

```powershell
.\skills.ps1
```

推荐顺序：

1. 新增技能库
2. 选择需要启用的技能
3. 构建并生效
4. 用 `doctor --strict` 做完整检查

### 常用命令

```powershell
.\skills.ps1 发现
.\skills.ps1 构建生效
.\skills.ps1 更新
.\skills.ps1 doctor --strict
```

仅做预演时可加 `-DryRun`：

```powershell
.\skills.ps1 发现 -DryRun
```

## 同步模式

在 `skills.json` 中通过 `sync_mode` 控制：

- `link`
  - Windows 下优先使用 Junction，把目标目录直接指向 `agent/`
  - 适合本地长期使用，改动能立即反映
- `sync`
  - 使用 `robocopy /MIR` 镜像复制到目标目录
  - 适合不允许链接或需要纯复制部署的环境

## 单技能导入

当你不想把整个仓库纳入 `vendors`，可以按单技能导入到 `imports/`：

```powershell
.\skills.ps1 add <repo> --skill <name> [--ref <branch/tag>] [--sparse]
.\skills.ps1 npx "skills add <repo> --skill <name> [--ref <branch/tag>] [--sparse]"
```

常用参数：

- `--mode manual|vendor`
- `--ref`
- `--sparse`

## 版本锁定

如需固定上游版本：

- 生成锁文件：`.\skills.ps1 锁定`
- 严格构建：`.\skills.ps1 构建生效 -Locked`
- 严格更新：`.\skills.ps1 更新 -Locked`
- 预览升级：`.\skills.ps1 更新 -Plan`
- 升级并刷新锁：`.\skills.ps1 更新 -Upgrade`

## MCP 管理

示例：安装 `fetch` MCP 服务

```powershell
python -m pip install --user mcp-server-fetch
.\skills.ps1 安装MCP fetch --cmd python --arg -m --arg mcp_server_fetch
```

交互式安装也可直接执行：

```powershell
.\skills.ps1 安装MCP
```

## 开发与质量门禁

本仓库按固定顺序执行质量门禁：

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict
./skills.ps1 构建生效
```

这也是提交前的最小验证集合。

## 仓库边界

本仓库不把以下内容视为远端分发物：

- `.claude/`、`.codex/`、`.gemini/`、`.trae/` 等本地 agent 目录
- 本地日志、备份、临时文件
- import 过程产生的 `_probe_*`、`_debug_*`、`_tree_*` 调试快照

这些文件允许在本地存在，但不应构成远端仓库契约的一部分。

## 相关文档

- [英文版 README](README.en.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [行为准则](CODE_OF_CONDUCT.md)
- [PR 模板](.github/pull_request_template.md)
