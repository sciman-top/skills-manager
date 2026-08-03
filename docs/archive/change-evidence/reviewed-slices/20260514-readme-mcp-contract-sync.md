# 2026-05-14 README MCP contract sync

规则ID=R1/R2/R6/R8/E4/E5
规则版本=GlobalUser/AGENTS.md v9.52 + skills-manager AGENTS.md v3.98
兼容窗口(观察期/强制期)=强制期
影响模块=README.md, README.en.md
当前落点=D:\CODE\skills-manager
目标归宿=把已落地的 MCP env contract、weekly `更新 -> 同步MCP` 持久化边界和英文审查命令补回用户入口文档
迁移批次=20260514-readme-mcp-contract-sync
风险等级=低；纯文档变更，不改脚本、配置、auth、provider 或 MCP live state
是否豁免(Waiver)=否
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=git status --short --branch; rg -n "discover-skills|发现新技能|Ensure-PostgresMcpEnvironment|Ensure-GhAuthForGithubMcp|CODEX_GITHUB_PERSONAL_ACCESS_TOKEN|weekly-auto-update|skills-manager-weekly" src scripts tests skills.ps1 skills.json; rg -n "发现新技能|discover-skills|同步MCP|CODEX_GITHUB|POSTGRES|weekly|每周" README.md README.en.md docs/change-evidence/20260509-mcp-env-contract-hardening.md AGENTS.md; git diff --check; rg -n "POSTGRES_CONNECTION_STRING|CODEX_GITHUB_PERSONAL_ACCESS_TOKEN|skills-manager-weekly-update-friday-2000|audit-targets discover-skills" README.md README.en.md src/Commands/Mcp.ps1 src/Commands/AuditTargets.Args.ps1 src/Commands/Utils.ps1 scripts/weekly-auto-update.ps1
验证证据=README.md/README.en.md 已补充 `同步MCP` env preflight、`POSTGRES_CONNECTION_STRING`、`CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`、weekly task 真源链；README.en.md 已补齐 `audit-targets discover-skills`; `git diff --check` exit 0（仅 CRLF 提示，无 whitespace error）; rg 证明新增变量/命令与源码实现存在对应
供应链安全扫描=gate_na; reason=纯文档变更，无依赖或包来源变化; alternative_verification=核对 README 与 src/Commands/Mcp.ps1、src/Commands/AuditTargets.Args.ps1、scripts/weekly-auto-update.ps1 的命令/变量事实; evidence_link=本文件; expires_at=下一次 MCP/审查命令或 README 入口变更
发布后验证(指标/阈值/窗口)=gate_na; reason=纯文档变更，无运行时代码发布; alternative_verification=git diff --check exit 0 + README/source rg contract check; evidence_link=本文件; expires_at=下一次代码或配置变更
数据变更治理(迁移/回填/回滚)=gate_na; reason=不涉及数据结构或迁移; alternative_verification=不适用; evidence_link=本文件; expires_at=下一次数据结构变更
回滚动作=git checkout -- README.md README.en.md docs/change-evidence/20260514-readme-mcp-contract-sync.md
