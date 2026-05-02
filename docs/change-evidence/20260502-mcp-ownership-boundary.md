# 2026-05-02 MCP 托管边界澄清

## 1) 依据
- issue_id: `mcp-ownership-boundary-20260502`
- 背景：
  - `skills-manager` 已被用作 MCP 的统一安装与同步入口。
  - 现场容易把 MCP 落地产物与宿主级非 MCP 设置混为一谈，进而误以为修改 `skills.json` 或执行 `同步MCP` 可以接管如 `windows.sandbox`、model/context、provider/auth 等配置。
- 根因判定：
  1. 现有文档已说明 `skills.json` 是 `mcp_servers` 真源，但没有明确列出“托管什么 / 不托管什么”。
  2. 之前的本机优化同时涉及 MCP 和宿主级设置，若不补边界说明，后续容易再次回到“改对了文件但改错了真源”。

## 2) 变更
- `governed-ai-coding-runtime/rules/projects/skills-manager/{codex,claude,gemini}`
  - 在 `C.1 模块职责` 明确：
    - `skills.json + 同步MCP` 只托管 MCP 服务清单与 MCP 落地产物
    - 非 MCP 宿主级设置必须改宿主配置或各自受控真源
- `README.md`
  - 新增 `MCP 托管边界`
- `README.en.md`
  - 新增 `MCP Ownership Boundary`

## 3) 执行命令与关键输出
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/sync-agent-rules.ps1 -Scope All -Apply`
  - 预期：将控制仓的 `skills-manager` 规则真源同步回目标仓副本
- `rg -n "MCP 托管边界|MCP Ownership Boundary|非 MCP 的宿主级设置|outside the MCP ownership boundary" README.md README.en.md AGENTS.md CLAUDE.md GEMINI.md`
  - 预期：中英文 README 与三份项目规则均可命中边界说明

## 4) 风险分级
- 风险等级：`low`
- 风险点：
  - 仅澄清规则与文档边界，不改变命令行为、配置 schema 或同步逻辑。

## 5) 回滚
1. 回滚规则与说明文件：
   - `git revert <本次提交SHA>`
2. 若只需撤回文档口径：
   - 删除本次新增的边界段落与证据文件，再重新同步规则副本
