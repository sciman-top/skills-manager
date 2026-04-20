# Skills Manager Menu Restructure Design

Date: 2026-04-20
Topic: interactive menu information architecture and copy refinement
Status: draft-for-review

## Goal

Reorganize the interactive menu so frequent users can reach common actions faster, while keeping advanced and low-frequency operations structured and discoverable. Tighten menu copy so each item is concise, semantically accurate, and easier to scan.

## Context

Current menu issues observed from source and live interaction review:

- Main menu mixes high-frequency actions, low-frequency maintenance, and domain-specific workflows at the same level.
- Some labels describe implementation details instead of user intent.
- Some labels are longer than needed and force users to parse parenthetical explanations before understanding the action.
- `审查目标` and `MCP` are already domain workflows, but their actions are not consistently surfaced as domain-oriented menu groups.
- `一键工作流` is useful but not a frequent single-step action for experienced users, so it should not consume a prime top-level slot.

Source basis reviewed:

- `src/Commands/Utils.ps1`
- `src/Commands/Workflow.ps1`
- `src/Commands/AuditTargets.ps1`
- `src/Commands/Install.ps1`
- `src/Commands/Mcp.ps1`
- `src/Commands/Update.ps1`
- `README.md`
- `README.en.md`

## User Priority

Confirmed priority for this redesign:

- primary audience: frequent users
- primary need: fast access to single actions
- secondary need: structured grouping for lower-frequency operations

This rules out a fully flat menu and also rules out a purely domain-based top-level structure. The recommended design is a hybrid model.

## Decision

Use a hybrid information architecture:

- Top-level menu is action-first for the highest-frequency operations.
- Domain-heavy workflows get dedicated submenus.
- Low-frequency configuration and maintenance items are grouped into secondary menus instead of competing with common actions.
- Keep depth to at most 2 levels.

## Menu Model

### Top-Level Menu

Recommended top-level structure:

1. 浏览技能
2. 选择安装
3. 粘贴命令导入
4. 卸载技能
5. 重建并同步
6. 更新上游
7. 目标仓审查
8. MCP 服务
9. 技能库管理
10. 更多
98. 帮助
0. 退出

### Why This Top Level Works

- `1-6` are the highest-value direct actions for experienced users.
- `7-9` are domain or management hubs with enough internal complexity to justify submenus.
- `10` intentionally absorbs lower-frequency operational utilities so the main menu stays readable.
- The user can answer “what do I want to do now?” within one scan line.

## Submenu Design

### 目标仓审查

Recommended order:

1. 查看需求
2. 编辑需求
3. 目标仓列表
4. 生成审查包
5. 应用建议（推荐）
6. 查看最近状态
7. 新增目标仓
8. 修改目标仓
9. 删除目标仓
10. 导入结构化需求
11. 初始化审查配置
12. 查看 AI 提示词
13. 编辑 AI 提示词
14. 直接执行建议（高级）
0. 返回

Rationale:

- Put the daily review loop first: inspect context, generate bundle, apply, check status.
- Put target repository CRUD after the common review loop.
- Put initialization and prompt-template operations near the end because they are advanced or infrequent.
- Keep the safe path and advanced path visibly separated.

### MCP 服务

Recommended order:

1. 新增 MCP 服务
2. 卸载 MCP 服务
3. 同步 MCP 配置
0. 返回

Rationale:

- Small domain, no need to over-structure.
- Order follows lifecycle: add, remove, sync.

### 技能库管理

Recommended order:

1. 新增技能库
2. 删除技能库
3. 生成锁文件
4. 打开配置
0. 返回

Rationale:

- This groups source-level and configuration-level management.
- These actions are useful but not frequent enough for the main menu.

### 更多

Recommended order:

1. 一键工作流
2. 自动更新设置
3. 解除关联
4. 清理备份
0. 返回

Rationale:

- These are utility or maintenance actions, not core daily single-step commands.
- `一键工作流` remains available but is no longer competing with direct expert actions.

## Copy Rules

All menu copy should follow these rules:

