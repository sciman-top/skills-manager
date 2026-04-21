规则ID=R1,R2,R6,R8
规则版本=project-3.92 / global-9.39
兼容窗口(观察期/强制期)=observe-now / enforce-now
影响模块=scripts/sync-git-acl-guard.ps1; tests/Unit/SyncGitAclGuard.Tests.ps1
当前落点=跨仓同步 git-acl-guard 脚本的复制流程
目标归宿=支持 WhatIf/Confirm 安全预演，保持 DryRun 向后兼容，并提供回归测试
迁移批次=20260421-sync-git-acl-guard-shouldprocess
风险等级=低
是否豁免(Waiver)=否
豁免责任人=
豁免到期=
豁免回收计划=
执行命令=
1) Invoke-Pester -Script tests/Unit/SyncGitAclGuard.Tests.ps1
2) ./build.ps1
3) ./skills.ps1 发现
4) ./skills.ps1 doctor --strict --threshold-ms 8000
5) ./skills.ps1 构建生效
验证证据=
- 新增单测通过：SyncGitAclGuard.Tests.ps1（2/2）。
- build 成功：Build success: D:\CODE\skills-manager\skills.ps1。
- test 成功：发现列表正常输出（exit_code=0）。
- contract/invariant 成功：doctor --strict 通过（exit_code=0）。
- hotspot 命令返回 0，但日志显示“构建生效部分失败并回滚”，失败项为既有映射问题：
  mapping:manual/write-a-prd、mapping:manual/prd-to-plan（与本次改动文件无直接耦合）。
供应链安全扫描=N/A（未引入新依赖）
发布后验证(指标/阈值/窗口)=建议观察 3 次同步运行：
- WhatIf 模式下 `scripts/` 与 `git-acl-guard.ps1` 不被创建/覆盖
- 实际执行模式下 `copied/skipped/pending` 计数符合预期
- RepoRoots 和 ScanRoot 两种入口行为一致
数据变更治理(迁移/回填/回滚)=N/A（无数据结构迁移）
回滚动作=
1) git restore -- scripts/sync-git-acl-guard.ps1 tests/Unit/SyncGitAclGuard.Tests.ps1
2) 若已提交则使用 git revert <commit>
