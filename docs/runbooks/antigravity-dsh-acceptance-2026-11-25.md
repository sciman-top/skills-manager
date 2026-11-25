# Antigravity 与 DSH 受控验收

本记录用于新会话的 `host_loaded` 与 `controlled_live` 验收。以下结果已在本机写入并核对 `filesystem_projected`；不代表宿主已经加载，更不能代替自然使用中的稳定性结论。

## 2026-11-26 实际结果

- Antigravity `2.35.1` 的新任务在一次性工作区实际运行了 PowerShell 测试，退出码 `0`，`cases=11 failed=0 generated=true cleanup=true`；只修复该目录的 `Labels.ps1`，未修改真实仓、外部文件或宿主配置。
- 独立读取 `.probe-receipt.json`：`receipt_status=passed`、`hashVerified=true`。这证明本次任务读取了临时目录、执行了命令并在 `Auto` 权限下完成，不证明 Windows 沙箱已完全隔离，也不证明长期稳定性或自然使用体验。
- DSH Desktop `0.2.2-rc.5` 建立了与 `skills-manager` 分离的新会话，工作区为 `C:\Users\sciman\AppData\Local\Temp\dsh-acceptance-a35343a9a5584bfebeb034b5520dac63`。实际读取到 `~/.dsh/AGENTS.md`，列出共享根中的 7 个技能，读取 `probe.txt`，且 `pwd` 与声明工作区一致。
- 首轮会话暴露 `smart-compaction` 组件重复插入：包默认补丁和 profile 都插入 `tool-compact-now`，插件页显示“已关闭”，`context_status` 不存在。移除 profile 的重复插入并重载后，同一会话实际调用 `context_status`，取得 `available=true`、`contextWindow=1048576`、`usedTokens=55297`、`percentUsed=5.3`；`compact_now` 与 `recall_output` 同时出现。这是已修复的配置冲突，不是凭据或权限切换。
- 同一会话实际调用了 `web_search` 一次，返回 9 条结果，但查询只命中 DeepSeek 公司/产品页面，未命中官方仓库或 release，因此没有得到版本结论。这证明免费搜索本次确实有返回，不证明搜索结果质量、缓存命中或自然流量持续稳定。
- DSH 实际警告 `File sandbox enforcement is partial on this host`。核验到当前模式为“工作区内修改”，不能将 UI 标签或配置存在当作完整 Windows 文件沙箱证明。需要更高隔离时，只在一次性目录和 `仅可查看` 模式下验证，不通过制造越界写入或执行恶意命令来试边界。
- 两个 `@deepseek-ai/dsh-experimental-*` 仅列在 `bundles`，没有依赖、安装目录或可观测加载证据。插件页以原生名称显示相应实验功能；没有明确缺口时保持禁用。此前试探都未安装，不能称为“卸载成功”，只记录为从 bundle 声明中移除。
- 启动 Antigravity 时出现已存在的“Antigravity-Proxy 加载状态”弹窗，文案为“API Hook 安装流程已执行”。`app.asar` 中未找到该文案，启动参数里的 `sidecar_sdk/register_loader.js` 只解析 `sidecar_sdk` 导入。因此仍无法将该弹窗归因给某个已识别模块，也不能据此断定它被本轮配置或技能加载触发。不要在来源未确认时改写或停用既有 Proxy；优先排查启动链、已安装扩展和本机注入项，必要时用独立用户目录做对照。
- 安装目录的 `resources/app.asar` 与同目录 `.bak` 内容不同：当前包为 7,143,095 bytes，SHA-256 为 `807C153811F8DFF31901D363B9646A155FA0FF84BC731C62C0073FEA8E25BB15`；`.bak` 为 6,729,546 bytes，SHA-256 为 `9F0AAD7274795D7FBDE04931D96B348DCFC5F3D81D7373E6B70AEB09307442DF`。`dist/preload.js` 由 44,455 增至 248,303 bytes，`dist/ideInstall/wizardPreload.js` 由 879 增至 204,727 bytes；内容含“Antigravity 2.0 Chinese Localization Engine”和页面补丁逻辑，来源仍待确认。不能把当前包视为未修改的官方二进制，也不能用它推断官方权限或沙箱能力。`.bak` 未经来源与版本核对，不作为恢复候选。
- 逐文件核对包内 SHA-256，共 12 项变化，而非仅限两个预加载文件：`wizardHtml.js`、`wizardPreload.js`、`ipcHandlers.js`、`main.js`、`menu.js`、`preload.js`、`provisionSplash.js`、`tray.js`、`updater.js`、`wsl.js`，以及新增的 `chrome-devtools-mcp/LICENSE` 与 `chrome-devtools-mcp/package.json`。这些变化的发布者与维护来源仍未知；保留调查结论为“已修改安装包”，不以 `预加载页面注入` 概括全部差异。

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
- `~/.dsh/profiles/desktop/cordis.patch.yml` 保留有限重试、`smart-compaction` 的策略层和 `ui-chat`/`ui-theme` 的可观测设置；重启后由运行时接管写回的当前文件 SHA-256 为 `91324B70CC38AF9B5DD3F1F5D71DF36802D6C6BDC8E4B896732CE9056958133C`。
- `ui-theme` 保留 `name: "@deepseek-ai/dsh-client-ui-theme"`，否则 `theme` 服务缺失会使 `layout/sidebar` 启动链阻塞；`tool-executor-native` 作为独立顶层 `insert` 存在，不能嵌入已有 `insert` 或 preset registry。
- `agent-preset-registry` 的 `default` 与 `selectedDefault` 均为 `standard`。当前 `web` 行含 `searchProvider: ddg` 与 `fetchProvider: http`，这是 `dsh-free-search` 启用后通过 `settings.mutate` 持久化的运行时接管结果；`ddg` 是该插件注册的 provider id，不等于固定使用 DuckDuckGo 引擎。插件保持启用时不要手删这一行；停用或卸载前才运行该插件提供的 `restore` 清理，再重启 DSH。
- 配置回滚入口：`cordis.patch.yml.bak-20261125-224515-latency`（重试改动前）、`cordis.patch.yml.bak-20261125-smartcompaction-safety`（插件安全配置前）、`cordis.patch.yml.bak-20261126-duplicate-insert`（重复插入修复前）与 `cordis.patch.yml.bak-20261126-pre-search-provider-cleanup`（本轮静态搜索覆盖清理前）。
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

