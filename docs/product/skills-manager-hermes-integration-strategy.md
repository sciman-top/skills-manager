# Hermes + Codex 受控协作策略

**状态**：`proposed`（设计输入；未安装、未配置、未验收）
**适用范围**：ChatGPT Desktop、Hermes、Codex Harness、skills-manager 的协作边界
**不构成授权**：本文件不授权安装 Hermes、创建 profile/Gateway/cron、修改 `~/.codex` / `~/.hermes`、投影技能、创建 worktree、合并、推送或发布。

## 1. 决策摘要

目标不是创建“万能 AI 控制面”，而是让每一层只承担一类真值：

```text
ChatGPT Desktop
  产品目标、PRD、架构取舍、风险授权、人工验收
       |
       v
Hermes（外部、可选、常驻控制面）
  任务入口、触发、恢复、任务状态、向执行器发起已批准工作
       |
       v
Codex Harness
  已分配 worktree 中的分析、实现、测试、review、提交
       |
       v
CI + 人工
  merge、release、业务/线上验收

skills-manager（供给与治理侧车）
  source/lock、技能、规则、MCP、projection、receipt、rollback
```

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 是否立即把 Hermes 接入主机 | 否 | Hermes 的 Codex app-server runtime 会管理 Hermes 配置，并可迁移 MCP/plugin、写入 Codex managed block；必须先隔离 POC。 |
| Hermes 的定位 | 一个外部、可选的任务控制面 | 它管理自己的 profile、session、Gateway 与 task state，不应进入 skills-manager。 |
| Codex 的定位 | 唯一代码执行 harness | Codex 在获分配的 worktree 内实现、测试、review；可在互斥 write set 下使用子代理。 |
| skills-manager 的定位 | 技能与规则的受控供应链 | 不变成 task queue、agent runtime、知识库或自学习 daemon。 |
| “自主学习/进化” | 受控技能演进，而非无界自修改 | 只能自动生成 proposal；review、admission、projection、host acceptance 分离。 |
| Hermes 参考仓 | `conditional` 候选 | 只有 POC 产生真实消费者与维护收益后才登记/刷新。 |

