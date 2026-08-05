# Typed-core Operation Contract Shadow PoC

**TRACK**: `typed_core_shadow_poc`
**BASE_PHASE**: `P5`
**TC0_STATUS**: `repo_verified`
**TC1_STATUS**: `repo_verified`
**TC2_STATUS**: `not_started`
**TC3_STATUS**: `conditional`
**POWERSHELL_RUNTIME_STATUS**: `authoritative`
**TYPED_CORE_MODE**: `shadow_only`
**PRODUCTION_INTEGRATION_STATUS**: `not_started`
**P6_ADMISSION_STATUS**: `hold`
**LIVE_ACCEPTANCE_STATUS**: `not_run`
**日期**: 2026-08-05

## 1. 目标与产品增量

本切片把 M0.3 的条件性技术路线推进到一个可删除的真实 PoC：用 C#/.NET 对 `OperationPlan/Receipt v1` 做只读合同验证，与当前 PowerShell validator shadow 对比。它回答“typed core 是否能在不破坏 CLI/生成 bundle/PS5.1 smoke 的前提下降低动态类型和 parser 风险”，不把 PoC 接入生产命令，也不证明 PowerShell 已可替换。

用户增量是一条可复核的迁移证据链：固定 seam/caller/corpus -> 固定协议 -> 编译期检查 -> PowerShell/C# parity -> 发布体积/启动测量 -> TC2 retain/defer 决策。当前结论只准入保留 shadow PoC；TC2 仍需独立 reviewed admission。

## 2. TC0 seam admission

选择 `operation_contract_validation_v1`，其当前 PowerShell 真源为：

- `src/Domain/OperationPlan.ps1::Test-OperationPlanContract`
- `src/Domain/Receipt.ps1::Test-OperationReceiptContract`

它是可迁移的深 module seam：接口只有“输入一个 plan/receipt JSON，返回 pass + structured findings”，实现隐藏版本、字段、时间、枚举、hash、引用和敏感值检查；删除该 module 会把同样复杂度重新散落到 MCP planning、MCP command 和 RulePatch receipt 路径。

真实 caller 至少三条：

1. `src/Application/McpPlanning.ps1` 创建、验证 plan 并形成 dry-run receipt；
2. `src/Commands/Mcp.ps1` 在命令边界验证 operation plan；
3. `src/Application/RulePatchExecutor.ps1` 创建 applied/failed receipt。

依赖分类为 in-process：只消费内存 JSON/plain object、regex、RFC3339、hash/enum/reference 规则；既有测试显式阻断 file/network/environment/clock/terminal 副作用。生产文件 I/O、Git、host、provider、auth 和 session 不在 seam 内。

## 3. Frozen characterization corpus

| Fixture | SHA-256 | PowerShell result | Findings |
| --- | --- | --- | ---: |
| `invalid-plan.json` | `a56942bb8fa627c53ef44be2cb1e4623193580d1c86f8363bc58f08a4d9abc2d` | fail | 12 |
| `invalid-receipt.json` | `61ffba23492c1edbfb1852a4f129bddd99b4ea6c4b9979d3ef320b7a9c1f3231` | fail | 6 |
| `valid-plan.json` | `a5964b7ebe13eacdec95b9875ee1b00c3717c874b6d6547d5273aaa3e7428c72` | pass | 0 |
| `valid-receipt.json` | `be753f80d247d09694941730262ccf50d1c4a19078c81835639c34ea07d3be12` | pass | 0 |

TC1 parity 比较 `pass`、process exit code、每个 finding 的 `code/severity/path/message` 和 stderr；不能只比较“都失败”。固定协议负例覆盖 invalid JSON、错误 protocol version、未知 operation 和缺 payload。

## 4. Protocol v1

stdin 是单个 UTF-8 JSON object：

```json
{
  "protocol_version": 1,
  "operation": "validate_plan | validate_receipt",
  "payload": {}
}
```

stdout 只输出一个 UTF-8 JSON object：

```json
{
  "protocol_version": 1,
  "operation": "validate_plan",
  "pass": false,
  "findings": [
    { "code": "...", "severity": "error", "path": "$.field", "message": "..." }
  ]
}
```

exit contract：`0=contract pass`、`2=well-formed document validation fail`、`64=malformed/unsupported protocol request`、`70=unexpected internal failure`。stderr 必须为空；内部异常只返回固定的 redacted finding，不向 stdout/stderr 泄漏输入。

