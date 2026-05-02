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

交互菜单按“高频动作直达 + 领域子菜单”组织，主菜单优先显示：

- 浏览技能
- 选择安装
- 粘贴命令导入
- 卸载技能
- 重建并同步（CLI 命令仍为 `构建生效`）
- 更新上游（CLI 命令仍为 `更新`）
- 目标仓审查
- MCP 服务
- 技能库管理
- 更多

`目标仓审查` 子菜单按实际流程展开：

1. 查看/编辑需求
2. 查看目标仓列表
3. 生成审查包
4. 预检建议
5. 应用建议（先 dry-run）
6. 查看最近状态

推荐顺序：

1. 新增技能库，或用 `add` / `npx` 命令导入单个技能。
2. 运行 `发现` 查看可用技能。
3. 安装需要的技能，写入 `mappings`。
4. 运行 `构建生效` 生成 `agent/` 并同步到目标目录。
5. 用 `doctor --strict` 检查配置和同步状态。

## 一键工作流（推荐）

```powershell
.\skills.ps1 一键 --list
.\skills.ps1 一键 新手
.\skills.ps1 一键 维护 --continue-on-error
.\skills.ps1 一键 审查 --no-prompt
.\skills.ps1 workflow all --no-prompt
```

场景说明：

- `新手`：`浏览技能 -> 选择安装 -> 重建并同步 -> doctor --strict`
- `维护`：`更新上游 -> 重建并同步 -> 同步 MCP -> doctor --strict`
- `审查`：`查看需求 -> 目标仓列表 -> 生成审查包 -> 查看最近状态`
- `全流程`：`更新上游 -> 浏览技能 -> 重建并同步 -> 同步 MCP -> doctor --strict`

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

## MCP 托管边界

`skills-manager` 通过 `skills.json` 的 `mcp_servers` 和 `.\skills.ps1 同步MCP` 托管 MCP 服务清单，并把结果写入：

- 各目标根目录 `.mcp.json`
- `~/.gemini/settings.json` 与 `~/.gemini/antigravity/settings.json` 的 MCP 段
- `~/.trae/mcp.json` 与项目级 `.trae/mcp.json`
- `~/.codex/config.toml` 中的 `[mcp_servers.*]` 段

以下内容不属于 `skills-manager` 的 MCP 托管边界，修改它们应去各宿主自己的配置真源，而不是改 `skills.json`：

- Codex：`windows.sandbox`、approval policy、model/reasoning/context 等非 MCP 字段
- Claude / Gemini：auth、provider、model、context、sandbox、非 MCP 权限策略等宿主级设置

## overrides 命名

`overrides/` 建议使用清晰前缀：

- `custom-*`：完全自定义的 skill。
- `patch-*`：基于上游 skill 的本地补丁版本。
- `<skill-name>`：有意覆盖同名生成产物时使用。

优先使用 `custom-*` 和 `patch-*`，只有需要同名替换时才直接使用 `<skill-name>`。

## 目标仓技能审查

外层 AI 代理可以让脚本生成目标仓审查包，再由 AI 自行研究官方文档、社区最佳实践、`skills.sh`、GitHub Trending 或 `find-skills` 结果，并把推荐写回 `recommendations.json`。

每次“生成审查包”后，优先把本次 run 目录里的 `outer-ai-prompt.md` 交给外层 AI，而不是只交 `ai-brief.md`。这份运行态提示词已经写明了应执行的顺序：

- 读取 `ai-brief.md`
- 按 `recommendations.template.json` 的 schema 填写 `recommendations.json`
- 先做自检：schema、占位符、双理由、真实来源全部通过
- 再执行 `应用确认（两阶段：dry-run -> 确认口令 -> apply）`
- 按 dry-run 原序号列出新增/卸载建议清单
- 或按需使用 `应用 recommendations（--apply --yes，可按序号选择增删）`

正式审查时必须同时基于两类上下文：

- 全局“用户基本需求”：长期工作类型、偏好、约束、常见任务
- 目标仓：当前项目的技术栈、规则文件、构建和测试事实

没有用户基本需求时，不应开始正式审查。启动审查流程后，外层 AI 可以在本次流程内自主联网研究，但联网不等于自动安装或自动卸载。

`需求设置` 保存原始长文本后，会自动进入结构化导入流程：

- 回车：使用默认路径 `reports\skill-audit\user-profile.structured.json`
- 自定义输入：使用你给定的路径和文件名
- 若目标文件不存在：脚本会自动生成结构化草稿文件，供 AI 或人工补全后再导入
- 输入 `0`：跳过本次结构化导入

