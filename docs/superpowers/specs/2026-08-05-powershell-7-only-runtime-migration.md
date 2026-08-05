# PowerShell 7-only Runtime Migration

**TRACK**: `powershell7_runtime_migration`
**STATUS**: `repo_verified`
**RUNTIME_POLICY**: `ps7_only`
**MINIMUM_VERSION**: `7.0`
**RECOMMENDED_BASELINE**: `PowerShell 7.6 LTS`
**LEGACY_RUNTIME_STATUS**: `unsupported`
**TYPED_CORE_PRODUCTION_STATUS**: `not_started`
**P6_ADMISSION_STATUS**: `hold`
**LIVE_ACCEPTANCE_STATUS**: `not_run`

## 1. 目标与决策

skills-manager 的当前 shell runtime、开发入口、生成链、CI、测试和受管子进程统一支持 PowerShell 7。Windows PowerShell 5.1 不再提供 installer fallback、CMD fallback、CI job、parse/plain-object smoke 或当前支持承诺；缺少 `pwsh` 时入口 fail-closed 并给出迁移提示。

这是 compulsory support contraction，替代 runtime 已存在且此前就是 build/test/full gate 的权威路径。它消除的是同一 PowerShell 代码在 5.1/7 之间的 parser、quoting、encoding、native-process、error-flow 和测试分叉，不是把生产 PowerShell 领域逻辑切到 C#。TC1 typed-core 继续 `shadow_only`，TC2/生产集成继续 `not_started`。

本决定不声称微软已停止支持 Windows PowerShell 5.1。微软仍把 5.1 置于 Windows 支持渠道；本项目基于维护成本、AI 修改稳定性和现有消费者事实，自主选择单一 PS7 runtime。

## 2. 支持矩阵

| Surface | 当前合同 | 失败行为 |
| --- | --- | --- |
| `src/*.ps1` / generated `skills.ps1` | `#requires -Version 7.0` | 低版本在解析/运行前拒绝 |
| `build.ps1` / `install.ps1` | PowerShell 7+ | 非 Core/低于 7 或缺少 `pwsh` 时 fail-closed |
| `skills.cmd` | 仅解析 `pwsh.exe` | 返回 `9009`，输出安装提示，不 pause |
| MCP Windows environment wrapper | `pwsh.exe` | 不尝试 `powershell.exe` |
| GitHub Actions / Azure Pipelines / GitLab CI | `pwsh` | 不提供 5.1 job 或 legacy shell |
| Pester/contract tests | 由 PowerShell 7 执行 | 不因缺少 `powershell.exe` 而 skip |
| release/runbook | PS7-only + migration + rollback | 不恢复隐藏 legacy fallback |

PowerShell 7.0 是仓库语法下限，不等于推荐部署版本。运维默认选择官方当前 LTS；本切片复核时为 PowerShell 7.6 LTS。LTS 版本会随时间变化，runbook 的官方 lifecycle 链接是动态复核入口，不能把一次快照硬编码成永久事实。

## 3. 官方依据与采纳决定