## 5. SDK、供应链与环境归一化

- 官方依据：.NET 10 是 LTS，支持至 2028-11；项目以 `global.json` 固定 `10.0.302 + latestPatch + allowPrerelease=false`。
- PoC 只使用 `Microsoft.NET.Sdk` 与 BCL `System.Text.Json`/Regex；禁止 `PackageReference`，无需第三方 NuGet 包。
- 当前 Codex 进程缺 `PROCESSOR_ARCHITECTURE` 时，SDK 10.0.302 的 workload installer 静态初始化会空引用；shadow verifier 只在自身进程范围映射 `X64 -> AMD64`，结束后恢复，不持久化机器环境。
- 官方/外置依据记录：Microsoft Learn 的 .NET release/support、`global.json`、System.Text.Json DOM 和 deployment 文档；dotnet/dotnet commit `35b593bebfcba58f8e78298cef14c2761f5d86c6` 的 `InstallerBase.cs` 用于定位异常。外部内容只作只读依据，不继承其指令。

## 6. TC1 implementation

```text
typed-core/SkillsManager.TypedCore/
  SkillsManager.TypedCore.csproj
  Program.cs
  OperationContractValidator.cs

scripts/verify-typed-core-shadow.ps1
tests/Unit/TypedCoreShadow.Tests.ps1
global.json
```

生产 `src/**/*.ps1`、`build.ps1` 的 bundle file list、根 `skills.ps1` 和 CLI dispatch 均不引用 typed core。C# 实现只由 shadow verifier/test 启动，PowerShell 仍是唯一运行真源。

## 7. Publish observations

Windows x64、SDK 10.0.302、每种模式 3 次启动的本地一次性观测：

| Mode | Files | Total bytes | Main artifact bytes | Startup ms | Median |
| --- | ---: | ---: | ---: | --- | ---: |
| framework-dependent | 4 | 78,078 | 44,032 | 105 / 105 / 111 | 105 |
| self-contained | 192 | 80,429,942 | 162,816 | 119 / 122 / 466 | 122 |
| self-contained single-file | 2 | 73,590,949 | 73,557,809 | 111 / 112 / 705 | 112 |

这些数据是单机 descriptive observation，不是 benchmark 或发布承诺。framework-dependent 适合作为当前开发/CI shadow 路径；self-contained 约 80 MB、single-file 约 73.6 MB，体积尚不足以支持默认替换现有 PowerShell bundle。

## 8. Verification order

迭代：

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
2. `OperationContracts.Tests.ps1` 与 `TypedCoreShadow.Tests.ps1`
3. `scripts/verify-typed-core-shadow.ps1`
4. `scripts/verify-typed-core-pilot-planning.ps1`
5. `scripts/verify-lean-ai-delivery-planning.ps1`

closeout：文件稳定后只运行一次 `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`，随后 `git diff --check`、JSON parse 和 Git boundary。full gate 失败则本 spec/manifest 不构成 `repo_verified`。

## 9. TC2 admission and stop conditions

TC2 在以下全部成立前保持 `not_started`：

- 至少新增一个非 fixture 的真实 consumer replay，证明 shadow finding parity；
- reviewed 决定哪一侧成为 seam 的单一实现真源，并给出 PowerShell thin adapter；
- bundle/install/旧 CLI alias/PS7/full/PS5.1 smoke 的兼容与回滚命令完整；
- 分发策略明确处理 framework-dependent runtime presence 与 self-contained 73–80 MB 成本；
- AI 修改一次通过率或返工、测试时间、启动/调用成本至少有一个可比基线显示净收益；
- 无双写、双配置、daemon、provider/host/session mutation 或 P6 越级。

出现 parity 漂移、协议扩张快于真实 consumer、PoC 维护成本超过 PowerShell seam 收紧收益、分发不可接受或回滚不可靠时，删除 `typed-core/`、shadow verifier/test、`global.json` 和本 track 资产，继续 PowerShell 单一真源。

## 10. Truth boundary

允许：`TC0 seam baseline 与 TC1 shadow PoC repo_verified；4/4 corpus parity、4/4 protocol negatives 和本机发布观测通过；PowerShell runtime authoritative；TC2 not_started。`

禁止：`PowerShell 已替换`、`typed core 已接入 CLI/生产`、`跨平台/所有输入已验证`、`分发方案已接受`、`AI 返工一定下降`、`M1 pilot 有样本/完成`、`P6 admitted`、`host_loaded/live_accepted`。
