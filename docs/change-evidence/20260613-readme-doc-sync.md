规则ID=R1,R2,R6,R8,E4,E5
规则版本=GlobalUser/AGENTS.md v9.53 + skills-manager AGENTS.md v3.98
兼容窗口(观察期/强制期)=强制期
影响模块=README.md, README.en.md, CONTRIBUTING.md, overrides/README.md
当前落点=D:\CODE\skills-manager
目标归宿=把用户入口文档、贡献说明和 override 说明同步到当前脚本入口、生成边界、MCP 托管边界、发布安装流程与仓库卫生真相
迁移批次=20260613-readme-doc-sync
风险等级=低；纯文档变更，不改脚本、配置、auth、provider 或 MCP live state
是否豁免(Waiver)=否
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=codex --version; codex --help; .\skills.ps1 --help; .\skills.ps1 一键 --list; .\skills.ps1 审查目标 --help; rg -n "mcp-install|workflow|prune-invalid-mappings|目标列表|发现新技能|audit-outer-ai-prompt|CurrentUser|PortableOnly" src install.ps1 scripts README.md README.en.md CONTRIBUTING.md overrides\README.md; ./build.ps1; ./skills.ps1 发现; ./skills.ps1 doctor --strict --threshold-ms 8000; ./skills.ps1 构建生效
验证证据=README.md/README.en.md 已补齐真实命令矩阵、English alias 覆盖范围、生成边界、portable/install 流程、质量门禁和仓库卫生说明；CONTRIBUTING.md 已改为以 src/skills.json 为真源的贡献流程；overrides/README.md 已补充 audit-outer-ai-prompt override 入口；硬门禁 build/发现/doctor/构建生效 已在本次文档同步后重新执行
供应链安全扫描=gate_na; reason=纯文档变更，无新增第三方依赖或包来源变化; alternative_verification=仅核对 README/CONTRIBUTING/overrides 文案与现有脚本和 help 输出是否一致; evidence_link=本文件; expires_at=下一次命令面、发布流程或托管边界变化
发布后验证(指标/阈值/窗口)=gate_na; reason=纯文档变更，无运行时代码发布; alternative_verification=硬门禁顺序复跑 + help/rg 对齐检查; evidence_link=本文件; expires_at=下一次脚本或 README 入口变化
数据变更治理(迁移/回填/回滚)=gate_na; reason=不涉及数据结构、迁移或回填; alternative_verification=不适用; evidence_link=本文件; expires_at=下一次数据结构变更
回滚动作=还原 README.md、README.en.md、CONTRIBUTING.md、overrides/README.md，并删除 docs/change-evidence/20260613-readme-doc-sync.md
