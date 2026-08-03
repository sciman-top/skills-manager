规则ID=R1,R2,R6,R8,E5
规则版本=GlobalUser/AGENTS.md v9.53 + skills-manager AGENTS.md v3.98
兼容窗口(观察期/强制期)=强制期
影响模块=docs/EXTERNAL_REFERENCE_REPO_TIERS.md, docs/change-evidence/20260706-external-reference-repo-tiers.md
当前落点=D:\CODE\skills-manager
目标归宿=把 skills-manager 的长期外置参考仓治理与 skills.json 运行真源边界正式落盘，并给出 core/secondary/conditional/discovery-only 分层清单，供后续是否实际克隆、删减或定期刷新时复用
迁移批次=20260706-external-reference-repo-tiers
风险等级=低；纯文档变更，不改 skills.json、imports、vendor、MCP live 配置或已安装技能
是否豁免(Waiver)=否
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=rg -n "external reference|reference repo|参考仓|外置参考|source-strategy|skills.sh|GitHub Trending|official documentation|community" README.md README.en.md docs src -S; powershell 统计 skills.json 中 vendor/import repo 数量与单仓技能分布; git diff -- AGENTS.md CLAUDE.md GEMINI.md README.md README.en.md skills.json audit-targets.json scripts/release/pack-portable.ps1 tests/Unit/Core.Tests.ps1; git diff --check -- docs/EXTERNAL_REFERENCE_REPO_TIERS.md docs/change-evidence/20260706-external-reference-repo-tiers.md
验证证据=新增 docs/EXTERNAL_REFERENCE_REPO_TIERS.md，明确 runtime truth 与 external shelf 的边界、推荐根目录 D:\CODE\external\skills-manager-references、core/secondary/conditional/discovery-only 四层规则、当前 9 vendor / 46 imports / 33 unique import repos / 28 singleton import repos 的判断，以及“暂不从 skills.json 直接删源”的结论；build=test=contract/invariant=hotspot 均按 gate_na 处理（reason=纯文档治理变更，不改脚本、配置、生成链或运行态；alternative_verification=核对文档与当前 skills.json/source-strategy 真相一致，并执行 git diff --check；evidence_link=本文件；expires_at=下一次 reference shelf 真正落地为脚本、配置或运行时自动化时）
供应链安全扫描=gate_na; reason=纯文档变更，无新增依赖、包源或执行入口; alternative_verification=仅核对文档中列举的上游来源与当前配置/公开官方入口一致; evidence_link=本文件; expires_at=下一次实际新增或删除外部 source repo / package source
发布后验证(指标/阈值/窗口)=gate_na; reason=纯文档变更，无发布或 live 配置写入; alternative_verification=git diff --check + 文档内容与现有 source-strategy、skills.json 统计对齐; evidence_link=本文件; expires_at=下一次将该分层策略接入自动刷新脚本或审查门禁
数据变更治理(迁移/回填/回滚)=gate_na; reason=不涉及 schema、迁移、回填或 lock 结构变化; alternative_verification=不适用; evidence_link=本文件; expires_at=下一次 reference governance 进入机器可执行配置
回滚动作=删除 docs/EXTERNAL_REFERENCE_REPO_TIERS.md 和 docs/change-evidence/20260706-external-reference-repo-tiers.md
