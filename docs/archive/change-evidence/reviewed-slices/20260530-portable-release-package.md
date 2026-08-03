规则ID=R1,R2,R6,R8,E5,E6
规则版本=GlobalUser/AGENTS.md v9.53 + skills-manager AGENTS.md v3.98
兼容窗口(观察期/强制期)=observe
影响模块=scripts/release/pack-portable.ps1, install.ps1, README.md, README.en.md, tests/Unit/ReleasePackaging.Tests.ps1
当前落点=D:\CODE\skills-manager
目标归宿=可重建 portable 发布包 + 新机器 CurrentUser/PortableOnly 安装适配入口
迁移批次=2026-05-30 portable release package
风险等级=中
是否豁免(Waiver)=否
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=Invoke-Pester -Script tests/Unit/ReleasePackaging.Tests.ps1; .\scripts\release\pack-portable.ps1 -Version smoke-20260530 -SkipVerification -AllowDirtyWorktree; .\build.ps1; .\skills.ps1 发现; .\skills.ps1 doctor --strict --threshold-ms 8000; .\skills.ps1 构建生效; .\tests\run.ps1
验证证据=定向发布测试 3 passed；smoke zip=D:\CODE\skills-manager\artifacts\release\skills-manager-smoke-20260530-portable.zip sha256=03e8c9dd3b84aa6f9c4cf0324619b5f3fa4afa8d7365cc75e5b6b922f6952085；硬门禁 build/发现/doctor/构建生效通过；全量 Pester unit=380 passed,e2e=11 passed
供应链安全扫描=gate_na; reason=本次未新增第三方依赖; alternative_verification=脚本仅使用 PowerShell/.NET 标准库与既有 git/pwsh; evidence_link=tests/Unit/ReleasePackaging.Tests.ps1; expires_at=下次新增外部依赖前
发布后验证(指标/阈值/窗口)=pack-portable 生成 zip/manifest/SHA256; install.ps1 doctor --strict --threshold-ms 8000 通过
数据变更治理(迁移/回填/回滚)=无数据结构迁移；portable 包不迁移 token、用户目录配置、运行态缓存或目标机状态
回滚动作=删除 install.ps1、scripts/release/pack-portable.ps1、tests/Unit/ReleasePackaging.Tests.ps1，并还原 README/.gitignore 文档改动
