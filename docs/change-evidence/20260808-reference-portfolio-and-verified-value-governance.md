# Reference portfolio and verified-value governance

- 日期：2026-08-08
- 状态：`affected_repo_verified`
- 风险：低到中；修改产品/项目治理、确定性 verifier、测试与 conditional reference candidate metadata，不修改 `skills.json`、外置 checkout、宿主配置或 runtime/live 状态。

## 依据与决定

- 产品 North Star 是 native-first、verified-value-first、local-first、advisory-first、可绕过/可回滚/可替换/可删除；本项目不复制宿主的推理、编码、agent loop、provider/auth/session/runtime。
- 编码交付先定义真实用户、入口、关键 seam、可观察终态和证据，优先跑通最薄真实主链；主链未通前只前置安全、数据、不可逆契约和直接阻断。
- 外部研究按本仓事实、官方文档/help/schema、官方/第一方源码、已映射本地参考仓、固定 revision/license 的社区候选有界推进；达到足以选择可逆方案的证据停止点后停止。
- reference shelf 是可逆证据组合，不是 append-only 档案馆或 runtime truth。生命周期为 `discover -> conditional-not-cloned -> on-demand read-only -> secondary/core-mainline -> historical-compatibility -> retire/remove`。
- 晋级需要第一方权威或重复当前消费者；官方替代、无消费者、重复、stale、许可证/供应链风险或维护成本超过净收益时优先降级、停刷或退役。
- 本项目只管理 manifest-owned `D:\CODE\external\skills-manager-references`。`D:\CODE\external` 根、兄弟 `*-references`、`_shared` 和产品 checkout 不进入自动 inventory/refresh/move/delete；reference checkout、manifest entry 和 `skills.json` runtime/import 删除是独立事务。

## Write set

- `AGENTS.md`
- `docs/product/README.md`
- `docs/product/skills-manager-vnext-prd.md`
- `docs/product/skills-manager-vnext-architecture.md`
- `docs/product/skills-manager-vnext-roadmap.md`
- `docs/EXTERNAL_REFERENCE_REPO_TIERS.md`
- `references/README.md`
- `references/reference-shelf.manifest.json`
- `scripts/verify-reference-governance.ps1`
- `tests/Unit/Core.Tests.ps1`
- 本 evidence

## 确定性门禁

`verify-reference-governance.ps1` 现在额外阻断：

- 非法 tier/status 生命周期组合；
- core/secondary/conditional 与相对路径层级不一致；
- historical entry 缺 replacement/source disposition；
- 非 core-mainline entry 进入 default refresh；
- manifest `references_root` 扩张到项目专用根之外；
- 项目规则、产品真源、参考 README/tier 文档和路线图缺失主链、可逆 portfolio、owned-root 或 runtime 分离契约。

## Verification

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`：通过，生成 `skills.ps1`。
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-reference-governance.ps1`：通过，`repos=36, default=7, patches=3`。
3. `Invoke-Pester -Script tests\Unit\Core.Tests.ps1 -PassThru`：实跑 `212`，通过 `212`，失败 `0`。
4. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json`：通过，P6 `12` tasks，`11 done / 1 open / 0 findings`。
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-lean-ai-delivery-planning.ps1 -Json`：通过，maintenance `11/11 done / 0 findings`，M1 仍 `collecting 0/10`。
6. `git diff --check -- <本切片 write set>`：通过；仅报告现有 Windows LF/CRLF checkout warning，无 whitespace error。
7. `AGENTS.md` 体量复核：`67 lines / 10035 bytes`，低于项目规则默认 `80 lines / 10 KiB` 上限；详细生命周期留在产品和 reference tier 文档，根规则只保留高频入口。

两次早期 focused Pester 尝试因 Pester 4.10.1 的嵌套文件 `-TestName` 过滤得到 `0 tests`，均被执行数断言正确阻断；最终改为完整 Core suite，不把零测试伪报为通过。

## Closeout correction

The final focused replay correctly rejected nine newly registered
`conditional-not-cloned` candidates because their discovery records lacked
the review metadata required by this slice's own verifier. The candidates were
not removed or cloned. Each now records a GitHub-observed full HEAD revision,
license or `NOASSERTION`, review date/evidence, activation trigger,
`reviewed-discovery-candidate` disposition and a reference-only decision.
Unknown licenses remain fail-closed and explicitly block cloning. The repaired
contract passes `Reference governance OK: repos=36, default=7, patches=3`, and
the complete Core suite passes `212/212`.

## Truth boundary 与回滚

- 本切片最高状态是 `affected_repo_verified`：证明产品/规则/reference contract、verifier 和 Core tests 一致，不证明宿主搜索行为、外置仓刷新、物理删除、安装、host_loaded、E2E 或 live acceptance。
- 当前仓库已有 P6 closeout 明确记录唯一 full quality gate 为 `not_passed` 且本轮不得重跑；本切片未运行 full，不得由 affected verification 推断 commit/release closeout。
- 回滚只撤销上述 write set 中本切片新增段落、verifier checks、测试和本 evidence；不得回退同文件内既有 P6/watch/runtime 用户改动，不删除任何 `D:\CODE\external` checkout。
