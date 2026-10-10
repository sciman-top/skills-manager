# 双机规则同步 Runbook

## 1. 目的与适用边界
- 场景：第二台机器（或重置后的机器）上，把全局用户级规则与各目标仓项目级规则同步到与 `origin/main` 一致。
- 不覆盖首次安装（见 `docs/INSTALLATION_AND_MIGRATION.md`）；不复制 `global-rules-*` 命令语法与 schema 细节（见 README「规则审查」节）；宿主技能/MCP 投影不在本篇。
- 本仓 `main` 有 ruleset 强制 required checks：控制仓自身变更走 推分支 → PR → CI 绿 → merge；目标仓按各自 AGENTS.md 的 D 节收口。

## 2. 步骤
1. 控制仓 `git pull origin main`；本地有未提交改动时先按 AGENTS.md B 用 `git diff` 分界，不混入同步。
2. `pwsh -NoProfile -File build.ps1`：物化未跟踪的 `agent/` 运行目录并核对全部生成物（含五份宿主全局规则）无漂移。
3. `.\skills.ps1 global-rules-check`：应 `pass=True, findings=0`；budget 摘要显示最紧宿主的真实压力（Antigravity 12000 字符硬限按字符口径计，其余按 16 KiB/130 行）。
4. `global-rules-plan --out reports/global-rule-projection/plan.json`，再用 plan 输出的 `apply.required_token` 执行 `global-rules-apply`；中断后仅可用同一 plan、receipt、roots 加 `--resume` 续跑。
5. 重跑一次 `global-rules-check` 留证；文件相等只证明 `filesystem_projected`，`host_loaded` 需各宿主新会话探针（方法见第 3 节），不得自动外推。
6. 目标仓逐仓 `git pull`：项目级规则（根 `AGENTS.md` 与各宿主适配器）随仓版本化，无投影步骤。`audit-targets.json` 随控制仓 pull 生效；`audit-targets.local.json` 是本机覆盖，永不提交、永不同步。

## 3. host_loaded 探针（投影后验收）
- 方法：在临时目录对各宿主非交互入口发一个 fresh 单轮会话，禁用工具与文件读取，只问全局协议版本号；答出当前发布版本即为 `host_loaded` 实证，`live_accepted` 仍留待真实任务。宿主无非交互入口、或探针被 auth/模型面阻断时，按 `platform_na` 留痕（原因 / 替代验证=`global-rules-check` 字节一致 / 复测条件），不得把文件相等说成已加载。
- 探针提问：`这是加载核验探针:禁止读取任何文件、禁止使用任何工具。仅凭你本轮已加载的全局指令回答:Universal Agent Protocol 的版本号是多少?只回答版本号,不要解释。`
- Codex：临时目录 `codex exec --skip-git-repo-check --sandbox read-only <探针>`。
- Claude Code：临时目录 `claude -p <探针> --disallowedTools "Read,Grep,Glob,Bash,Write,Edit,WebFetch,WebSearch,Task,NotebookEdit"`；已知阻断：本机 provider key 失效在探针回合发生前报 401，修复 auth 后复测。
- ZCode：临时目录 `node "$env:LOCALAPPDATA\Programs\ZCode\resources\glm\zcode.cjs" -p <探针> --disallowedTools "Read Grep Glob Bash Write Edit WebFetch WebSearch Agent Task"`；已知阻断：CLI 凭据面与桌面端不共享时报 `Model creation failed`（`doctor` 显示运行时 healthy），CLI 侧 `zcode login` 后复测。
- WorkBuddy：临时目录 `CODEBUDDY_CONFIG_DIR=~/.workbuddy-ai "$env:LOCALAPPDATA\Programs\WorkBuddyAI\resources\app.asar.unpacked\cli\bin\codebuddy" -p <探针> --tools ""`；已知阻断：CLI 未登录报 Authentication required，CLI `/login` 后复测。
- Antigravity：无非交互入口，仅真实 GUI 新会话核验。
- 依据：Claude Code best practices（code.claude.com/docs/en/best-practices）、Anthropic context engineering（anthropic.com/engineering/effective-context-engineering-for-ai-agents）、AGENTS.md 规范（agents.md），2026-10-10 读取。

## 4. 证据与回滚
- 留证：apply 的 `receipt.json`（schema v2）与第二次 `global-rules-check` 输出；普通同步不为它新增审计文档。
- 回滚：用户级规则用 `global-rules-rollback --receipt ... --token <receipt.rollback.required_token>` 精确撤销；目标仓规则用 `git revert` 撤销对应切片。
