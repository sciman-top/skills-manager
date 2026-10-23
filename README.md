# skills-manager

<p align="center">
  <strong>面向 Windows 的本地优先（Local-First）AI 技能与 MCP 服务版本化管理器</strong><br>
  一处配置，五大 AI 宿主无缝投影 · 版本锁定防漂移 · 目标仓能力审计 · 零账号侵入
</p>

<p align="center">
  <a href="https://github.com/sciman-top/skills-manager/releases"><img src="https://img.shields.io/github/v/release/sciman-top/skills-manager?color=0078D4&label=Release" alt="Release"></a>
  <img src="https://img.shields.io/badge/Platform-Windows-blue?logo=windows" alt="Platform: Windows">
  <img src="https://img.shields.io/badge/PowerShell-7.0%2B-5391FE?logo=powershell" alt="PowerShell 7+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
  <a href="README.en.md"><img src="https://img.shields.io/badge/Language-English-orange.svg" alt="English README"></a>
</p>

---

### 解决什么痛点？

你在用 Codex、Claude Code、ZCode、Antigravity (Gemini) 或 WorkBuddy 进行日常编码时，是否遇到过：

- **多端配置繁琐**：台式机配好的 Agent 技能与 MCP，换到笔记本或新电脑要手动翻目录、重新粘 JSON？
- **多宿主标准分裂**：Codex 要放到 `~/.codex/skills`，Claude 要放到 `~/.claude/`，Antigravity 又有自己的目录，每次加个工具都要配五遍？
- **上游依赖不可控**：引用的第三方开源技能悄悄发了破坏性更新，提示词突然失效，却查不到改动记录？
- **过度包装与隐私焦虑**：想要统一管理，却不想引入沉重的常驻后台，更不想把 API Key 和账号交给第三方代理框架？

**skills-manager** 正是为此而生：把多处分散的 AI 技能和 MCP 服务收敛到单一版本化配置（`skills.json`），精准锁定 Git Commit，并以原生安全的文件链接（Junction）透明投影到各宿主，**不劫持模型、不代理网络、不接触凭据**。

```text
                    ┌─── [ skills.json ] (配置真源) ───┐
                    │   • 技能来源 / 版本锁定 (Git SHA)    │
                    │   • 统一 MCP 场景 Profiles (coding/web)│
                    └─────────────────┬────────────────┘
                                      │
                           pwsh .\skills.ps1 构建生效
                                      │
       ┌──────────────┬───────────────┼───────────────┬──────────────┐
       ▼              ▼               ▼               ▼              ▼
  OpenAI Codex   Claude Code        ZCode       Antigravity     WorkBuddy
(~/.codex/skills) (~/.claude/agents) (~/.zcode/skills) (~/.gemini/...) (本地受管目标)
```

---

## 核心特性

- 🎯 **一次配置，五大多宿主投影**：原生支持 Codex、Claude Code、ZCode、Antigravity（Gemini）与 WorkBuddy。按宿主规范生成目录链接或配置，告别重复配置。
- 🔒 **版本锁定与防漂移（Lockfile）**：内置 `skills.lock.json` 精准锁定 Commit SHA，杜绝上游隐式更新引入的提示词劣化。
- 🔌 **统一 MCP 服务与场景切换**：一条命令安装 stdio / HTTP SSE 协议的 MCP。支持 `default`、`coding`、`browser`、`database` 等场景 Profile，全宿主一键同步。
- 🔍 **目标仓能力智能审查（Audit Targets）**：一键扫描你的本地代码仓库，识别当前项目缺什么技能或 MCP，生成可审查、可预检、带回滚保障的三文件决策包。
- 💻 **交互式 TUI 菜单（新手友好）**：直接双击 `skills.cmd` 即可启动终端图形菜单，浏览、勾选、安装、同步一站式搞定。
- 📦 **开箱即用 & 免安装便携（Portable）**：提供预打包的绿色便携版，支持 U 盘即插即用和离线机器无网运行。
- 🛡️ **严格安全边界**：纯本地运行，不碰你的 API Key / Token，不常驻后台，不侵入模型推断链。

---

## 宿主支持矩阵

