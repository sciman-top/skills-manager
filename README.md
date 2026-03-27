# Skills 管理器（极简版）

目标：用一个中文菜单脚本，完成你最常用的 4 类动作：

1. **添加/删除技能库 URL**（菜单“新增/删除技能库”自动维护 `vendors`）
2. **从技能库里选择启用哪些技能（白名单）**（菜单“安装/卸载”自动写 `mappings`）
3. **构建并生效**（把白名单技能汇总到 `agent/`，并合并 `imports(mode=manual)` 与 `overrides/` 后同步到目标）
4. **手动更新上游**（`git pull` 后重建并生效）

本项目刻意做到：目录少、概念少、可控更新（不做定时自动更新）。

---

## 目录结构

```
repo/
  skills.ps1        # 唯一入口（中文菜单）
  skills.json       # 唯一配置（vendors + 白名单 + link/sync 模式）
  vendor/           # 上游技能库缓存（自动生成）
  agent/            # 最终技能集合（自动生成）
  imports/          # 单技能导入缓存（自动生成）
  overrides/        # 可选：你的覆盖层（同名目录会覆盖上游构建结果）
  .claude/skills    # link/sync 指向 agent/
  .codex/skills     # link/sync 指向 agent/
  .gemini/skills    # link/sync 指向 agent/（如 Gemini 支持）
```

---

## 前置条件

- Windows 10/11
- PowerShell 5.1+（或 PowerShell 7+）
- Git（命令行可用：`git --version`）
- `robocopy`（Windows 自带）

如遇脚本无法运行，可在当前 PowerShell 会话临时放开执行策略：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

## 快速开始（推荐流程）

1) 运行中文菜单：

```powershell
.\skills.ps1
```

可选：加上 `-DryRun` 仅预演（跳过写入/删除/同步/拉取）：

```powershell
.\skills.ps1 -DryRun
```

2) 按菜单顺序执行：

- **1 新增技能库**：输入 URL，自动写入并初始化
- **4 批量安装**：多选要启用的技能（=白名单）
- **6 手动更新**：拉取上游 vendor/imports → 重建 → 同步
- **7 构建并生效**（可选）：重建 `agent/`（含 `imports(mode=manual)` 与 `overrides/`）并让 Claude/Codex 使用
  - 注意事项：手动更新会逐项确认是否丢弃 vendor/imports 的本地改动；仅需本地改动生效时用“构建并生效”

可选命令：
- `.\skills.ps1 发现`：单独列出可用 skills（含已安装标记）
- `.\skills.ps1 发现 -DryRun`：仅预演模式（不会写入/删除/同步/拉取）

3) 隔一段时间手动更新：

- **6 手动更新**：拉取上游 vendor/imports → 重建 → 同步
  - 注意事项：手动更新会逐项确认是否丢弃 vendor/imports 的本地改动；仅需本地改动生效时用“构建并生效”

---

## 场景速查

- 首次安装：
  - 运行 `.\skills.ps1`
  - 依次执行“新增技能库”→“批量安装”→“构建并生效”
- 迁移新机器：
  - 拷贝 `skills.json` 与 `overrides/`（如有）
  - 执行 `.\skills.ps1 构建生效`（必要时先“新增技能库”初始化）
- 权限受限（无法创建链接）：
  - 将 `sync_mode` 改为 `sync`
  - 重新执行 `.\skills.ps1 构建生效`
- 回滚到上次配置：
  - 恢复 `skills.json`（或移除本次 `overrides/` 变更）
  - 执行 `.\skills.ps1 构建生效`

---

## MCP（fetch）统一写法

推荐统一使用同一条启动命令：

```powershell
python -m mcp_server_fetch
```

先安装依赖（一次即可）：

```powershell
python -m pip install --user mcp-server-fetch
```

交互式安装（菜单/命令都可）：

```powershell
.\skills.ps1 安装MCP
```

按提示输入：
- 服务名：`fetch`
- transport：`stdio`（或回车）
- 命令：`python -m mcp_server_fetch`

非交互一行命令：

```powershell
.\skills.ps1 安装MCP fetch --cmd python --arg -m --arg mcp_server_fetch
```

---

## 关于“安装 / 卸载”

- **安装**：在菜单“安装”里勾选技能（写入白名单），然后“构建并生效”。
- **卸载**：
  - vendor：从白名单移除（不删除 vendor 物理目录）
  - manual：删除 `imports` 中的 manual 条目（兼容清理 `manual/<skill>` legacy 目录）
  - overrides：先备份到 `overrides/.bak/`，再删除覆盖层目录

项目默认每次构建前会清空 `agent/`，因此不会残留已卸载技能。
如需彻底清理 overrides 备份，可手动删除 `overrides/.bak/`。

---

## 关于“清理备份”

- 会删除仓库内的 `*.bak.*` 和 `.bak` 目录（排除 `vendor/`、`agent/`、`imports/`、`.git`；包含 overrides 备份）。
- 需输入 `DELETE` 才会执行。

---

## 单技能安装（npx 风格兼容）

默认落入 `imports/`（`mode=manual`），构建后自动生效：

```powershell
.\skills.ps1 add <repo> --skill <name> [--ref <branch/tag>] [--sparse]
.\skills.ps1 npx "skills add <repo> --skill <name> [--ref <branch/tag>] [--sparse]"
.\skills.ps1 npx "add-skill <repo> --skill <name> [--ref <branch/tag>] [--sparse]"
```

