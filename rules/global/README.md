# 全局规则维护

`common.md` 是共同规则的唯一源，包含 `1/A/C/D` 节和独立一行的 `{{PLATFORM}}` 占位符。`platforms/<host>.md` 只保存该宿主的 B 节。发布版本与日期在共同源中维护。

`build.ps1` 确定性生成 Codex、Claude、ZCode、Antigravity 和 WorkBuddy 的宿主文件，同时生成 `skills.ps1`。全部输入先完成结构和预算校验，再写入生成文件；`build.ps1 -Check` 只读检查漂移。

```powershell
./build.ps1
./build.ps1 -Check
./skills.ps1 global-rules-check --json
./skills.ps1 global-rules-plan --out reports/global-rule-projection/plan.json --json
./skills.ps1 global-rules-apply --plan reports/global-rule-projection/plan.json --token <plan-token> --out reports/global-rule-projection/receipt.json --json
```

可选宿主通过 `--zcode-user-root`、`--antigravity-user-root`、`--workbuddy-user-root` 指定既有用户规则目录。WorkBuddy 优先采用环境变量选择的根，否则采用已有 `.workbuddy-ai` 或 `.codebuddy`；选定根目录存在即可启用，不要求预先存在规则文件，也不自动创建根目录。apply、resume 和 rollback 必须提供与 plan/receipt 相同的根目录。

`global-rules-check` 检查 WorkBuddy 时可通过 `--workbuddy-user-root` 显式指定用户根。

投影只写约定的宿主规则文件，保留 source/target hash、token、备份和回滚 receipt。文件相等最多证明 `filesystem_projected`；加载与实际验收仍需独立宿主证据。

预算分两类：16 KiB/130 行及 Antigravity 12,000 字符是本仓采用的保守预算，后者继续兼容未核验的旧版宿主；现有 JSON `host_char_limit` 字段保留兼容此口径，不表示当前产品硬限。Antigravity 当前官方限制为展开内联后单文件 24,000 bytes、全局与 `always_on` 合计 20,000 tokens；静态预算检查不证明展开后的加载总量或未降级。依据：[Antigravity Rules](https://antigravity.google/docs/rules)（2026-10-25 读取）。

项目根 `AGENTS.md` 继续由每个仓库独立维护。Claude 用 `CLAUDE.md` 的 `@AGENTS.md` 引用承接；Antigravity 原生读取 `AGENTS.md`，不要求另建适配器。已有 `.agents/rules/00-project.md` 必须包含合法 `trigger: always_on` 前言，内联内容用 `@[Project contract](../../AGENTS.md)`；裸 `@文件` 只表示路径引用。依据：[Antigravity Rules](https://antigravity.google/docs/rules)（2026-10-08 读取）。WorkBuddy 静态报告列出候选文件、遮蔽和独立目录组，明确未检查的仓外祖先、imports、解析及条件激活，不宣称完整加载。

Claude Desktop 的 Code tab 使用 Claude Code 本机规则；普通 Chat 与 Cowork 的 Customize instructions 是独立 profile 配置，不属于本文件投影。依据：[Claude Code memory](https://code.claude.com/docs/en/memory)、[Claude Desktop](https://code.claude.com/docs/en/desktop)（2026-10-17 读取）。

Codex 的本机 `AGENTS.md`、ChatGPT Personalization 与 Work Web instructions 分属不同配置面，不因本机投影而自动互投。ZCode 仅自动拼接用户全局与当前 Workspace 根 `AGENTS.md`，不展开嵌套规则或 import；子目录的必要边界应在根规则给出按需读取入口。依据：[Codex instructions](https://developers.openai.com/codex/guides/agents-md)、[ZCode Agent](https://zcode.z.ai/cn/docs/agents)（2026-10-25 读取）。
