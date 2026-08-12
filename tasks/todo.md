# skills-manager vNext Phase 5 Checklist

**task truth**: `tasks/skills-manager-vnext-phase5.tasks.json`

- [x] `SMV-P5-001` 建立 P5 Adaptive Capability Fabric 规划真源。
- [x] `SMV-P5-002` 实现 task model、schema v3 与 capability DAG。
- [x] `SMV-P5-003` 实现 session 稳定性、preheat recommendation 与 App Server 只读快照。
- [x] `SMV-P5-004` 同步 resident skill、corpus、PRD、架构、路线图和兼容验证。
- [x] `SMV-P5-005` 完成 ordered acceptance 与 truth closeout。
- [x] `SMV-P5-006` 完成字段级 runtime truth merge、App aliases、MCP protocol defaults、复合工具风险聚合、动态 host identity coverage、source/runtime 双证据与 ordered closeout。

## Current boundary

- P0-P4 保持历史 `repo_verified` 真源。
- P5 6/6 已达到 `repo_verified`；current snapshot 动态覆盖和 ordered full gate 已通过，但不自动晋级为 host activation 或 business `live_accepted`。
- Plugin/MCP install、OAuth、host writes、profile/session mutation、ChatGPT web local projection 和 business `live_accepted` 不在自动执行面。