### 2026-11-26 最终 standard 受控验收

- 新建会话实际显示 `标准模式`，落盘会话为 `C:\Users\sciman\.dsh\sessions\--C-Users-sciman-AppData-Local-Temp-dsh-acceptance-a35343a9a5584bfebeb034b5520dac63--\session-ea9c5a68-2119-4b5b-9173-ecc8638bada7\session.v4.jsonl.zstd`；首行 `agentPreset` 为 `"standard"`。
- standard 会话的 `request/header` 工具表没有 `context_status`、`compact_now`、`recall_output`。模型只读调用了三次 `ops_discover_tools`，分别查询相关名称、上下文用量和 `select:context_status`；三次均返回 `No allowed, implemented capability matched`，随后明确报告无法取得 `usedTokens`、`contextWindow` 与 `percentUsed`，没有编造数字。
- 同一会话未调用 `compact_now`、`recall_output` 或 `task`，未读写工作区、安装插件、下载或联网。`ops_discover_tools` 能实际执行，证明 native 工具执行链可用；这不等于 `dsh-ops` 发布了上述三个能力。
- DSH 完整重启后，现有会话可恢复，界面仍显示 `标准模式`，输入区、侧边栏和发送控件正常，未再出现 `theme/layout/sidebar` 启动阻塞。重启只证明本轮配置能被宿主加载并完成受控启动，不证明 `context_status` 等能力长期存在。
- 先前一次 PTC 会话也未提供这三个能力；PTC 结果不能外推为 standard 结果。此前短暂取得的上下文数字属于旧配置/旧会话的瞬态证据，已被本轮 standard 落盘结果取代。
- 本轮重启后未再发起真实搜索请求，因此没有为搜索质量、缓存命中或自然流量建立 `live_accepted`；也未做长期稳定性或 Windows 完整沙箱验收。

### 新会话探测

1. 先核对新会话 baseline 含 `Instructions from: ~/.dsh/AGENTS.md`。只有这一步实际出现，规则才算 `host_loaded`。
2. 让宿主列出 `~/.agents/skills` 的 7 个常驻技能，并各执行一次只读核对；目录存在只算文件投影。
3. 以当前 profile 的真实工具表为准检查上下文能力；若 `context_status`、`compact_now` 或 `recall_output` 不在工具表，不得通过静态配置名称推断其可用。只读落盘记录优先于 UI 标签。
4. 在一次性文件上修改并检查 `dsh-diff-approval` 的 Keep/Revert 状态，以及 `dsh-ops` 是否成功发布工具。若直接点击编辑需要事先的 UI 删除确认，改用只读、可撤销的探针，并在验收记录中写明未观察到的部分。
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