菜单入口（一次性输入整行参数）也支持以下形式：

```text
npx skills add <repo> --skill <name> [--ref <branch/tag>] [--sparse]
npx add-skill <repo> --skill <name> [--ref <branch/tag>] [--sparse]
skills add <repo> --skill <name> [--ref <branch/tag>] [--sparse]
```

可选参数：
- `--mode manual|vendor`：默认 manual；vendor 会写入 vendors/mappings（适合想纳入“技能库”生态）
- `--ref`：指定分支或标签（如 `main`、`v1.2.3`）
- `--sparse`：启用 `git sparse-checkout`（适合大仓库只取子目录）
 
单技能安装会自动补全 `owner/repo` 为 GitHub URL；若未指定 `--skill` 或路径不正确，将自动扫描仓库：
- 只有 1 个候选时自动修正并继续
- 多个候选时提示错误并列出候选路径与列举命令

---

## link / sync 模式（自动同步）

在 `skills.json` 中配置：

- Windows 优先 Junction，受限环境用 sync。

- `"sync_mode": "link"`（默认推荐）
  - `.claude/skills`、`.codex/skills`、`.gemini/skills` 通过 **Junction** 指向 `agent/`（如 Gemini 支持）
  - 构建后立即生效；后续 `agent/` 变化对 CLI 等同“自动同步”

- `"sync_mode": "sync"`
  - 构建后用 `robocopy /MIR` 镜像复制到目标目录（含 `.gemini/skills` 如已配置）
  - 适合 link 被安全策略拦截的环境

---

## 更新策略（update_force）

在 `skills.json` 中配置：

- `"update_force": true`（默认）
  - 更新 imports/vendor 时会进入逐项确认，可按 vendor/import 决定是否执行强制清理（`git reset --hard` + `git clean -fd`）
  - 运行“更新”时会先提示是否进入逐项确认
- `"update_force": false`
  - 保留 imports/vendor 的本地改动；如果与上游冲突，可能需要手动处理

---

## 锁定版本（skills.lock.json）

- 生成锁文件：`.\skills.ps1 锁定`
  - 记录当前 `vendors/imports` 的 `repo/ref/commit` 快照到 `skills.lock.json`。
- 严格锁定执行：`.\skills.ps1 构建生效 -Locked` 或 `.\skills.ps1 更新 -Locked`
  - 缺少锁文件、配置与锁不一致、或本地缓存 commit 与锁不一致时会直接失败。
  - `更新 -Locked` 会按锁文件中的 commit 回放工作区，再执行构建生效。
- 升级与预览：
  - `.\skills.ps1 更新 -Plan`：预览 vendors/imports 的当前 commit 与目标 commit（不改动）
  - `.\skills.ps1 更新 -Upgrade`：执行更新，并在成功后自动刷新 `skills.lock.json`

---

## 添加/删除技能库 URL（vendors）

使用菜单即可完成：

- **新增技能库**：输入 Git URL，自动写入 `skills.json` 并初始化
- 也可留空仅初始化已配置的 vendors
- **删除技能库**：选择已配置 vendor 删除，并同步移除相关映射与目录，然后自动构建生效

---

## overrides（可选覆盖层）

如果你想对某个 skill 做定制（例如增加中文说明、加门控），可：

- 在 `overrides/<同名目录>/` 放入你自己的 `SKILL.md` 或其它文件
- 构建时会在最后覆盖到 `agent/` 同名目录

---

## 故障排查

- `mklink` 失败 / link 不生效：把 `sync_mode` 改为 `sync`，再运行“构建并生效”。
- CLI 未立即识别新技能：重启该 CLI 会话通常最稳。
- 可运行 `.\skills.ps1 doctor` 查看环境检查与最近性能摘要（每个流程最近 3 次 `last/avg/samples`）。
- `doctor` 还会做配置风险扫描（重复 `targets.path`、重复 `mappings.to`、映射引用不存在 vendor）并提示性能异常（默认阈值 5000ms）。
- 机器可读输出与低风险自修复：`.\skills.ps1 doctor --json`、`.\skills.ps1 doctor --fix`、`.\skills.ps1 doctor --dry-run-fix`。
- 严格模式：`.\skills.ps1 doctor --json --strict`（有配置风险或性能异常时 `pass=false`，便于 CI 阻断）。
- 性能阈值：`.\skills.ps1 doctor --json --threshold-ms 3000`。
- `doctor --strict` 在命令行会返回非 0 退出码（当前为 `2`），可直接接入 CI。

---

## 构建优化与回滚

- 已启用增量构建缓存：未变化技能目录会跳过复制，减少 `构建生效` 耗时。
- 构建流程带事务回滚：若构建/同步阶段失败，会自动回滚 `agent/` 到构建前状态（同步目标可能仍需手动重建）。

---

## 开发校验（CI 同款）

```powershell
.\tests\check-generated-sync.ps1   # 校验 src/ 与 skills.ps1 产物一致
.\tests\run.ps1                    # 运行 Unit + E2E
```

---

## 过滤语法（安装/卸载/发现命令）

- 多关键词：空格分隔，按 **AND** 过滤（如：`docx pdf`）
- 正则：用 `/.../` 包裹（如：`/docx|pdf/`）
