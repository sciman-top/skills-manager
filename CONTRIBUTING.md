# Contributing to skills-manager

[English](#english) | [中文](#中文)

## 中文

感谢你参与 `skills-manager`。

### 开发环境

- Windows 10/11
- PowerShell 5.1+，推荐 PowerShell 7+
- Git

### 提交流程

1. Fork 并克隆仓库。
2. 创建分支，例如 `feat/<topic>` 或 `fix/<topic>`。
3. 修改完成后，按固定顺序执行门禁：

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict
./skills.ps1 构建生效
```

4. 提交说明写清楚变更目的、影响范围、验证方式和回滚方式。
5. 发起 Pull Request，并补齐验证证据。

### 仓库约束

- `skills.ps1` 是统一入口。
- `skills.json` 是唯一配置源。
- `agent/` 与 `vendor/` 属于生成/缓存产物，不应作为手工维护入口。
- 本地自定义内容优先放到 `overrides/` 或 `imports/`。
- `.claude/`、`.codex/`、`.gemini/`、`.trae/`、日志、临时快照等本地状态不应进入远端仓库。
- CI 会执行 `scripts/quality/check-repo-hygiene.ps1`，拦截已被跟踪的本地专用文件、调试快照和临时产物。

### 提交建议

- 尽量小步提交，单次提交只解决一个主题。
- 不要把无关格式化、缓存、日志、备份一并带入提交。
- 如果修改影响行为，请在 PR 中说明兼容性风险。

## English

Thank you for contributing to `skills-manager`.

### Development Environment

- Windows 10/11
- PowerShell 5.1+; PowerShell 7+ is preferred
- Git

### Contribution Flow

1. Fork and clone the repository.
2. Create a focused branch such as `feat/<topic>` or `fix/<topic>`.
3. Run the quality gates in the required order after your changes:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict
./skills.ps1 构建生效
```

4. Write commit messages that explain purpose, scope, verification, and rollback.
5. Open a Pull Request and attach verification evidence.

### Repository Constraints

- `skills.ps1` is the unified entry point.
- `skills.json` is the single source of configuration truth.
- `agent/` and `vendor/` are generated or cache-oriented directories and should not be hand-maintained.
- Put local customizations in `overrides/` or `imports/`.
- Local agent state such as `.claude/`, `.codex/`, `.gemini/`, `.trae/`, logs, and temporary probe artifacts should not be committed.
- CI runs `scripts/quality/check-repo-hygiene.ps1` to block tracked local-only agent files, debug snapshots, and temporary artifacts.

### Commit Guidance

- Keep commits small and single-purpose.
- Do not include unrelated formatting, caches, logs, or backups.
- If behavior changes, call out compatibility and migration risk in the PR.
