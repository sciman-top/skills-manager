# 2026-05-18 skills/MCP profile governance execution

规则ID=R1/R2/R4/R6/R8/E4/E5/E6
规则版本=GlobalUser/AGENTS.md v9.52 + skills-manager AGENTS.md v3.98
兼容窗口(观察期/强制期)=强制期
影响模块=skills.json, skills.ps1, src/Core.ps1, src/Commands/Install.ps1, src/Commands/Utils.ps1, src/Main.ps1, tests/Unit/Core.Tests.ps1, tests/Unit/UninstallCleanup.Tests.ps1, overrides/custom-*, imports/mcp-cli, imports/md2wechat-lite
当前落点=D:\CODE\skills-manager
目标归宿=按教师课件、Windows 教学软件、公众号/知乎写作、初中物理动画和本机 MCP 使用场景，完成低风险技能/MCP 安装卸载，并把发现的脚本缺口修回源码与测试
迁移批次=20260518-skills-mcp-profile-governance
风险等级=中低；变更通过本仓脚本写入 skills.json、agent 生成产物和 MCP 投影，不修改 auth/provider/model/sandbox，不重启任何宿主进程
是否豁免(Waiver)=否
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A

执行命令=.\skills.ps1 同步MCP; .\skills.ps1 卸载 ui-ux-pro-max --yes; .\skills.ps1 清理无效映射 --yes --no-build; .\skills.ps1 add https://github.com/github/awesome-copilot.git --skill skills/mcp-cli --mode manual --sparse; .\skills.ps1 npx "skills add geekjourneyx/md2wechat-lite@md2wechat-lite"; .\build.ps1; .\skills.ps1 发现; .\skills.ps1 doctor --strict --threshold-ms 8000; .\skills.ps1 构建生效; .\skills.ps1 同步MCP; codex mcp list; git diff --check; powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\Core.Tests.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\UninstallCleanup.Tests.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File tests\check-generated-sync.ps1 -AllowDirtyWorktree
关键输出=构建完成 agent/ 共 92 项技能；发现列表包含 mcp-cli、md2wechat-lite、5 个 custom-* override；doctor --strict 通过，性能项仅告警；同步MCP 写入 9 个目标；codex mcp list 显示 github/microsoft-learn/openaiDeveloperDocs/postgres enabled；Core.Tests.ps1 161 passed；UninstallCleanup.Tests.ps1 4 passed；check-generated-sync 通过；git diff --check 仅 CRLF warning，无 whitespace error

落地变更=卸载功能支持非交互 tokens、--yes、--filter，并补单测；清理无效映射修复 Generic List 赋值错误；add/npx 支持 skills.sh 常见 repo@skill 语法并保持单元素 token 数组稳定；卸载 ui-ux-pro-max；清理失效 marketingskills/social-content 映射；新增 mcp-cli 与 md2wechat-lite；新增 custom-teacher-courseware-ppt、custom-creator-publishing、custom-junior-physics-animation、custom-windows-wpf-teacher-app、custom-powershell-windows-automation
MCP落地=保留并同步 context7/filesystem/github/microsoft-learn/openaiDeveloperDocs/playwright/postgres；Codex 投影中因 Windows taskkill/stdout 风险默认只启用 github、microsoft-learn、openaiDeveloperDocs、postgres；GitHub token 和 Postgres 连接串均由 同步MCP 预检处理，配置文件不写明文 token

未安装候选=firecrawl/canva/md2wechat API MCP
N/A分类=platform_na
reason=本机未检测到 FIRECRAWL_API_KEY、CANVA_API_KEY、CANVA_CLIENT_ID、CANVA_CLIENT_SECRET、MD2WECHAT_API_KEY；强行安装会造成宿主 MCP 启动失败或凭据空转
alternative_verification=安装了无需云凭据的 md2wechat-lite skill；保留现有 browser/playwright/openai/microsoft/github/postgres MCP；后续凭据可用后再通过 .\skills.ps1 安装MCP 写入 skills.json 并运行 同步MCP
evidence_link=本文件
expires_at=设置对应 User/Machine scope API key 后的下一次 MCP 审查

