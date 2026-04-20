规则ID=R1,R2,R6,R8
规则版本=AGENTS.md(project v3.91 / global v9.39)
兼容窗口(观察期/强制期)=直接强制
影响模块=src/Version.ps1, src/Main.ps1, src/Commands/Workflow.ps1, src/Commands/Utils.ps1, build.ps1, README.md, README.en.md, tests/Unit/*
当前落点=命令入口与菜单/帮助分散，缺少可复用的多步骤编排入口
目标归宿=新增“可编排一键工作流”能力，并保持旧命令完全兼容
迁移批次=2026-04-20-batch-1
风险等级=中
是否豁免(Waiver)=否
豁免责任人=
豁免到期=
豁免回收计划=
执行命令=
  1) ./build.ps1
  2) powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script 'tests/Unit/BuildScript.Tests.ps1'"
  3) powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script 'tests/Unit/Workflow.Tests.ps1'"
  4) ./build.ps1
  5) ./skills.ps1 发现
  6) ./skills.ps1 doctor --strict --threshold-ms 8000
  7) ./skills.ps1 构建生效
  8) ./skills.ps1 一键 --list
验证证据=
  - Build: "Build success: D:\OneDrive\CODE\skills-manager\skills.ps1"
  - Unit(BuildScript): Passed 1 / Failed 0
  - Unit(Workflow): Passed 7 / Failed 0
  - Gate(test=发现): exit_code=0，输出技能清单
  - Gate(contract=doctor strict): exit_code=0，"Your system is ready for skills-manager."
  - Gate(hotspot=构建生效): exit_code=0，构建完成并链接 5 个目标目录
  - Workflow(list): exit_code=0，输出 quickstart/maintenance/audit/all 场景与示例
供应链安全扫描=本次未新增外部依赖；N/A
发布后验证(指标/阈值/窗口)=doctor 性能摘要中 workflow_run 指标已出现；后续观察 7 天
数据变更治理(迁移/回填/回滚)=仅脚本逻辑和文档变更，无数据迁移
回滚动作=
  1) 回滚新增命令入口：撤销 src/Version.ps1 与 src/Main.ps1 中 “一键/workflow”
  2) 删除 src/Commands/Workflow.ps1 并从 build.ps1 移除拼装项
  3) 回滚菜单/帮助与 README 变更
  4) 重新执行 ./build.ps1 生成 skills.ps1
