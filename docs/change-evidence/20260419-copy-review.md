规则ID=R1,R2,R6,R8
规则版本=GlobalUser/AGENTS.md v9.39; project AGENTS.md v3.91
兼容窗口(观察期/强制期)=enforce
影响模块=README.md; README.en.md; CONTRIBUTING.md; SECURITY.md; overrides/README.md; src/Commands/Utils.ps1; skills.ps1
当前落点=D:\OneDrive\CODE\skills-manager
目标归宿=根目录说明文档与 src/ 用户可见帮助文案；skills.ps1 由 build.ps1 生成
迁移批次=20260419-copy-review
风险等级=低
是否豁免(Waiver)=否
豁免责任人=N/A
豁免到期=N/A
豁免回收计划=N/A
执行命令=git status --short; rg; git remote -v; ./build.ps1; ./skills.ps1 发现; ./skills.ps1 doctor --strict --threshold-ms 8000; ./skills.ps1 构建生效; git diff --check
验证证据=./build.ps1 exit=0; ./skills.ps1 发现 exit=0; ./skills.ps1 doctor --strict --threshold-ms 8000 exit=0; ./skills.ps1 构建生效 exit=0; stale-copy rg only matched evidence file; git diff --check exit=0
供应链安全扫描=gate_na: 文案与帮助文本优化未新增依赖；alternative_verification=git diff 人工审查; evidence_link=本文件; expires_at=2026-04-26
发布后验证(指标/阈值/窗口)=本地门禁通过；README 不再引用不存在的 scripts/doctor.ps1；doctor 性能告警 build_agent avg=8076ms > 8000ms 但 --strict 不阻断
数据变更治理(迁移/回填/回滚)=N/A: 未修改数据结构、配置 schema 或锁文件
回滚动作=git restore README.md README.en.md CONTRIBUTING.md SECURITY.md overrides/README.md src/Commands/Utils.ps1 skills.ps1 docs/change-evidence/20260419-copy-review.md

## 依据

- README.md 原内容混用中英文，并包含与当前仓库不一致的治理/doctor 示例。
- 项目级规则要求改动先声明落点、目标归宿和验证方式，并按 build -> test -> contract/invariant -> hotspot 顺序验证。
- `git remote -v` 显示仓库为 `https://github.com/sciman-top/skills-manager.git`。
- `src/Main.ps1` 显示 `doctor` 是 `skills.ps1 doctor` 子命令，不是 `scripts/doctor.ps1`。

## 变更摘要

- 重写中文 README，删除过时治理段，补齐实际快速开始、同步模式、门禁和仓库卫生说明。
- 同步精简英文 README，保持与中文 README 结构一致。
- 将 CONTRIBUTING 的“最小门禁”改为本仓实际门禁命令。
- 删除 SECURITY 中无法执行的占位符 `<security email>` 与 `<N>`，改为可执行的安全报告说明。
- 精简 `overrides/README.md` 与中文帮助文案。
- 运行 `./build.ps1` 重新生成 `skills.ps1`。

## 验证记录

- `./build.ps1`
  - exit_code: 0
  - key_output: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- `./skills.ps1 发现`
  - exit_code: 0
  - key_output: 列出 132 个技能候选，已安装项以 `[*]` 标记。
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - exit_code: 0
  - key_output: `Your system is ready for skills-manager.`
  - warning: `build_agent: last=6169ms avg=8076ms threshold=8000ms`；当前是性能告警，不影响 `--strict`，如需阻断应使用 `--strict-perf`。
- `./skills.ps1 构建生效`
  - exit_code: 0
  - key_output: `构建完成：agent/ (共 94 项技能)`；`=== 构建生效流程完成 ===`
- `rg -n "scripts/doctor|doctor.ps1|HEALTH=GREEN|trigger-eval|promotion|lifecycle|极简版|<security email>|<N>|governance scripts|policy files" README.md README.en.md CONTRIBUTING.md SECURITY.md overrides/README.md src/Commands/Utils.ps1 skills.ps1`
  - exit_code: 1
  - key_output: 无匹配；表示已移除本次审查确认的过时/占位文案。
- `git diff --check`
  - exit_code: 0
  - key_output: 无 whitespace error；仅提示 Windows 工作区会在 Git 触碰时将 LF 替换为 CRLF。

## N/A

- `gate_na` reason: 本次是文案与帮助文本优化，未新增依赖、未改数据结构、未改外部协议。
- `alternative_verification`: 执行固定本地门禁，并人工审查 diff。
- `evidence_link`: docs/change-evidence/20260419-copy-review.md
- `expires_at`: 2026-04-26
