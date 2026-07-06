# 2026-07-06 审查并清理 imports 遗留 merge 状态

- Rule IDs: `R1`, `R4`, `R6`, `R7`, `R8`
- Risk: `medium`
- Current landing: `skills-manager` 外层仓的 3 个嵌套 imports 仓处于 dirty 状态
- Target destination: 审查这 3 个遗留改动是否可提交；若属于未完成 merge，则恢复到各自最近已提交快照，避免把无效 merge 状态继续带入外层仓

## Scope

- 审查对象：
  - `imports/drawio-diagram-forge`
  - `imports/mcp-cli`
  - `imports/powerpoint-automation`
- 外层仓状态起点：
  - `git status --short --branch`
  - 结果：仅上述 3 个嵌套仓为 dirty，其余外层索引已清空

## Findings

### 1. 三者都不是“正常已完成改动”，而是 merge in progress

- `imports/drawio-diagram-forge`
  - `git rev-parse --verify MERGE_HEAD` 返回：`88766a03af51c465246d57a5eb11326fb79e4647`
  - `git diff --name-only --diff-filter=U` 显示 15 个未解决冲突
  - `MERGE_MSG` 为：`Merge branch 'master' of https://github.com/aktsmm/agent-skills`
- `imports/powerpoint-automation`
  - `git rev-parse --verify MERGE_HEAD` 返回：`88766a03af51c465246d57a5eb11326fb79e4647`
  - 与 `drawio-diagram-forge` 同属 `aktsmm/agent-skills`，状态一致
- `imports/mcp-cli`
  - `git rev-parse --verify MERGE_HEAD` 返回：`cd420ca862a301755a32ed76d53611bd5e04de30`
  - `git diff --name-only --diff-filter=U` 显示 37 个未解决冲突
  - `MERGE_MSG` 为：`Merge branch 'main' of https://github.com/github/awesome-copilot`

### 2. 直接继续提交风险过高

- `drawio-diagram-forge` / `powerpoint-automation`
  - 当前 `HEAD` 为 `22a5084396fb3c65d96d8f40be44a7efaea48d6e`
  - `git branch -r --contains HEAD` 无输出，说明当前 gitlink 已指向本地私有提交，不是远端可复现公共提交
- `mcp-cli`
  - 当前 `HEAD` 为 `251f416b6d3aa12837b10536e6f9bdd67f482ff7`
  - `git branch -r --contains HEAD` 仅出现在远端特性分支，不在 `origin/main`
- 结论：
  - 若继续在这 3 个嵌套仓内完成 merge 并让外层仓跟随 gitlink 前进，会进一步扩大“外层仓依赖本地私有 commit”的范围
  - 这些改动当前既无验证，也不是完整收口状态，不满足“可提交变更”的最小标准

## Decision

- 不把这 3 个遗留 dirty 状态继续作为“待提交功能改动”处理
- 将其判定为：
  - 上游同步流程中断留下的未完成 merge 状态
  - 应先恢复到最近已提交快照，再视需要另开任务做正式 upstream 同步

## Action

- 执行：
  - `git merge --abort` in `imports/drawio-diagram-forge`
  - `git merge --abort` in `imports/mcp-cli`
  - `git merge --abort` in `imports/powerpoint-automation`
- 结果：
  - 三个嵌套仓均成功退出 merge in progress
  - 未生成新的内层 commit
  - 未更新外层仓 gitlink

## Verification

- 清理后嵌套仓状态：
  - `imports/drawio-diagram-forge` -> `## master...origin/master [ahead 97, behind 138]`
  - `imports/mcp-cli` -> `## main...origin/main [ahead 84, behind 151]`
  - `imports/powerpoint-automation` -> `## master...origin/master [ahead 97, behind 138]`
- 外层仓状态：
  - `git status --short --branch`
  - 结果：`## main...origin/main [ahead 1]`
  - 说明：外层仓已不再受这 3 个 dirty imports 影响

## Gate Status

- `gate_na`
- reason:
  - 本次提交仅新增审查证据文件；未改动 `skills-manager` 源码、配置、脚本或生成逻辑
  - 三个 imports 的实际变化是退出未完成 merge，不涉及外层仓受版本管理的功能代码变更
- alternative_verification:
  - 以 `MERGE_HEAD` 检查、冲突列表、`git merge --abort` 结果，以及清理后的内外层 `git status` 作为验证
- evidence_link:
  - `docs/change-evidence/2026-07-06-audit-import-merge-states.md`
- expires_at:
  - `2026-10-06`

## Rollback

- 若后续确认需要继续做这 3 个导入仓的 upstream 合并：
  - 分别进入对应 imports 仓
  - 基于各自当前 `HEAD` 重新发起受控 merge / rebase
  - 单独完成冲突解决、验证和证据记录
  - 仅在确认新的内层 commit 可被长期保留时，再考虑让外层仓更新 gitlink
