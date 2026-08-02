# skills-manager vNext Phase 3 Checklist

**task truth**: `tasks/skills-manager-vnext-phase3.tasks.json`
**说明**: 本文件只显示状态；依赖、write set、测试、验证与回滚以 manifest 为准。

- [x] `SMV-P3-001` 建立 P3 entry evidence、spec、task truth 与 verifier routing。
- [x] `SMV-P3-002` 实现 official/personal/workspace plugin inventory snapshot adapter。
- [x] `SMV-P3-003` 实现 manifest shape 与 source/version/license lint。
- [x] `SMV-P3-004` 实现 fixture-only Codex skills-only bounded exporter。
- [x] `SMV-P3-005` 实现 static/behavior/model-snapshot 分层 eval。
- [x] `SMV-P3-006` 接入 CLI 并完成 Phase 3 acceptance/compatibility。
- [x] `SMV-P3-007` 完成 full closeout 与 P4 entry gate 裁决。

## Current boundary

- P0/P1：均 9/9 `repo_verified`；历史真源保留。
- P2：7/7 `repo_verified`；单 Git 仓 reviewed rule apply 已完成历史 pilot。
- P1/P2 follow-through：`rule-estate-audit` 已覆盖动态目标、registry drift、common/delta、release 与责任映射；补齐同一 bullet 多标签解析后，9 仓真实复审为 99 covered、0 gap、0 finding。
- Rule Estate reviewed multi-target：已基于用户显式授权执行 2 个全局规则与 9 个项目规则的 reviewed rollout，receipt 为 11/11 applied 且 desired hash 全匹配；Codex fresh-process 为 9/9 `host_loaded`，Claude 为 `platform_na`，`live_accepted=not_run`。
- P3：7/7 `repo_verified`；plugin install、plugin host load 与 live workflow 均未执行；Rule Estate 的 Codex 规则加载验证不外推为 plugin 或业务验收。
- P4：`conditional` 且 entry decision 为 `not_started/deferred`；未创建 P4 manifest。
