规则ID=R1,R2,R6,R8
规则版本=project-3.92 / global-9.39
兼容窗口(观察期/强制期)=observe-now / enforce-now
影响模块=skills.json
当前落点=manual import: write-a-prd / prd-to-plan
目标归宿=修复无效 manual skill 路径，恢复构建生效
迁移批次=20260421-manual-import-skill-path-fix
风险等级=低
是否豁免(Waiver)=否
豁免责任人=
豁免到期=
豁免回收计划=
执行命令=
1) ./build.ps1
2) ./skills.ps1 发现
3) ./skills.ps1 doctor --strict --threshold-ms 8000
4) ./skills.ps1 构建生效
验证证据=
- 仅修改 skills.json 两处 skill 字段：
  write-a-prd: write-a-prd -> to-prd
  prd-to-plan: prd-to-plan -> to-issues
- build 成功：Build success: D:\CODE\skills-manager\skills.ps1。
- test 成功：发现列表包含 write-a-prd 与 prd-to-plan（exit_code=0）。
- contract/invariant 成功：doctor --strict 通过（exit_code=0）。
- hotspot 成功：构建生效完成并同步链接；不再出现 manual/write-a-prd、manual/prd-to-plan 导入无效错误。
供应链安全扫描=N/A（仅配置修复，未引入新依赖）
发布后验证(指标/阈值/窗口)=观察 3 次构建生效日志，确认不再出现上述两条 manual 导入错误。
数据变更治理(迁移/回填/回滚)=N/A（无数据结构迁移）
回滚动作=
1) git restore -- skills.json
2) 若已提交则使用 git revert <commit>