1. Lead with the result or user intent, not implementation detail.
2. Keep top-level labels short and scannable.
3. Use `动作 + 对象` in submenus whenever possible.
4. Distinguish recommended paths from advanced paths explicitly.
5. Keep wording style consistent within the same menu level.

## Copy Changes

### Main Replacements

- `发现技能` -> `浏览技能`
- `从技能库选择安装` -> `选择安装`
- `命令导入安装` -> `粘贴命令导入`
- `构建并生效` -> `重建并同步`
- `更新上游并重建` -> `更新上游`
- `审查目标` -> `目标仓审查`

### Why These Changes

- `浏览技能` better matches the real behavior: it lists already connected skills rather than discovering external repositories.
- `选择安装` is shorter and sufficient in context.
- `粘贴命令导入` tells the user exactly what input mode is expected.
- `重建并同步` reflects the real action more clearly than the abstract phrase `生效`.
- `更新上游` expresses user intent first; rebuild behavior can remain in supporting text.
- `目标仓审查` is more immediately understandable as a workflow hub.

## Parenthetical Guidance Policy

The current menu often relies on long parentheses. The redesign should reduce this and keep only essential hints.

Recommended pattern:

- Top-level menu: short label first, brief hint only if needed.
- Submenu items: no long process explanation unless ambiguity would remain without it.
- Detailed behavior should move to help text or confirmation preview instead of menu rows.

Examples:

- Keep: `应用建议（推荐）`
- Keep: `直接执行建议（高级）`
- Remove from top level: long workflow summaries such as `需求 / 目标仓 / 审查包 / 自检后 dry-run / 按原序号选择增删`

## Behavior Boundaries

This redesign is copy and navigation focused. It should not change command semantics:

- Existing command handlers remain the source of truth.
- Existing CLI aliases remain valid.
- Existing `审查目标` and `workflow` implementations remain behaviorally compatible.
- Only menu grouping, menu labels, and related help text should change in this phase.

## Help Text Strategy

The help output should mirror the new structure:

- Present the recommended top-level workflow first.
- Group commands by domain instead of listing everything in one undifferentiated block.
- Keep detailed notes where semantics are subtle, especially for:
  - `add` without `--skill`
  - `重建并同步`
  - `更新上游`
  - `目标仓审查`
  - `应用建议（推荐）` vs `直接执行建议（高级）`

## Implementation Scope

Files expected to change in the implementation phase:

- `src/Commands/Utils.ps1`
- `src/Commands/Workflow.ps1`
- `README.md`
- `README.en.md`
- tests that assert menu/help copy

Generated output to rebuild:

- `skills.ps1`

Likely tests to update or extend:

- `tests/Unit/AuditTargets.Tests.ps1`
- `tests/Unit/Workflow.Tests.ps1`
- any tests asserting exact menu/help text

## Verification Plan

Implementation should verify:

1. Main menu ordering matches the approved design.
2. Submenus reflect the approved grouping and wording.
3. Help text is updated to the same terminology.
4. Existing command routing still works.
5. Generated `skills.ps1` stays in sync with `src/`.

Project gate order remains:

1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`

Known platform note:

- `codex status` returned `stdin is not a terminal` during non-interactive verification. This is `platform_na` for status capture and does not affect menu redesign semantics.

## Risks

- Users familiar with old numbering may need brief adaptation.
- Renaming labels without preserving the old command names in documentation could create confusion.
- If help text is not updated alongside menus, terminology drift will make the UI feel inconsistent.
- Overusing parentheses again in the new menu would erase most of the usability gain.

## Rollback

Rollback is straightforward:

- restore previous menu/help text in `src/Commands/Utils.ps1`
- rebuild `skills.ps1`
- restore any updated tests to prior expectations

No runtime data migration is involved.

## Recommendation Summary

Recommended final direction:

- Use a hybrid menu model.
- Keep expert actions direct on the main menu.
- Move domain workflows and low-frequency utilities into structured submenus.
- Shorten labels to intent-first wording.
- Keep detailed process explanation in help text, not in the main menu rows.
