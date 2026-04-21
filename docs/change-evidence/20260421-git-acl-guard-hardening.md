规则ID=R1,R2,R3,R6,R8
规则版本=project-3.92 / global-9.39
兼容窗口(观察期/强制期)=observe-now / enforce-now
影响模块=scripts/git-acl-guard.ps1
当前落点=git-acl-guard 的 ACL 检测与修复执行链
目标归宿=增强诊断可观测性、降低误修复风险、保持修复语义不变
迁移批次=20260421-git-acl-guard-hardening
风险等级=中
是否豁免(Waiver)=否
豁免责任人=
豁免到期=
豁免回收计划=
执行命令=
1) PowerShell parser parse: scripts/git-acl-guard.ps1
2) ./build.ps1
3) ./skills.ps1 发现
4) ./skills.ps1 doctor --strict --threshold-ms 8000
5) ./skills.ps1 构建生效
6) ./scripts/git-acl-guard.ps1 -GitDir .git -ProbeGitStatus
7) Invoke-Pester -Script tests/Unit/GitAclGuard.Tests.ps1
验证证据=
- 语法解析无错误（exit_code=0）。
- build 成功：Build success: D:\CODE\skills-manager\skills.ps1。
- test 成功：发现列表正常输出（exit_code=0）。
- contract/invariant 成功：doctor --strict 通过（exit_code=0）。
- hotspot 命令返回 0，但日志显示“构建生效部分失败并回滚”，失败项为既有映射问题：
  mapping:manual/write-a-prd、mapping:manual/prd-to-plan（与本次改动文件无直接耦合）。
- 脚本冒烟验证通过：Target=.git, ACL clean, git status probe passed（exit_code=0）。
- 新增单测通过：`GitAclGuard.Tests.ps1`（2/2）。
  - 覆盖 DENY + 非修复模式下 `FailureReason=deny_detected_requires_fix_mode`。
  - 覆盖 `-LightFix -WhatIf` 下 `RepairStrategy=skipped_by_shouldprocess`、`SkippedByShouldProcess=true`、JSON 报告落盘。
供应链安全扫描=N/A（本次仅脚本逻辑调整，未引入新依赖）
发布后验证(指标/阈值/窗口)=建议观察 3 次实际修复运行：
- 外部命令失败日志是否包含 exit_code + output
- JSON 报告是否出现 Before/AfterAclReadErrorCount
- DenyCount<0 目标是否按预期快速失败并给出 FailureReason
- WhatIf/Confirm 预演时是否稳定返回 `skipped_by_shouldprocess` 且保留报告文件
数据变更治理(迁移/回填/回滚)=N/A（无数据结构迁移）
回滚动作=
1) git restore -- scripts/git-acl-guard.ps1
2) 若已提交则使用 git revert <commit>