中文命令：

```powershell
.\skills.ps1 审查目标 初始化
.\skills.ps1 审查目标 需求设置
.\skills.ps1 审查目标 需求查看
.\skills.ps1 审查目标 需求结构化 --profile reports\profile.json
.\skills.ps1 审查目标 添加 my-repo ..\my-repo
.\skills.ps1 审查目标 扫描 --target my-repo
.\skills.ps1 审查目标 发现新技能 --query "repo governance and agent workflows"
.\skills.ps1 审查目标 状态
.\skills.ps1 审查目标 应用确认 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --dry-run-ack "我知道未落盘"
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes --add-indexes "1,3" --remove-indexes "2" --mcp-add-indexes "1" --mcp-remove-indexes "2"
```

`发现新技能` 是不绑定目标仓的 profile-only 模式，会生成同样的审查包与 `recommendations.template.json`，但不生成 `repo-scan.json`；外层 AI 必须基于用户画像、已安装技能、`source-strategy.json` 和真实来源研究给出建议。
默认 `应用` 只做 dry-run。只有同时传入 `--apply --yes` 才会真正执行你选中的新增和卸载、构建生效并运行 doctor。
`应用确认` 提供单入口两阶段流程：先 dry-run，再要求输入确认口令 `APPLY <run-id>` 才会执行落盘。
在 dry-run 模式下，脚本会以红色警示“未落盘”，并要求显式确认口令 `我知道未落盘`（非交互场景可用 `--dry-run-ack` 传入）。
`状态` 命令会读取最近一次 `apply-report.json`，展示 `mode / success / persisted / changed_counts`。

执行 `应用` 时，脚本会先展示四份独立的建议清单：

- 新增建议：每项有序号、技能名、用户需求依据、目标仓/场景依据
- 卸载建议：每项有序号、技能名、已安装定位信息、用户需求依据、目标仓/场景依据
- MCP 新增建议：每项有序号、MCP 名称、用户需求依据、目标仓/场景依据
- MCP 卸载建议：每项有序号、MCP 名称、用户需求依据、目标仓/场景依据

你可以在交互中分别输入技能/MCP 的新增与卸载序号，也可以用 `--add-indexes` / `--remove-indexes` / `--mcp-add-indexes` / `--mcp-remove-indexes` 非交互传入。四份清单独立编号，任一类别的选择不会改变其他清单的序号映射。

如果外层 AI 具备工作区执行能力，最直接的交付方式是让它代理执行本次 run 目录中的 `outer-ai-prompt.md`；要求它先完成 `recommendations.json` 自检，再进入 dry-run。

English aliases：

```powershell
.\skills.ps1 audit-targets init
.\skills.ps1 audit-targets profile-set
.\skills.ps1 audit-targets profile-show
.\skills.ps1 audit-targets profile-structure --profile reports\profile.json
.\skills.ps1 audit-targets add my-repo ..\my-repo
.\skills.ps1 audit-targets scan --target my-repo
.\skills.ps1 audit-targets discover-skills --query "repo governance and agent workflows"
.\skills.ps1 audit-targets status
.\skills.ps1 audit-targets apply-flow --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --dry-run-ack "我知道未落盘"
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes --add-indexes "1,3" --remove-indexes "2" --mcp-add-indexes "1" --mcp-remove-indexes "2"
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

质量门禁脚本（本地/CI 同款）：

```powershell
./scripts/quality/run-local-quality-gates.ps1 -Profile quick
./scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

## MCP 与门禁环境变量

- `SKILLS_MCP_VERIFY_GEMINI_CLI=1|true|yes|on`：启用 Gemini CLI 实机校验（默认关闭，默认走配置态校验）。
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS`：统一设置 `mcp list` 校验超时（秒）。
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_<CLI>`：按 CLI 覆盖超时（例如 `_CLAUDE` / `_CODEX` / `_GEMINI`）。
- `SKILLS_MCP_NATIVE_TIMEOUT_SECONDS`：原生 `claude mcp add/remove` 超时（秒）。
- `SKILLS_MCP_VERIFY_ATTEMPTS`、`SKILLS_MCP_VERIFY_INTERVAL_SECONDS`：跨 CLI MCP 校验的重试次数与重试间隔（秒）。
- `SKILLS_SYNC_MCP_THRESHOLD_MS`：`check-doctor-json.ps1` 中 `sync_mcp` 性能阈值（毫秒，CI 建议 `12000`）。

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