| AI 宿主 | 技能投影机制 | 默认 Profile 技能数 | MCP 目标格式 |
| :--- | :--- | :--- | :--- |
| **OpenAI Codex** | Native Skill Root & Agent Bridge | `core-lean` (7 个精选) | 原生 Codex MCP 配置 |
| **Claude Code** | 用户级 `~/.claude/agents` 链接 | `core-lean` (7 个精选) | `~/.claude.json` / Desktop 配置 |
| **ZCode** | `~/.zcode/skills` 链接 | `core-lean` (7 个精选) | `~/.zcode/cli/config.json` |
| **Antigravity (Gemini)** | `~/.gemini/config/skills` 链接 | `core-ops` (8 个运维增强) | `mcp_config.json` |
| **WorkBuddy** | 受管本地目标投影 | `core-ops` (8 个运维增强) | 内部工作区标准配置 |

---

## 快速上手

系统要求：**Windows 10 / 11**，已安装 **PowerShell 7+** (`pwsh`) 与 **Git**。（*注：不支持老旧的 Windows PowerShell 5.1*）。

### 方式 A：GitHub Release 预打包安装（最省心）

前往 [GitHub Releases](https://github.com/sciman-top/skills-manager/releases) 下载最新发行版：

1. **标准一键安装**：下载 `bootstrap.zip`，解压后双击运行：
   ```cmd
   .\setup.cmd
   ```
2. **绿色便携运行（推荐 U 盘 / 离线环境）**：下载 `portable.zip`，解压后直接运行 `skills.cmd`，不会主动改动系统宿主目录。

> 校验信息与安全签名可在 Release 页下载 `SHA256SUMS.txt` 对比。详细说明请参考 [安装、绿色运行与迁移指南](docs/INSTALLATION_AND_MIGRATION.md)。

### 方式 B：源码直接运行 / 交互式菜单

克隆仓库到本地：

```powershell
git clone https://github.com/sciman-top/skills-manager.git
cd skills-manager
```

**新手推荐：直接运行 `skills.cmd` 打开交互菜单**：

```powershell
.\skills.cmd
```

通过上下方向键即可直接执行高频动作：

```text
==============================================
         Skills 管理器（交互菜单）
==============================================
  [1] 浏览技能      - 查看来源中所有可用技能
  [2] 选择安装      - 交互式勾选并写入配置
  [3] 粘贴命令导入  - 直接解析 add / npx 安装指令
  [4] 重建并同步    - 重新编译并安全投影至各 AI 宿主
  [5] 更新上游      - 一键拉取上游技能更新
  [6] 目标仓审查    - 扫描代码仓缺失的 AI 技能
  [7] MCP 服务      - 管理并同步 MCP 服务
  [8] 环境体检      - 运行 doctor 检查健康状态
==============================================
```

---

## 核心工作流与常用命令

### 1. 技能管理（Skills）

```powershell
# 浏览已配置来源中的全部技能
.\skills.ps1 发现

# 交互式选择技能并安装
.\skills.ps1 安装

# 从 GitHub 仓库添加单个技能
.\skills.ps1 add <github-user/repo> --skill <skill-name>

# 检查上游技能是否有新提交（只读预览，不改本地文件）
.\skills.ps1 check-updates --json

# 一键拉取上游更新并升级锁文件
.\skills.ps1 更新 -Upgrade

# 重新生成本地受管技能并投影到宿主目录（核心生效命令）
.\skills.ps1 构建生效

# 仅投影到指定宿主（例如只更新 Codex 与 Claude）
.\skills.ps1 构建生效 -ProjectionHosts codex,claude
```

### 2. 统一 MCP 服务管理（Model Context Protocol）

告别在各个客户端配置文件里手写 JSON 的痛苦：

```powershell
# 添加标准 stdio 类型的 MCP
.\skills.ps1 安装MCP fetch -- uvx mcp-server-fetch

# 添加远程 HTTP / SSE 类型的 MCP
.\skills.ps1 安装MCP remote-api --transport http --url https://api.example.com/mcp

# 查看当前所有 MCP Profiles 场景
.\skills.ps1 MCP配置 列表

# 按场景一键切换启用的 MCP（例如切换为 coding 场景）
.\skills.ps1 MCP配置 使用 coding

# 将当前启用的 MCP 配置同步到所有已安装的宿主（Claude / Codex / Antigravity / ZCode）
.\skills.ps1 同步MCP
```

### 3. 目标代码仓审查（Audit Targets）

想知道自己的某个工程（比如做 OCR 的项目、或做物理课件的项目）缺少什么针对性的 AI 技能？

```powershell
# 1. 添加要审查的本地工程目录
.\skills.ps1 审查目标 添加 my-project D:\CODE\my-project

# 2. 扫描该工程的技术特征与能力需求画像
.\skills.ps1 审查目标 扫描

# 3. 预检推荐的技能方案并 dry-run 验证
.\skills.ps1 审查目标 预检 --recommendations <推荐文件路径>

# 4. 显式确认应用（安全落盘，绝不静默覆盖）
.\skills.ps1 审查目标 应用 --recommendations <推荐文件路径> --apply --yes
```

### 4. 多机迁移与全量快照

在公司电脑配好了 20 个技能和一整套 MCP，怎样安全带回家里的电脑？

```powershell
# 在旧电脑上打包全部现有 skills + MCP（明文私用快照，严禁上传公共网络）
.\skills.ps1 迁移 --mode private-all --version v2026.10

# 拷贝到新电脑后，解压运行一键恢复：
.\skills.ps1 migration-apply
```

---

## 配置真源架构

本项目的配置边界极度清晰，保证开发者的可预期性与环境可复现：

- **`skills.json`**：声明式配置真源。定义上游 `vendors`、已安装映射 `mappings`、目标目录 `targets` 以及 `mcp_servers` 与场景 `mcp_profiles`。
- **`skills.lock.json`**：严格锁定每个引入技能的 Git 提交哈希，协同与迁移时绝不漂移。
- **`overrides/`**：存放你编写的本地私有技能（`custom/`）或对第三方技能的微调补丁（`patches/`）。
- **`agent/`**：构建时生成的纯净技能包中间物，随后透明链接至系统各宿主。

### 四类交付物边界

| 形态 | 产物包 | 定位与说明 |
| :--- | :--- | :--- |
| **标准安装版** | `bootstrap.zip` | 公共标准发行包，解压后通过 `setup.cmd` 一键部署。 |
| **完整绿色版** | `portable.zip` | 离线免安装绿色包，U 盘即插即用，不主动向宿主写入配置。 |
| **公共源码版** | `source.zip` 或 Git clone | 开发者完整工程源码。 |
| **私用全量快照** | `private-all.zip` | 用户自用多机迁移包，携带所有私有配置，明文存放，仅供私有介质流转。 |

---

## 设计原则与安全边界

为了让个人开发者和企业研发团队完全放心地使用，本项目严格遵循以下架构不变量：

1. **零框架劫持**：本工具只负责同步与投影文件配置，**绝不接管你的 API Key、账号登录态、推理网络请求或上下文路由**。
2. **真值分层与证据闭环**：内部严格遵守 `repo_verified -> filesystem_projected -> host_loaded -> live_accepted` 四层边界，未经验证的绝不虚假断言生效。
3. **Fail-Closed 安全机制**：所有 MCP 与规则的同步均支持 `--plan` 预览；修改外部目录前强制经过校验，防止配置污染。
4. **受控的独立扩展**：独立的模型配置工具详见 [模型编排工具](src/model-orchestration/README.md)；产品冻结面与解冻条件详见 [PRD §3.1](docs/product/skills-manager-vnext-prd.md)。

---

## 开发与门禁验证

如果你希望为本项目贡献代码或进行本地定制：

```powershell
# 1. 从源码构建根 skills.ps1 与 skills.lib/
pwsh -NoProfile -File .\build.ps1

# 2. 检查生成物是否与源码保持一致
pwsh -NoProfile -File .\build.ps1 -Check

# 3. 运行本地自动化质量门禁
pwsh -NoProfile -File .\scripts\quality\run-local-quality-gates.ps1 -Profile auto
```

更多工程规范请参阅 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [发布指南](docs/RELEASING.md)。

---

## 开源协议 / License

本项目基于 [MIT License](LICENSE) 开源发布。所引用的第三方技能与依赖仍各自遵循其原始开源许可证。
