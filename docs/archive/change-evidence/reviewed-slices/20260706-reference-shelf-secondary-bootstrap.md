规则ID=R1,R2,R6,R8,E4,E5
规则版本=GlobalUser/AGENTS.md v9.53 + skills-manager AGENTS.md v3.98
兼容窗口(观察期/强制期)=强制期
影响模块=scripts/refresh-reference-repos.ps1, references/reference-shelf.manifest.json, references/README.md, references/updates/README.md, docs/EXTERNAL_REFERENCE_REPO_TIERS.md, references/updates/reference-refresh-20260706-065325.md, references/updates/reference-refresh-20260706-065346.md, references/updates/reference-refresh-latest.md
当前落点=D:\CODE\skills-manager
目标归宿=在已有 core 参考棚基础上补齐 tier 选择入口，真实 bootstrap secondary 参考棚，并证明 custom tier 运行不会覆盖稳定的 core-default latest 指针
迁移批次=20260706-reference-shelf-secondary-bootstrap
风险等级=中；会在 D:\CODE\external\skills-manager-references\secondary 下真实克隆 secondary 参考仓，并调整 refresh 脚本的 latest 更新策略，但不改 skills.json/runtime source truth
是否豁免(Waiver)=否
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=[void][System.Management.Automation.Language.Parser]::ParseFile('D:\CODE\skills-manager\scripts\refresh-reference-repos.ps1',[ref]$null,[ref]$null); .\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos; .\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos; 对 latest 计算 before/after hash + LastWriteTimeUtc 并再次执行 .\scripts\refresh-reference-repos.ps1 -Tier secondary -FetchOnly -SkipDirtyRepos 验证稳定指针不变
验证证据=脚本新增 Tier 入口后 parse-ok；默认 core-default 运行生成 references/updates/reference-refresh-20260706-065325.md，返回 latest_updated=true；secondary bootstrap 运行生成 references/updates/reference-refresh-20260706-065346.md，repo_set=tier-secondary、latest_updated=false，6 个 secondary 仓全部 status=cloned、branch=main、ahead/behind=0 0；本机 secondary 目录现场存在 vercel-agent-skills / obra-superpowers / wshobson-agents / mattpocock-skills / trailofbits-skills / awesome-copilot；再次执行 .\scripts\refresh-reference-repos.ps1 -Tier secondary -FetchOnly -SkipDirtyRepos 前后，reference-refresh-latest.md 的 SHA256 与 LastWriteTimeUtc 均保持不变（unchanged=true），证明 custom tier 运行不会覆盖稳定 latest 指针；manifest 中这 6 个 secondary 仓状态已由 not-cloned 更新为 active
供应链安全扫描=已做来源校验；secondary 仅补齐高复用社区参考仓 vercel-labs/agent-skills、obra/superpowers、wshobson/agents、mattpocock/skills、trailofbits/skills、github/awesome-copilot；无新增 npm/pip/dotnet 依赖安装；不改现有 runtime vendor/import source truth
发布后验证(指标/阈值/窗口)=reference-refresh-latest.md 继续只承载 core-default；secondary 及后续 conditional 刷新仅保留历史摘要；若未来 default_refresh_set 扩大，先更新 manifest，再明确接受 latest 指针语义变化
数据变更治理(迁移/回填/回滚)=不涉及 skills.json schema、lock 或安装态迁移；本次只扩展 reference shelf manifest 状态与脚本参数；回填方式为重新运行 refresh-reference-repos.ps1；回滚时删除 secondary 克隆并还原 manifest/docs/script
回滚动作=git checkout -- scripts/refresh-reference-repos.ps1 references/reference-shelf.manifest.json references/README.md references/updates/README.md docs/EXTERNAL_REFERENCE_REPO_TIERS.md docs/change-evidence/20260706-reference-shelf-secondary-bootstrap.md; 如需回滚物理 secondary 参考棚，再删除 D:\CODE\external\skills-manager-references\secondary\vercel-agent-skills、obra-superpowers、wshobson-agents、mattpocock-skills、trailofbits-skills、awesome-copilot
