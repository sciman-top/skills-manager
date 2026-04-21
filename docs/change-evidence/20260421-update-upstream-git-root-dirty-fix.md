规则ID=R1,R2,R3,R6,R8
规则版本=Project 3.92 / Global 9.39
兼容窗口(观察期/强制期)=observe=2026-04-21~2026-04-28 / enforce=2026-04-29起
影响模块=src/Config.ps1; tests/Unit/ConfigUpdate.Tests.ps1; skills.ps1(构建产物)
当前落点=更新链路 Confirm-UpdateForce 脏检查（manual import 缓存）
目标归宿=仅对“目录自身为 git 仓库根”的缓存启用 dirty 保留策略，避免误跳过强制清理
迁移批次=20260421-update-upstream
风险等级=中
是否豁免(Waiver)=否
豁免责任人=
豁免到期=
豁免回收计划=
执行命令=
- codex --version
- codex --help
- codex status
- ./skills.ps1 更新
- ./build.ps1
- Invoke-Pester -Path tests/Unit/ConfigUpdate.Tests.ps1
- Invoke-Pester -Path tests/Unit/GitLockRecovery.Tests.ps1,tests/Unit/ConfigUpdate.Tests.ps1
- ./skills.ps1 发现
- ./skills.ps1 doctor --strict --threshold-ms 8000
- ./skills.ps1 构建生效
验证证据=
- 修复前：`./skills.ps1 更新` 末尾稳定出现 3 项失败（openpyxl/python-pptx/python-docx，报“缓存目录已存在但不是 git 仓库且 update_force=false”）
- 根因：non-git 缓存目录位于主仓库内，`git status` 回落到父仓导致误判 dirty，被加入 skip-force-clean
- 修复后：`./skills.ps1 更新` 完整通过，输出“更新完成”，不再出现上述 3 项失败
- 单测：Pester 24/24 通过，新增“非 git manual cache 不参与 dirty 检测”回归覆盖
供应链安全扫描=N/A（本次仅 PowerShell 逻辑与测试修复，无新增依赖）
发布后验证(指标/阈值/窗口)=
- 指标：update_total 失败项数量
- 阈值：0
- 窗口：连续 3 次 `./skills.ps1 更新`
数据变更治理(迁移/回填/回滚)=N/A（无数据结构变更）
回滚动作=
- git restore --source=HEAD -- src/Config.ps1 tests/Unit/ConfigUpdate.Tests.ps1 skills.ps1
- 重新执行：./build.ps1 && ./skills.ps1 更新

platform_na=
- reason: `codex status` 在非交互 shell 报 `stdin is not a terminal`
- alternative_verification: 使用 `codex --version` 与 `codex --help` 完成平台最小诊断
- evidence_link: 本文件“执行命令/验证证据”与终端执行日志
- expires_at: 2026-05-21
