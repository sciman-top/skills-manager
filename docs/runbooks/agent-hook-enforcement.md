# 宿主 Hook 强制面：生成物守卫与收口守卫

**定位**：说明本仓把哪些"文字约束"下沉成了确定性裁决、覆盖范围到哪、以及怎样验证。

## 1. 一张表：每条约束落在哪一层

| 约束 | 确定性裁决位置 | 覆盖不了的情况 |
| --- | --- | --- |
| 不手改生成物（`skills.ps1`、`skills.lib/`、`rules/global/<host>/`） | `scripts/guard-generated.ps1`，由 `.claude/settings.json` 与 `.codex/config.toml` 的 `PreToolUse` 调用 | 任意程序内部写文件；未建模的写入动词 |
| 生成物必须与其源同批提交 | 同一守卫的 `apply_patch` 分支 | Bash 分支不跨语句聚合（`sed -i skills.lib/x && touch src/y` 会放行） |
| 生成物与源不得漂移 | `.codex/config.toml` 的 `Stop` 钩子跑 `build.ps1 -Check`；CI 的 `-CheckGenerated` | 没有 hooks 的宿主 |
| 完成任务必须给证据 | 同一 `Stop` 钩子检查最后一条回复是否含命令块或验证段落 | 回复里写了"验证"字样但没真跑命令；模型可以用文字满足形式 |
| 新增面须有人标签 | CI `verify-new-surface.ps1` | 唯一权威，无本地等价物 |

原则：**能写成 hook/权限/测试的约束，不写成提示词**。文字规则只留无法机械化的判断。

## 2. 两个脚本

- `scripts/guard-generated.ps1`：两个宿主共用同一个副本（`GeneratedGuardHook.Tests.ps1` 断言仓库里只有一份）。
  `Edit/Write` 事件看 `tool_input.file_path`；`Bash` 事件看重定向目标、写入动词的路径参数、
  `git rm/mv/restore/checkout/reset/clean/stash/apply/switch` 的路径参数；`apply_patch`
  事件看 patch 里的 `*** Add/Update/Delete File:` 行。
- `scripts/guard-stop-verification.ps1`：`stop_hook_active` 为真时立即放行（否则会自我循环），
  否则先跑 `build.ps1 -Check`，失败即以退出码 2 把输出回传给模型；工作区有改动而最后一条
  回复没有命令块/验证段落时同样阻断。

## 3. 接线

Claude Code 与 Codex 的注册形状不同，脚本只有一个：

```toml
# .codex/config.toml —— 命令从 git 根解析，因为 Codex 可能从子目录启动
[[hooks.PreToolUse]]
matcher = "^Bash$"
```

```json
// .claude/settings.json
{ "hooks": { "PreToolUse": [{ "matcher": "Edit|MultiEdit|Write|Bash",
  "hooks": [{ "command": "pwsh -NoProfile -File \"${CLAUDE_PROJECT_DIR}/scripts/guard-generated.ps1\"" }] }] } }
```

Codex 侧首次使用需要在 `/hooks` 审查并信任这些 hook；hook 定义或脚本变化后会重新要求审查。

## 4. 已知限制

- hook 是护栏，不是完整边界（Codex 官方文档同此表述）；最终裁决是 CI。
- 没有 hooks 机制的宿主（当前为 DSH）只能靠沙箱模式与审批策略，不能用本文的守卫。
- `Stop` 钩子有连续阻断上限（Claude `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`，默认 8），
  达到上限后宿主会放行本轮。
- 证据判定是形式检查。它挡的是"没跑任何检查就宣称完成"，不是"证据本身正确"。

## 5. 验证

```powershell
pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/GeneratedGuardHook.Tests.ps1
pwsh -NoProfile -File .\tests\run.ps1 -TestPath tests/Unit/StopGuardHook.Tests.ps1
```

手工核对事件编码时不要用函数间管道：Pester 4 + PowerShell 7 + 中文代码页会把中文参数
转码成乱码。测试改为写 UTF-8 事件文件并用 `-RedirectStandardInput` 送入 stdin。

依据：[Codex hooks](https://learn.chatgpt.com/docs/hooks) · [Claude Code best practices](https://code.claude.com/docs/en/best-practices)（均为 2026-11-06 读取）。
