规则ID=R1,R2,R3,R4,R6,R7,R8,E5,E6
规则版本=GlobalUser/AGENTS.md v9.39; project AGENTS.md v3.91
兼容窗口(观察期/强制期)=observe
影响模块=src/Commands/AuditTargets.ps1,src/Main.ps1,src/Version.ps1,src/Commands/Utils.ps1,build.ps1,skills.ps1,tests/Unit/AuditTargets.Tests.ps1,tests/E2E/SkillAudit.Tests.ps1,README.md,README.en.md
当前落点=C:\Users\sciman\.config\superpowers\worktrees\skills-manager\skill-audit-targets
目标归宿=AI-orchestrated skill audit workflow
迁移批次=skill-audit-implementation-20260419
风险等级=medium
是否豁免(Waiver)=N/A
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=./build.ps1; Invoke-Pester tests/Unit/AuditTargets.Tests.ps1; Invoke-Pester tests/E2E/SkillAudit.Tests.ps1; ./skills.ps1 发现; ./skills.ps1 doctor --strict --threshold-ms 8000; ./skills.ps1 构建生效
验证证据=build success; AuditTargets unit tests Passed: 10 Failed: 0; SkillAudit E2E Passed: 1 Failed: 0; 发现 listed 132 skills; doctor strict reported "Your system is ready for skills-manager."; 构建生效 built agent/ with 94 skills and completed successfully
供应链安全扫描=recommendation sources are recorded in recommendations.json; script does not perform broad network search; staged diff scanned for credential-like patterns before commits
发布后验证(指标/阈值/窗口)=doctor threshold-ms 8000; latest discover last=1085ms avg=796ms; build_apply_total latest observed successful gate completed in ~9s after cache mirror, below project build_apply_total threshold 240000ms
数据变更治理(迁移/回填/回滚)=adds audit-targets.json schema v1; generated reports under reports/skill-audit/<run-id>; recommendations schema v1; no existing data migration required; apply-report.json records installed items and rollback notes
回滚动作=remove src/Commands/AuditTargets.ps1; remove 审查目标/audit-targets dispatch from src/Main.ps1 and src/Version.ps1; remove help text from src/Commands/Utils.ps1; remove tests/Unit/AuditTargets.Tests.ps1 and tests/E2E/SkillAudit.Tests.ps1; run ./build.ps1; remove audit-targets.json/reports/skill-audit outputs if not needed
