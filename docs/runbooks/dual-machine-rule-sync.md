# 双机开发与规则同步 Runbook

## 1. 目的与适用边界
- 场景：两台电脑维护同一仓库时安全同步代码与提交；第二台机器（或重置后的机器）同步全局用户级规则与各目标仓项目级规则。
- 不覆盖首次安装（见 `docs/INSTALLATION_AND_MIGRATION.md`）；不复制 `global-rules-*` 命令语法与 schema 细节（见 README「规则审查」节）；宿主技能/MCP 投影不在本篇。
- 本仓 `main` 有 ruleset 强制 required checks：控制仓自身变更走 推分支 → PR → CI 绿 → merge；目标仓按各自 AGENTS.md 的 D 节收口。

## 2. 双机普通开发与 PR 收口

本仓在两台电脑上按同一条顺序维护：`status → fetch → review → integrate → work → focused verify → commit → fetch → review → integrate → final verify → push → post-push fetch/status`。每台电脑都要实际整合已推送的远端提交；`fetch` 只更新远端引用，不改变当前分支或工作树。未推送到远端的另一台电脑本地提交，`fetch` 无法发现。

1. 每次开始或换电脑续作，先执行 `git status --short --branch`，识别并保留本地未提交/未跟踪改动；来源或归属不明时先停下划分，不 stash、reset 或顺手纳入本任务。
2. 执行 `git fetch origin`，再看状态、远端独有提交及完整文件范围：

   ```powershell
   git status --short --branch
   git log --oneline HEAD..origin/main
   git diff --name-status HEAD...origin/main
   ```

   在干净的 `main` 上，审查通过后用 `git merge --ff-only origin/main` 整合。任务分支先审查 `origin/main` 自分叉以来的提交与文件，再用 `git merge --no-edit origin/main` 整合；有冲突、漂移或归属不明的提交时保留现场并报告 `integration_blocker`，不强推或重写他人历史。
3. 新任务从同步后的 `main` 建独立 `codex/<task>` 分支。两台电脑上的独立任务使用不同分支；同一任务换电脑时，先在上一台提交并推送，再在另一台 fetch、审查并整合该任务分支后续作。这样避免不同任务提交进入同一 PR。
4. 实现后按改动风险运行最低充分 focused 验证；提交前检查 `git status`、`git diff --check`、工作区完整 diff 和显式暂存路径，确认每个变更都属于当前任务后再 commit，不用 `git add -A`。
5. commit 后再次 `git fetch origin`，检查 `origin/main` 与同名远端任务分支的新提交/文件范围；如同名远端任务分支已存在，也核对 `git log --oneline HEAD..origin/<branch>` 和 `git diff --name-status HEAD...origin/<branch>`。审查并整合适用更新。若整合改变了本任务代码，再做对应 focused 验证；随后执行 final verify。
6. 只 push 当前任务分支；新分支首次推送用 `git push --set-upstream origin HEAD`。push 后执行：

   ```powershell
   git fetch origin
   git status --short --branch
   git rev-list --left-right --count "HEAD...@{u}"
   ```

   `0 0` 且工作区符合预期，才证明本机提交与该分支远端一致。创建或审查 PR 前核对本任务完整提交和文件清单：

   ```powershell
   git log --oneline origin/main..HEAD
   git diff --name-status origin/main...HEAD
   ```

   PR 创建后、请求审查前再用 `gh pr view <number> --json commits,files,baseRefName,headRefName` 核对服务端提交与文件清单。若 PR 混入其他任务，先从 `origin/main` 建干净分支，只挑入本任务提交并重新验证；已合并 PR 的历史不可由后续本地同步抹除，应准确披露并保留并发工作。
7. PR 合并后，在每台需要更新的电脑上先确认干净，再切到 `main` 并执行 `git status --short --branch`、`git fetch origin`；审查 `git log --oneline HEAD..origin/main` 和 `git diff --name-status HEAD...origin/main` 后，再 `git merge --ff-only origin/main`。最后检查 `git status --short --branch` 及 `git rev-parse HEAD` 与 `git rev-parse origin/main` 相等；到这一步远端更新才落盘并在该电脑的工作树生效。