OpenAI 官方将 Codex app-server 定位为深度客户端集成，并建议自动化/CI 使用 Codex SDK；因此 Hermes app-server runtime 只能先承担本地 POC 与交互式协作，不能直接成为无人监管的 CI/发布关键路径。见 [Codex App Server](https://developers.openai.com/codex/app-server)。

## 2. 所有权与禁止重叠

| 资产或决策 | 唯一 owner | 允许协作者 | 禁止的交叉控制 |
| --- | --- | --- | --- |
| 产品目标、验收口径、风险授权 | 用户 + ChatGPT Desktop | Hermes/Codex 提供建议 | Hermes/Codex 自行扩大范围或接受业务验收 |
| Hermes profile、memory、session、Gateway、cron | Hermes operator | ChatGPT Desktop 审批 | skills-manager 读写 `~/.hermes` 或管理 Gateway lifecycle |
| Codex auth、plugins、sandbox、`~/.codex` | Codex operator | Hermes 在隔离 POC 中按其官方 runtime 使用 | skills-manager 迁移 MCP/plugin、写入 managed block、替代 Codex 认证 |
| worktree | 单个 task owner | Codex 子代理仅在互斥 write set 下协作 | Hermes、另一个 Codex turn 或其他 framework 并行写同一 worktree |
| 技能 source/lock/mapping/projection receipt | skills-manager | Hermes/Codex 只读消费 | Hermes 自动修改全局受管技能 root |
| merge/release/live acceptance | CI + 人工 | Hermes/Codex 提供证据 | 自动 merge/push/release 取代人工决策 |

### 2.1 单任务工作流

```text
proposed
  -> approved
  -> worktree_allocated
  -> implementing
  -> gate_passed | gate_failed
  -> review_passed | review_failed
  -> human_approved
  -> merged | rejected | rolled_back
```

- Hermes 可以保存上述任务状态，但状态不成为 skills-manager 的运行数据库。
- `worktree_allocated` 前，不允许 Codex 执行写操作。
- `gate_passed` 仅代表仓库门禁；不等于 merge、host loading 或线上验收。
- 任何恢复逻辑都必须恢复同一个任务 owner，不能重新派发一个可能重叠写入的任务。

## 3. Hermes Windows 隔离 POC

### 3.1 同机优先的三档部署

`pwsh` 与“隔离”不是两种安装方式：`pwsh` 只是运行 PowerShell 脚本的宿主；隔离决定 Hermes/Codex runtime 看到哪些文件、配置和凭据。四个工具完全可以位于同一 Windows 工作环境中协作，只是不能把“同一用户目录”误解为安全隔离或自动共享会话。

| 档位 | 位置与用途 | 能协作的内容 | 风险/限制 | 推荐时机 |
| --- | --- | --- | --- | --- |
| A：同机协调模式 | 当前 Windows 用户；Hermes 独立 profile；不启用 Codex app-server runtime | 同一 repo、Git、worktree、项目级技能、任务 brief、人工批准 | Hermes profile 不隔离文件权限；ChatGPT/Hermes/Codex 不自动共享会话或授权 | 日常首选，先获得便利性 |
| B：同机受控 runtime POC | 当前 Windows 用户；单一 POC repo/worktree；当前授权后启用 Hermes Codex runtime | A 的全部能力，加 Hermes 发起 Codex task、查看任务状态 | runtime 可能改变当前用户 Codex managed block、迁移 MCP/plugin 描述；必须备份/比较/可回滚 | A 稳定且用户接受主机配置风险时 |
| C：VM/第二账户探针 | 独立 Windows 用户或 VM；完整 beta runtime 试验 | 与生产环境同样的 Git/远程仓库协作；通过显式同步共享必要 artifact | 需要切换窗口/账户；不会自动看到主用户的 auth/session | 首次验证高风险 migration、复杂 plugin/MCP、或不想污染主配置时 |

因此，VM 或第二账户不是系统长期运行的必需条件，而是第一次验证“会写配置的 beta bridge”时的低成本安全探针。推荐路径是 **A 日常协作 -> B 受控试点 -> C 仅在风险或失败不清楚时使用**；也可以先 C 后 B，取决于用户对主配置变更的容忍度。

同机协作的真实共享面只有：

```text
Git repository + worktree ownership
project documents / reviewed task brief
skills-manager managed skill artifacts
explicit task status or receipt
```

ChatGPT Desktop、Hermes Desktop 与 Codex 的聊天历史、memory、approval、provider/auth 不会因为安装在同一 Windows 用户下而自动统一；每次跨工具 handoff 都必须带上任务 ID、repo/worktree、允许写集、门禁和停止条件。

### 3.2 环境要求

Hermes profile 虽然隔离其 config、session、memory、skills 与 Gateway state，但不是文件系统 sandbox；本地 terminal backend 仍以当前 Windows 用户的权限运行。见 [Hermes Profiles](https://hermes-agent.nousresearch.com/docs/user-guide/profiles)。

档位 A/B 的 POC 环境必须满足：

1. 一份小型测试仓，例如 `D:\CODE\hermes-poc`，且只建立一个测试 worktree。
2. 记录当前用户的 Codex config、MCP/plugin inventory 与受管技能 root 基线；档位 A 不改变它们，档位 B 在当前授权后才允许其发生预期变更。
3. 没有生产 bot token、云凭据、服务器私钥或生产 MCP。
4. 先不启用 Gateway、cron、Kanban 自动分派、自动 merge/push。
5. 先不将 Hermes 指向主 `~/.agents/skills`。

档位 C 额外要求：

1. 独立的 Windows 用户或 VM；不使用日常生产 Codex profile。
2. 只同步 POC Git 仓、测试凭据和必要的无密钥 artifact；不得复制主用户整个 `.codex` / `.hermes` 目录。

上述条件下，四个工具仍可通过同一 Git remote、同一 POC 仓的内容和显式任务 handoff 协作；只是主用户的 session/auth 不自动复制给试验账户。

### 3.3 安装与 profile 初始化

优先使用 [Hermes 官方 Desktop installer](https://hermes-agent.nousresearch.com/docs/getting-started/installation)。如果仅安装 CLI，官方 Windows 命令是：

```powershell
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

该命令只应在档位 A/B 的受控 POC 环境中、经过当前操作者确认后运行；若当前用户不希望其主机安装环境产生任何第三方依赖，则改用档位 C。安装完成后的最小命令序列：

```powershell
hermes doctor
hermes profile create codex-poc --description "Controlled Codex orchestration POC; one worktree; no automatic merge."
hermes -p codex-poc setup
hermes profile show codex-poc
hermes desktop
```

建议的 profile `config.yaml` 基线：

```yaml
terminal:
  backend: local
  cwd: 'D:\CODE\hermes-poc'
  home_mode: auto

skills:
  write_approval: true

memory:
  write_approval: true
```

档位 A 中，`home_mode: auto` 让 Hermes 进程沿用当前 Windows 用户的 CLI 配置，因此便利但不隔离；此档位不启用 Codex runtime。档位 B 中，使用前先备份/比较当前用户 Codex config；若需要更强的 CLI 配置隔离，必须单独初始化该 profile 所需的 Codex/Git/SSH 凭据。`config.yaml` 保存非敏感设置，`.env` 保存密钥。见 [Hermes Configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)。

### 3.4 Codex runtime POC

Hermes 的 `codex_app_server` runtime 是 opt-in beta。启用前在档位 B 或 C 环境完成：

```powershell
codex login
hermes -p codex-poc auth add openai-codex
```

然后备份并比较隔离环境的 Codex config，再通过 Hermes 的 Codex runtime 控件启用。该动作可能写入 Hermes managed block、注册 Hermes MCP callback、迁移 MCP/plugin 描述，并设置 workspace 写入权限；所有这些都必须只发生在隔离环境。见 [Hermes Codex App-Server Runtime](https://hermes-agent.nousresearch.com/docs/user-guide/features/codex-app-server-runtime)。

第一次 runtime POC 使用 `:read-only` 或等效的逐操作审批策略；只在确认 worktree containment 和工具审批路径正确后，才对该 POC worktree 放开 workspace 写入。

## 4. 技能消费策略

### POC：项目级技能优先

第一轮只使用：

```text
<poc-repo>/.agents/skills/
```

Hermes 将项目级技能视为 repo-owned，优先级高于 profile 与 external dirs，且 autonomous curator 不会修改它们。见 [Hermes Skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)。

### 后续：受控共享消费

只有 POC 通过后，才考虑让 Hermes 读取由 skills-manager 生成的共享副本。其 consumer contract 至少包含：

```text
consumer_id
source_fingerprint
target_root
ownership_mode = managed | external
write_policy = read_only | reviewed_write
projection_receipt
rollback_entry
```

不得把主 `~/.agents/skills` 直接配置为可写 `external_dirs`。Hermes 官方明确说明，外部目录不是写保护边界；若 Hermes 可写，它可原地修改发现的技能。共享场景应使用 ACL、独立 Windows 用户或由 skills-manager 生成的只读副本。

## 5. 受控技能演进

“宿主 AI 自主学习、自主创建/修复/优化技能”应被拆成两个不同概念：

| 允许的自动化 | 必须保留的控制 |
| --- | --- |
| 从失败、重复任务、人工反馈中识别技能缺口 | 不把观察写成生产技能或全局 memory 真值 |
| 在项目级 `.agents/skills` 或 sandbox 草拟候选 | 不直接修改 `~/.agents/skills`、`agent/`、vendor/import 或宿主 cache |
| 运行 schema、package safety、路径、内容 hash、受影响测试 | 不允许候选 AI 批准自身、绕过 license/provenance 或跳过 review |
| 生成 proposal、diff、测试结果、风险与回滚建议 | 不允许自动 admission、自动 projection、自动 push/release |
| 在显式 admission 后由 skills-manager 重建与投影 | host_loaded/live_accepted 必须用新会话和真实任务独立证明 |

候选准入状态机：

```text
observed_need
  -> sandbox_candidate
  -> validation_passed | validation_failed
  -> reviewed
  -> admitted
  -> projected
  -> host_loaded
  -> live_accepted
```

每一步的最低证明：

1. `observed_need`：链接到真实失败、重复劳动或经批准的产品需求；没有需求不得创建“猜测性技能”。
2. `sandbox_candidate`：候选位于项目级目录或隔离目录，不能是主受管 root。
3. `validation_passed`：identity、frontmatter、path containment、reparse/special file、package safety、provenance/hash、license 与受影响测试通过。
4. `reviewed`：独立 human/owner 审查 Git diff、行为、权限、外部副作用和回滚；AI 自评不计入此状态。
5. `admitted`：显式变更 `skills.json` / lock / override 或批准的 source；没有明确 source identity 不准入。
6. `projected`：build 与 projection receipt 绑定到 package hash；只改变本次受管对象。
7. `host_loaded`：新宿主会话实际发现预期技能；inventory 或 config 文件不充分。
8. `live_accepted`：真实用户任务显示该技能有效且无不期望副作用。

## 6. 不应加入 skills-manager 的功能

- Hermes Gateway、聊天 UI、cron 注册/删除、Kanban、任务队列、持久 memory、任务恢复 daemon。
- Codex app-server 管理、`~/.codex/config.toml` migration、plugin/MCP 自动迁移、Codex OAuth 或默认权限设定。
- 一键“AI 自我进化”、自动覆盖技能、无审核自动 publish、全局候选市场或第二状态数据库。
- 对技能做宿主语义路由、模型选择、prompt 规划或 agent 任务分解。

这些功能即使可实现，也会同 Hermes/Codex 的已有控制面重叠，削弱 skills-manager 现有的 source/receipt/rollback 深度。

## 7. 进入下一阶段的证据

仅当下列证据同时成立，才能从设计进入代码或主机试点：

1. 隔离 POC 证明 Hermes profile、项目级技能和一个 Codex task 的 write boundary。
2. POC 前后对比证明主日常 `~/.codex`、主 `~/.agents/skills` 和生产凭据未变化。
3. 真实需求显示现有 native projection 不能满足 Hermes 的消费差异。
4. 提议的 consumer interface 可由 source hash、receipt、rollback 充分描述。
5. 用户明确授权后续的仓库代码改动或宿主配置改动；二者是独立授权域。

在这些条件之前，正确状态是 `design_only`，不是 `repo_verified`、`host_loaded` 或 `live_accepted`。