供应链安全扫描=已做来源校验；git ls-remote/clone 成功安装 github/awesome-copilot 的 skills/mcp-cli 与 geekjourneyx/md2wechat-lite 的 skills/md2wechat-lite；未引入 npm/pip/dotnet 新依赖；imports 为本地缓存输入，后续提交前需按仓库策略决定是否纳入版本管理
发布后验证(指标/阈值/窗口)=构建生效 outputs=92, signature=dec5022cb4fe；doctor strict exit 0；codex mcp list enabled=github,microsoft-learn,openaiDeveloperDocs,postgres；窗口=本次同步后即时验证
数据变更治理(迁移/回填/回滚)=skills.json mappings 由失效项清理后增加 mcp-cli/md2wechat-lite，imports 增加对应 manual 条目；生成链通过 build/check-generated-sync 证明 skills.ps1 与 src 一致；回滚可用 git checkout 或逆向脚本命令
回滚动作=git checkout -- README.md skills.json skills.ps1 src/Commands/Install.ps1 src/Commands/Utils.ps1 src/Core.ps1 src/Main.ps1 tests/Unit/Core.Tests.ps1 tests/Unit/UninstallCleanup.Tests.ps1 docs/change-evidence/20260518-skills-mcp-profile-governance.md; 删除 overrides/custom-* 与 imports/mcp-cli imports/md2wechat-lite；或用 .\skills.ps1 卸载 mcp-cli --yes、.\skills.ps1 卸载 md2wechat-lite --yes、重新 add ui-ux-pro-max 后 .\skills.ps1 构建生效 && .\skills.ps1 同步MCP

## 2026-05-18 runtime verification addendum

追加问题=检测已安装 skills/MCP 时，`Test-NetConnection github.com -Port 443` 曾对 20.205.243.166 返回 false，但同轮 `gh api user --jq .login` 返回 sciman-top，说明 doctor 的单一 TCP 探针存在假阴性。
追加修复=新增 `Test-DoctorGitHubConnection`，按 `Test-NetConnection -> gh api user -> git ls-remote` 分层验证 GitHub 可达性；`doctor` 网络错误现在会写入 summary error，成功时记录 method。
追加测试=tests/Unit/DoctorCli.Tests.ps1 新增 TCP 失败但 git ls-remote 成功的 fallback 单测。
追加验证=.\skills.ps1 发现：92 个技能均为 [*]；agent 结构扫描：93 个目录中 92 个真实技能入口可读，唯一 missing_entry 是 .system 系统目录；.\skills.ps1 构建生效：outputs=92 且输入未变化；codex mcp list：github/microsoft-learn/openaiDeveloperDocs/postgres enabled；mcp smoke：github.get_me、microsoft_docs_search、openai_docs_search 均真实成功；.\skills.ps1 doctor --strict --threshold-ms 8000：通过，仅 update_imports/update_total 性能历史告警；DoctorCli.Tests.ps1：6 passed；check-generated-sync.ps1 -AllowDirtyWorktree：通过；git diff --check：仅 CRLF warning。
当前限制=本会话未暴露 postgres/context7/playwright/filesystem 的直接 MCP tool namespace；它们已在 skills.json 与目标配置中同步，Codex 当前只启用 postgres，context7/playwright/filesystem 按现有 Windows stdout/taskkill 风险策略未进入 Codex live list。Postgres 处于 enabled/configured，但未在本会话完成 SQL tool-call 级验证。

## 2026-05-18 MCP projection repair addendum

追加问题=context7/filesystem/playwright 已有 `mcp-node-cache-wrapper.mjs` 包装能力，但 `Convert-McpServersToCodexConfigMap` 在包装前仍按历史 npx/taskkill stdout 风险跳过它们，导致 Codex live list 默认只显示 github/microsoft-learn/openaiDeveloperDocs/postgres。
追加修复=新增 `Should-SkipCodexMcpKnownTaskkillStdoutLeak`：若服务器可转换为 cached Node wrapper，则默认纳入 Codex 投影；只有无法包装且未显式设置 `SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP=1` 时才跳过。对应单测从“默认跳过”更新为“默认通过 cache wrapper 纳入”。
追加验证=不设置 `SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP` 重新执行 `.\skills.ps1 同步MCP; codex mcp list`，Codex 显示 context7/filesystem/playwright/postgres 4 个 stdio MCP enabled，以及 github/microsoft-learn/openaiDeveloperDocs 3 个 HTTP MCP enabled；wrapper 启动探针显示 context7/filesystem/playwright/postgres 均能启动并等待 stdio 输入；Core.Tests.ps1 161 passed；DoctorCli.Tests.ps1 6 passed；.\skills.ps1 发现 92 项均 [*]；.\skills.ps1 doctor --strict --threshold-ms 8000 通过；.\skills.ps1 构建生效 outputs=92；check-generated-sync 通过；git diff --check 仅 CRLF warning。
当前限制=当前已修复 configured/enabled/startup-waiting 层；本 Codex 会话的可调用 MCP tool namespace 仍由会话启动时注入，已启用的新增 stdio MCP 可能需要新会话/新进程才会作为工具命名空间暴露。
