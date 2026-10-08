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

可选宿主通过 `--zcode-user-root`、`--antigravity-user-root`、`--workbuddy-user-root` 指定既有用户规则目录。WorkBuddy 默认仅在选定用户根已有 `CODEBUDDY.md` 或 `CODEBUDDY.mdc` 时启用；创建首个文件须显式指定根目录。apply、resume 和 rollback 必须提供与 plan/receipt 相同的根目录。

`rule-estate-audit` 检查 WorkBuddy 时必须显式传入 `--workbuddy-user-root`；该审查入口不自动读取 `CODEBUDDY_CONFIG_DIR` 或当前用户的 `~/.codebuddy`。

投影只写约定的宿主规则文件，保留 source/target hash、token、备份和回滚 receipt。文件相等最多证明 `filesystem_projected`；加载与实际验收仍需独立宿主证据。

项目根 `AGENTS.md` 继续由每个仓库独立维护。Claude 用 `CLAUDE.md` 的 `@AGENTS.md` 引用承接；Antigravity 原生读取 `AGENTS.md`，不要求另建适配器。已有 `.agents/rules/00-project.md` 必须包含合法 `trigger: always_on` 前言，内联内容用 `@[Project contract](../../AGENTS.md)`；裸 `@文件` 只表示路径引用。依据：[Antigravity Rules](https://antigravity.google/docs/rules)（2026-10-08 读取）。WorkBuddy 静态报告列出候选文件、遮蔽和独立目录组，明确未检查的仓外祖先、imports、解析及条件激活，不宣称完整加载。
