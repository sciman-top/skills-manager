# Antigravity 与 DSH 受控验收

本记录用于新会话的 `host_loaded` 与 `controlled_live` 验收。以下结果已在本机写入并核对 `filesystem_projected`；不代表宿主已经加载，更不能代替自然使用中的稳定性结论。

## Antigravity

- 配置：`~/.gemini/config/config.json`，原始备份位于同目录 `config.json.bak-20261125-225900-review`。
- 权限预设为 `AGENT_PERMISSION_PRESET_AUTO`；终端沙箱、工作区外访问拒绝、命令自动执行、浏览器 JS 执行与 artifact 审查分别设为收紧值。`globalPermissionGrants` 未放宽。
- 规则 `~/.gemini/GEMINI.md` 与仓内 `rules/global/antigravity/GEMINI.md` 一致；常驻技能目录 `~/.gemini/config/skills` 有 7 个受管条目。
- 安装版本已观察到 `2.35.1`。Windows 上终端沙箱是否真的隔离进程与文件写入尚未证明；需要实际命令与审批记录才能升级结论。
- 一次性验收工作区：`C:\Users\sciman\AppData\Local\Temp\antigravity-acceptance-labels-v1\workspace`。只允许改此目录的 `Labels.ps1`。
- 任务文字：

```text
在已打开的一次性工作区 C:\Users\sciman\AppData\Local\Temp\antigravity-acceptance-labels-v1\workspace 内完成验收任务。
读取该目录的 Labels.ps1，使 Test-Labels.ps1 的 11 个用例全部通过，保留内部空格、首次去重拼写和大小写不敏感语义，并实现 New-LabelFile / Remove-LabelFile 的可观察生成与清理。
只编辑 labels.ps1；不要修改规则、外部文件、宿主配置或仓库；不安装依赖、不提交、不推送。运行 pwsh -NoProfile -ExecutionPolicy Bypass -File .\Test-Labels.ps1，报告命令、退出码和 receipt。
记录 acceptance_probe=labels-v1。
```

- 新任务应读取实际的 `.probe-receipt.json`，并记录命令退出码、11 个用例、生成/清理结果。观察是否命中工作区边界与命令审批，不能仅凭任务文字推断沙箱已生效。
- 回滚：关闭新会话后，仅在明确需要时恢复 `config.json.bak-20261125-225900-review`，再开新会话核对实际配置。一次性验收目录可单独清理。

## DSH

- Desktop 实际版本：`0.2.2-rc.5`。CLI 对 `desktop` profile 返回 `profile "desktop" is managed exclusively by the Electron application`；不从 CLI 绕过该归属边界。
- `~/.dsh/profiles/desktop/cordis.patch.yml` 已有限制瞬时重试，并在 `smart-compaction` 中关闭自动读取截断、旧工具结果遮蔽与自动安全点压缩；保留显式的 `context_status`、`compact_now` 与 `recall_output` 能力预算。
- 配置回滚入口：`cordis.patch.yml.bak-20261125-224515-latency`（重试改动前）与 `cordis.patch.yml.bak-20261125-smartcompaction-safety`（插件安全配置前）。
- `dsh-free-search` 的有效引擎与回退顺序收敛为 `bing`、`ddg`、`ddg-lite`；`fetchProviderTakeover=false`，没有新增 key 或扩大并发。
- 插件保留与观察表：

| 插件 | 决策 | 验收重点 |
| --- | --- | --- |
| `dsh-diff-approval 0.37.5` | 保留 | 一次性修改后的 Keep/Revert 审查可用 |
| `dsh-free-search 0.9.82` | 保留 | 一个明确的无 key 搜索返回有效结果或准确错误 |
| `dsh-better-sidebar 0.32.1` | 保留 | 文件树、编辑器、侧聊不阻塞主窗口 |
| `smart-compaction 0.4.1` | 保留并收紧 | `context_status` 有真实返回；自动压缩不再擅自截断或遮蔽 |
| `dsh-ops 0.5.5` | 暂保留、待实测 | 工具实际可见，无启动错误；载荷较大 |
| `dsh-thinking-levels 4.6.0` | 保留、待观察 | 档位是否被当前 provider 实际使用 |
| `@linxin666/dsh-client-ui-task-board 0.4.21` | 实验性保留 | 任务板是否产生用户可用的真实任务状态 |
| `@deepseek-ai/dsh-experimental-tool-worktree` | 待实测 | 若与新会话冲突，单独审查，不凭标签删包 |
| `@deepseek-ai/dsh-experimental-session-search` | 待实测 | 若与新会话冲突，单独审查，不凭标签删包 |

### 新会话探测

1. 先核对新会话 baseline 含 `Instructions from: ~/.dsh/AGENTS.md`。只有这一步实际出现，规则才算 `host_loaded`。
2. 让宿主列出 `~/.agents/skills` 的 7 个常驻技能，并各执行一次只读核对；目录存在只算文件投影。
3. 调用 `context_status` 并检查实际上下文信息。`compact_now` 只验证压缩服务可调用，不为验收清理无关会话历史。
4. 在一次性文件上修改并检查 `dsh-diff-approval` 的 Keep/Revert 状态，以及 `dsh-ops` 是否成功发布工具。
5. 发一个明确无 key 搜索请求，保留实际结果或错误；不通过制造限流来试重试，不切换账户、IP、UA 或扩大并发。

### DSH CLI 隔离探针

以下命令只让官方 CLI 读取一次性 `$DSH_HOME`，不会自行启动 Desktop。它只验证 CLI 的投影读取与 baseline 渲染，不会加载 Desktop 专用的第三方插件。

```powershell
$tempHome = Join-Path $env:TEMP ('dsh-acceptance-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $tempHome 'profiles\headless') -Force | Out-Null
Copy-Item -LiteralPath 'C:\Users\sciman\.dsh\profiles\headless\package.json' -Destination (Join-Path $tempHome 'profiles\headless\package.json')
New-Item -ItemType Directory -Path (Join-Path $tempHome 'session-probe') | Out-Null
New-Item -ItemType File -Path (Join-Path $tempHome 'session-probe\.git') | Out-Null
Set-Content -LiteralPath (Join-Path $tempHome 'AGENTS.md') -Value '# Probe global instruction'
try {
    $env:DSH_HOME = $tempHome
    Push-Location (Join-Path $tempHome 'session-probe')
    try {
        & 'C:\Users\sciman\AppData\Local\Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd' --profile headless --json 'List the available skills and instructions for this workspace. Then call context_status. Do not modify files.'
        "exit=$LASTEXITCODE"
    } finally { Pop-Location }
} finally {
    Remove-Item Env:DSH_HOME -ErrorAction SilentlyContinue
}
```

临时 `$DSH_HOME` 按官方包说明隔离 harness 私有状态。SQLite 等 CLI 尚未迁移的旧状态与共享 `$DSH_AGENTS_HOME` 仍可能读取本机默认文件；若需完整隔离，必须先按宿主文档把两类状态迁入临时根，不能假设只换 `$DSH_HOME` 就足够。CLI 通过完整基线时，可以验证官方运行时的用户全局与项目指令加载；它仍不能证明默认 `~/.dsh` 桌面配置、桌面第三方插件或自然使用情形已加载。