- [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6)：采纳 PowerShell 7 跟随 .NET 生命周期、优先当前 LTS 的运行策略。
- [Migrating from Windows PowerShell 5.1 to PowerShell 7](https://learn.microsoft.com/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.6)：采纳 side-by-side 安装、显式 `pwsh` 调用和兼容差异核对。
- [What is Windows PowerShell?](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell?view=powershell-7.6)：保留“项目不支持”与“微软支持渠道”之间的事实边界。

社区实现不决定 runtime support。本迁移不安装 shim、兼容模块、第二 shell resolver 或新的包管理器；已有 `pwsh`、Pester 和 repo-native gate 足以完成。

## 4. 范围与历史边界

### 4.1 当前活跃 write set

- production/source：`src/Version.ps1`、`src/Core.ps1`、`src/Commands/Mcp.ps1`、`build.ps1`、`install.ps1`、`skills.cmd`、generated `skills.ps1`；
- CI/test：三个 CI 文件、PS7 runtime tests、受影响的 subprocess fixtures、quality gate；
- product/planning：根契约、README、PRD、architecture、roadmap、Lean spec、runbook、release template、plan/todo；
- executable governance：本 spec、task manifest、runtime-policy verifier、Pester negatives 和一份 reviewed evidence；
- AI defaults：repo skill override 与经过独立备份的 host-global user instructions。

### 4.2 必须保留

- P0/P1/P2/P3 等历史 spec/manifest 中“当时验证了 5.1”的记录；
- typed-core TC0/TC1 `repo_verified / shadow_only`、TC2 `not_started`；
- P5 5/5 历史状态、P6 hold、M1 collecting 0/10 和 live `not_run`；
- generated bundle 的 deterministic UTF-8 BOM 分发选择。BOM 是 Windows/工具链的编码稳定性合同，不是 5.1 兼容承诺。

### 4.3 明确非目标

- 不批量把所有 PowerShell 重写为 C#/TypeScript/Python/Rust；
- 不把 TC1 candidate 接到 CLI、bundle 或生产 caller；
- 不更改 provider、auth、model、sandbox、session、active profile 或插件状态；
- 不证明所有外部/下游脚本已经完成迁移；
- 不创建 P6 manifest、daemon、database 或第二 runtime resolver。

## 5. AI 可执行任务图

```text
SMV-PS7-001 decision/evidence freeze
  -> SMV-PS7-002 runtime/source fail-closed
     -> SMV-PS7-003 CI/test/skill migration
        -> SMV-PS7-004 product/runbook/release sync
           -> SMV-PS7-005 verifier/full/evidence/Git closeout
```

这些任务按 shared generated/planning seam 串行集成。CI 文件、focused test 转换和双语 README 在 write set 真正互斥时可形成候选并行，但最终 bundle、产品真值、task status、full gate 和 Git index 必须由单 writer 串行完成。不得为了并行而复制 manifest/evidence 或让多个 writer 同时生成 `skills.ps1`。

## 6. 实现合同

1. `#requires -Version 7.0` 同时存在于 source header、build、installer 和 generated bundle。
2. `Resolve-PowerShellExecutable` 只接受 `pwsh`；删除 `CODEX_ALLOW_WINDOWS_POWERSHELL` 与 `powershell.exe` fallback。
3. CMD wrapper 无 `pause`、无 legacy assignment，缺失 `pwsh` 返回可诊断非零码。
4. CI 只运行 `pwsh`；测试不启动或探测 `powershell.exe`，也不把 legacy runtime 缺失记为 N/A 成功。
5. build 继续生成 UTF-8 BOM bundle，并把注释明确为 deterministic distribution choice。
6. 当前产品真源统一使用 `ps7_only`；历史 manifest 不做机械改写。
7. `scripts/verify-powershell-runtime-policy.ps1` 必须 fail-close：版本 floor 漂移、fallback 恢复、CI legacy shell、当前 policy 漂移、历史事实被清空、TC2 越级或 P6 manifest。
8. host-global rule 是跨仓默认 guidance；每个重要仓库仍应在自身 code/CI/verifier 中承接确定性 enforcement。

## 7. 消费者迁移指南

1. side-by-side 安装官方 PowerShell 7，确认 `Get-Command pwsh` 指向预期版本。
2. 将 `powershell.exe -File ...` 改为 `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`。
3. 检查 scheduled task、CI runner、IDE task、CMD/shortcut 和父进程 wrapper，不要只验证交互终端默认 profile。
4. 运行 `pwsh -NoProfile -File ./skills.ps1 --help` 或仓库 gate，确认 `PSEdition=Core`、exit code 和输出合同。
5. 若外部 legacy consumer 暂时不能迁移，在其自身仓库隔离并记录 owner/expires/rollback；不得把 fallback 重新放回 skills-manager 主路径。

## 8. 验证顺序

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
2. focused Pester：runtime policy、compatibility、build/core/package、受影响 subprocess 和 Lean planning
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-powershell-runtime-policy.ps1 -Json`
4. Lean/typed-core planning verifiers，证明 `ps7_only` 与 TC2 `not_started` 同时成立
5. 唯一 full closeout：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`
6. `git diff --check`、`git status --short --branch`、分支/远端 parity

`repo_verified` 只证明同一最终 write set 通过上述仓库门禁；不证明下游 consumer、host fresh-load 或业务 live acceptance。

## 9. 回滚

若迁移导致阻断，优先恢复/安装 PowerShell 7、修调用方或恢复最后已验证发布。代码回滚只能撤销本 manifest 列出的迁移切片，并重新 build/focused/full；不得用环境变量、CMD fallback 或临时 `powershell.exe` resolver 绕过 policy verifier。

host-global instructions 的回滚使用写入前备份，恢复后必须在 fresh task 重新验证加载；当前运行 task 不视为热加载证据。历史 manifest/spec 不参与本切片回滚。

## 10. 完成定义与可声明边界

完成要求：5/5 task done；active source/generated/entry/CI/test 不存在 legacy fallback；product/runbook/release 使用 `ps7_only`；historical evidence 仍可追；runtime verifier 的 current 与 negative cases 通过；Lean/typed-core 状态无越级；唯一 full gate、diff check 和 Git closeout 通过。

允许表述：“skills-manager 当前仓库运行支持已收敛为 PowerShell 7-only，repo-side 门禁通过。”禁止表述：“微软已停止支持 5.1”“所有下游已迁移”“typed core 已替换 PowerShell”“P6/live acceptance 已完成”。
