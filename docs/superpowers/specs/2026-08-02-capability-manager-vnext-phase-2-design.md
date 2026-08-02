# skills-manager vNext Phase 2 Design: Transactional explicit apply

**program_id**: `skills-manager-vnext`
**phase**: `P2`
**status**: implementation_ready
**date**: 2026-08-02

## 1. Goal

在 P1 只读 findings 之后，为单一规则文件 patch 提供 versioned plan、human diff、freshness、显式 apply、atomic replace、receipt 和精确 rollback。实现只在显式授权 root 与 fixture 中执行；不得把 repo-side executor 的存在写成真实宿主写入已授权或已验收。

## 2. Existing basis

- P0 已有 `OperationPlan`、`Receipt`、SHA-256 freshness、redaction 与 `Write-Utf8FileAtomic`。
- P1 已有 bounded discovery、deterministic findings、recommendation-only advisor 和 repo truth。
- Codex/Claude 规则加载、host auth/permission、fresh-session activation 仍由宿主所有。
- P2 不新增 runtime、daemon、database、central registry、cross-repo synchronizer 或 generic policy AST。

## 3. Phase boundary

### In scope

- `RulePatchPlan v1`：单文件、before/desired hash、unified diff、finding/evidence refs、risk、verification、rollback。
- 纯 planner：显式 current/desired text -> deterministic plan；不从 semantic recommendation 自动生成 desired text。
- freshness/path/symlink/root/single-target/explicit-token guards。
- staging + atomic replace + receipt + fault-injection rollback。
- fixture-only CLI `rule-plan` / `rule-apply`；真实仓默认拒绝 apply。
- 让 MCP structured plan/receipt adapter 复用 verification vocabulary，不改变当前 apply 行为。

### Out of scope

- 修改 `~/.codex`、`~/.claude`、当前仓或任一真实目标仓规则。
- 自动接受 semantic advice、批量 patch、多仓事务、跨仓同步。
- host plugin/MCP native mutation、provider call、auth/profile/model/sandbox 修改。
- fresh-session load 或 live workflow acceptance。

## 4. Product invariants

1. plan 永远 zero-write；apply 必须同时满足 valid plan、fresh hash、authorized root、single target、explicit token。
2. P2 CLI apply 只允许 `tests/fixtures` 或调用方显式 `-FixtureRoot`；真实仓路径 fail-closed。
3. semantic finding/recommendation 不能作为 desired content 或 apply authorization。
4. 写入使用同目录 staging/atomic replace；失败只回滚本 operation。
5. receipt 分离 `static_validated/repo_gates_passed/host_loaded/live_accepted`，后三者不自动晋级。
6. before/desired content、diff、receipt 均做敏感信息检测；凭据不得落盘。
7. symlink/reparse/out-of-root/drive-root/UNC root 未显式支持时拒绝。
8. MCP adapter 只复用合同，不改变 legacy sync/plan target set。

## 5. RulePatchPlan v1

```text
schema_version, patch_id, operation_id, mode(plan|apply)
target{target_ref,path,authorized_root,before_hash,desired_hash,owner}
source{finding_ids[],evidence_refs[],desired_source(explicit_user_input|reviewed_file)}
diff{format=unified,content,has_changes}
risk, preconditions[], verification[], rollback[]
apply{required_token,fixture_only=true}
```

`desired_source` 不允许 `semantic_recommendation`。plan 不存 host token/credentials。

## 6. Planner and freshness

- caller 必须传入 current text、desired text、target path 和 authorized root。
- planner 计算 hashes 和 deterministic patch ID；相同输入输出字节稳定。
- diff 为 bounded unified text；不引入第三方 diff engine，超过阈值时 fail-closed 而非截断误导。
- apply 前重新读取目标并计算 current hash；不存在/变化/owner/root/token mismatch 均零写入。

## 7. Transaction executor

- 将 desired bytes 写入目标同目录临时文件，flush 后 atomic replace。
- 原文件内容保留为 operation-local rollback material；receipt 不嵌入完整敏感内容。
- fault points：before_stage、after_stage、before_replace、after_replace、before_receipt。
- `after_replace` 失败必须恢复 before bytes；恢复失败输出 `rollback_failed` 并保留可定位 recovery evidence。
- 并发变化通过 replace 前二次 hash 检测阻断。

## 8. CLI contract

```powershell
.\skills.ps1 rule-plan --target <fixture-file> --desired-file <reviewed-file> --fixture-root <root> --json [--out <plan.json>]
.\skills.ps1 rule-apply --plan <plan.json> --fixture-root <root> --token APPLY_RULE_PATCH --json [--out <receipt.json>]
```

- `rule-plan` 默认只输出，不修改 target。
- `rule-apply` 缺 token、非 fixture root、stale plan 或 semantic desired source返回 exit 2。
- runtime/input error exit 1；successful fixture apply exit 0。
- JSON stdout 只有一个 compressed envelope。

## 9. MCP compatibility

- 现有 `mcp-sync --plan --json` action/target parity 不变。
- 新 adapter 可从 OperationPlan 构造 not-run Receipt skeleton；不得执行 native add/remove。
- MCP apply 迁移到共享 executor 需要独立后续证据，本 Phase 不强制改写已稳定的多目标配置逻辑。

## 10. Task design

1. `SMV-P2-001`：P2 planning truth 和动态 planning tests。
2. `SMV-P2-002`：RulePatchPlan schema/constructor/validator/diff。
3. `SMV-P2-003`：freshness、authorized-root、single-target 和 token guards。
4. `SMV-P2-004`：fixture-only atomic executor、receipt 与 rollback。
5. `SMV-P2-005`：fault injection、concurrency 和 sensitive-content tests。
6. `SMV-P2-006`：fixture-only CLI 与 MCP receipt adapter compatibility。
7. `SMV-P2-007`：代表 fixture、full gate 和 repo-side closeout。

## 11. Representative fixtures

- clean-update：fresh single-file patch succeeds and receipt remains repo-only.
- stale：target changes after plan; apply writes nothing.
- fault-after-replace：executor restores exact before bytes.
- out-of-root/reparse/drive-root：fail-closed.
- sensitive desired/diff：plan rejected before serialization.

## 12. Ordered verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000
python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

## 13. Failure routing

- diff/encoding ambiguity：拒绝 plan，不猜测格式。
- stale/root/token/sensitive failure：exit 2，target hash 不变。
- fault rollback failure：阻断 closeout，保留 fixture evidence，不尝试其他目标。
- legacy MCP regression：还原 adapter，不迁移 executor。
- 两次同类失败：按 clarify protocol 记录 issue；不扩大真实写入面。

## 14. Done definition

- 七个 P2 task 全部 done；planning 0 finding。
- fixture plan/apply/rollback/fault/concurrency/sensitive guards 全部通过。
- 默认 CLI 不允许真实仓 apply，真实规则/host/profile/config hash 不变。
- MCP plan parity、existing tests 和 full gate 通过。
- 最高状态仅 `repo_verified`；`host_loaded/live_accepted=not_run`。
