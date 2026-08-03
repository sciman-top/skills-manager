规则ID=R1,R2,R6,R8
规则版本=GlobalUser/AGENTS.md v9.39; project AGENTS.md v3.91
兼容窗口(观察期/强制期)=observe
影响模块=docs/superpowers/specs,docs/change-evidence
当前落点=D:\OneDrive\CODE\skills-manager
目标归宿=docs/superpowers/specs/2026-04-19-skill-audit-targets-design.md
迁移批次=skill-audit-design-20260419
风险等级=low
是否豁免(Waiver)=N/A
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=Get-Content/rg self-review; git status scoped check
验证证据=rg 未发现未完成标记; 设计文档已明确目标仓配置、推荐文件契约、dry-run/apply 边界、重叠技能只报告策略
供应链安全扫描=gate_na; reason=纯设计文档变更，无依赖或代码执行入口变更; alternative_verification=规格自检和路径范围检查; evidence_link=docs/superpowers/specs/2026-04-19-skill-audit-targets-design.md; expires_at=实现阶段恢复执行
发布后验证(指标/阈值/窗口)=gate_na; reason=未发布运行时代码; alternative_verification=实现阶段运行 build/test/doctor/hotspot; evidence_link=docs/superpowers/specs/2026-04-19-skill-audit-targets-design.md; expires_at=实现阶段
数据变更治理(迁移/回填/回滚)=N/A; 本次仅新增设计文档和证据文档
回滚动作=删除 docs/superpowers/specs/2026-04-19-skill-audit-targets-design.md 与 docs/change-evidence/20260419-skill-audit-design.md