## 3. 全局规则同步步骤
1. 按第 2 节先确认控制仓工作区干净，`fetch` 并审查远端改动，再整合 `origin/main`；不以 `git pull` 跳过 review。
2. `pwsh -NoProfile -File build.ps1`：物化未跟踪的 `agent/` 运行目录并核对全部生成物（含五份宿主全局规则）无漂移。
3. `.\skills.ps1 global-rules-check`：应 `pass=True, findings=0`；budget 摘要显示受管源文件的保守预算压力（Antigravity 保留 12000 字符旧版兼容预算，其余按 16 KiB/130 行；不是当前宿主完整加载预算，详见 `rules/global/README.md`）。
4. `global-rules-plan --out reports/global-rule-projection/plan.json`，再用 plan 输出的 `apply.required_token` 执行 `global-rules-apply`；中断后仅可用同一 plan、receipt、roots 加 `--resume` 续跑。
5. 重跑一次 `global-rules-check` 留证；文件相等只证明 `filesystem_projected`，`host_loaded` 需各宿主新会话探针（方法见第 4 节），不得自动外推。
6. 模型编排投影核验：`pwsh -NoProfile -File src/model-orchestration/Set-ModelPreset.ps1 -Action Verify` 应 `status=pass, issues=[]`；仅子代理面漂移时 `Apply -SubagentsOnly` 修复并留 receipt。父根标量（`model`/`review_model`/`model_reasoning_effort`/`model_verbosity`）与模型目录归本机操作者及宿主配置工具所有：Plan 报 `config.toml` 父根待写时只记录、不 Apply；宿主配置正被外部进程活跃改写时暂停一切宿主写入（边界详见 `src/model-orchestration/AGENTS.md`）。
7. 目标仓逐仓按第 2 节的 `status → fetch → review → integrate` 同步：项目级规则（根 `AGENTS.md` 与各宿主适配器）随仓版本化，无投影步骤。`audit-targets.json` 随控制仓提交生效；`audit-targets.local.json` 是本机覆盖，永不提交、永不同步。
   当前本机目标为 `D:\CODE` 下除 `external` 外的八个项目。缺失的历史目录保留登记但默认禁用，其他电脑确有该仓时用本地覆盖显式启用；新增或改名目录须审查登记差异，不能把不存在的旧路径当作扫描覆盖。

## 4. host_loaded 探针（投影后验收）
- 方法：优先使用当前宿主支持的来源列表、规则面板或 prompt-input 诊断，在新 run/workspace 核对实际路径及所需内容。证据只支持其观察范围：全局文件加载不证明项目链、条件规则、完整内联内容或未截断；`live_accepted` 仍需真实任务。
- 版本号探针仅作低成本补证：在临时目录对可用非交互入口发 fresh 单轮会话，禁用工具与文件读取，只问全局协议版本号；答对只证明版本标识可见，不能单独断言完整 `host_loaded`。宿主无可观察入口、或被 auth/模型面阻断时按 `platform_na` 留痕（原因 / 替代验证=`global-rules-check` 字节一致 / 复测条件），不为获取证据改账号、重启宿主或重复重试。
- 探针提问：`这是加载核验探针:禁止读取任何文件、禁止使用任何工具。仅凭你本轮已加载的全局指令回答:Universal Agent Protocol 的版本号是多少?只回答版本号,不要解释。`
- Codex：先用 `codex --version`、`codex debug --help` 与 `codex debug prompt-input --help` 核对当前入口；支持时在目标仓或授权临时目录执行 `codex debug prompt-input`，检查 JSON 中的实际指令内容，不公开完整 prompt 或凭据。当前流程使用该诊断，不另发模型请求；若入口不可用则记录 `platform_na`。普通 `--sandbox read-only` 与提示词均不能强制禁用文件读取或工具，不将其当作无工具探针的隔离保证。
- Claude Code：临时目录 `claude -p <探针> --disallowedTools "Read,Grep,Glob,Bash,Write,Edit,WebFetch,WebSearch,Task,NotebookEdit"`；已知阻断：本机 provider key 失效在探针回合发生前报 401，修复 auth 后复测。
- ZCode：当前入口 `node "$env:LOCALAPPDATA\Programs\ZCode\resources\glm\zcode.cjs" --help` 在 2026-10-25 成功（本机 App 3.16.3），列有 `-p`、工具禁用和 `--mode`，未验证无需模型请求的加载诊断。确需模型补证时在临时目录用当前 help 支持的参数禁用工具，并显式选择只读任务所需权限模式。历史的 `Model creation failed`、`无法定位 CLI ZCode Built-in Provider Config` 只作排障线索，不认定为当前故障；登录或 provider 修复属于独立授权范围。
- WorkBuddy：无扩展名入口是 Node 脚本，使用 `node "$env:LOCALAPPDATA\Programs\WorkBuddyAI\resources\app.asar.unpacked\cli\bin\codebuddy" --help` 核对入口。2026-10-25 国际版 App 5.8.4 实测退出码 1、`Cannot find module '../dist/codebuddy'`，按 `platform_na` 记录，替代验证为 `global-rules-check` 字节一致；可用 CLI 恢复或现有 GUI 提供来源证据后复测，不以 `--version`、空输出或其他版本的 CLI 代替当前执行面验收。需要显式 root 时使用 PowerShell 进程环境变量并在 `finally` 恢复，不使用 POSIX `NAME=value command` 写法。
- Antigravity：本轮仅确认本机 App 2.26.0 安装版本，未验证可用的非交互加载诊断；优先用 GUI 新会话的规则来源面板核验。当前官方文档已区分 App、CLI 与 IDE/extension 执行面，不将某个执行面缺少入口推广为整个产品无 CLI；不得为核验自动启动或重启 GUI。
- 依据：[Codex instructions](https://developers.openai.com/codex/guides/agents-md) 与本机 `codex-cli 0.159.2` help（2026-10-25）；其余宿主入口按当前安装包与 help 核对，不把历史已知故障视为当前探针结果。

## 5. 证据与回滚
- 留证：apply 的 `receipt.json`（schema v2）与第二次 `global-rules-check` 输出；普通同步不为它新增审计文档。
- 回滚：用户级规则用 `global-rules-rollback --receipt ... --token <receipt.rollback.required_token>` 精确撤销；目标仓规则用 `git revert` 撤销对应切片。
