# 2026-07-06 安装 mattpocock/skills 精选技能

- Rule IDs: `R1`, `R6`, `R8`, `E4`, `E5`
- Risk: `medium`
- Current landing: `skills-manager` 仓库内技能映射与导入源管理
- Target destination: 仅把 `mattpocock/skills` 中高适配、低重叠的两个工程技能纳入当前本地技能栈，并完成本仓门禁验证

## Decision

- 本次正式安装：
  - `research`
  - `grill-with-docs`
- 本次明确不做：
  - 不批量导入 `mattpocock/skills` 全库
  - 不因为同源存在，就卸载现有 `grill-me`、`systematic-debugging`、`test-driven-development`、`code-review-and-quality` 等本地工程技能
- 依据：
  - `research` 适合官方文档优先、社区项目横向对比、最佳实践梳理
  - `grill-with-docs` 适合作为 `grill-me` 的文档化补充，而不是替代品

## Repo Changes

- `skills.json`
  - `mappings` 新增：
    - `research -> research`
    - `grill-with-docs -> grill-with-docs`
  - `imports` 新增：
    - `https://github.com/mattpocock/skills.git` / `skills\engineering\research`
    - `https://github.com/mattpocock/skills.git` / `skills\engineering\grill-with-docs`
- `imports/`
  - 新增手动导入目录：
    - `imports/research/`
    - `imports/grill-with-docs/`
- `agent/`
  - 重建后已生成：
    - `agent/research/`
    - `agent/grill-with-docs/`

## Recommendation Evidence

- 已校验推荐文件为合法 JSON：
  - `docs/change-evidence/20260706-mattpocock-skills-recommendations.json`
- 推荐文件中的目标路径已确认：
  - `skills/engineering/research`
  - `skills/engineering/grill-with-docs`

## Verification

- 预演安装：
  - `./skills.ps1 add mattpocock/skills --skill skills/engineering/research --ref main --mode manual --sparse -DryRun`
  - 结果：通过；确认会导入 1 个技能并触发 `构建生效`
- 正式安装：
  - `./skills.ps1 add mattpocock/skills --skill skills/engineering/research --ref main --mode manual --sparse`
  - `./skills.ps1 add mattpocock/skills --skill skills/engineering/grill-with-docs --ref main --mode manual --sparse`
  - 结果：通过；`mappings` 从 `95 -> 97`，`agent/` 技能数增至 `102`
- 硬门禁：
  - `./build.ps1`
    - `Build success: D:\CODE\skills-manager\skills.ps1`
  - `./skills.ps1 发现`
    - 通过；列表中可见 `research` 与 `grill-with-docs`
  - `./skills.ps1 doctor --strict --threshold-ms 8000`
    - 通过；未阻断
    - 保留性能告警：
      - `build_agent: last=15563ms avg=10591ms threshold=8000ms`
      - `sync_mcp: last=1944ms avg=12602ms threshold=10000ms`
  - `./skills.ps1 构建生效`
    - 通过；输入未变化时正确走缓存跳过重建
  - `./skills.ps1 doctor --strict-perf --threshold-ms 8000`
    - 通过；当前实现未因性能告警阻断
    - 结论：本次无需因性能告警停止提交，后续若要收紧性能治理，应优先重置样本窗口或单独调优 `build_agent` / `sync_mcp` 阈值与耗时来源
- 产物复核：
  - `agent/research/SKILL.md` 存在
  - `agent/grill-with-docs/SKILL.md` 存在

## Rollback

- Repo rollback:
  - 从 `skills.json` 移除本次新增的两条 `mappings`
  - 从 `skills.json` 移除本次新增的两条 `imports`
  - 删除 `imports/research/` 与 `imports/grill-with-docs/`
  - 执行 `./skills.ps1 构建生效`
- Scope boundary:
  - 本次未处理 `imports/drawio-diagram-forge`、`imports/mcp-cli`、`imports/powerpoint-automation` 的既有嵌套仓改动
  - 若后续要提交，应继续把这些无关改动排除在本次变更之外
