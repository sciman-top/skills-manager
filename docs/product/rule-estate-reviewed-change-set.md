# Reviewed rule estate change-set

`rule-estate-plan` 只消费已经由当前用户、外部审阅者或登记自动化策略批准的 change-set。AI 生成建议、desired file 或 JSON 本身不等于批准。

最小格式：

```json
{
  "schema_version": 1,
  "review_status": "reviewed",
  "reviewed_by": "workspace-owner",
  "reviewed_by_type": "human",
  "authorization_source": "user_supplied",
  "changes": [
    {
      "target_scope": "repository",
      "repository": "skills-manager",
      "target_file": "AGENTS.md",
      "desired_file": "desired/skills-manager-AGENTS.md",
      "allow_create": false,
      "risk": "medium",
      "evidence_refs": ["repo build/test/CI/script/README truth"]
    }
  ]
}
```

约束：

- `desired_file` 必须位于 change-set 所在目录或其子目录。
- `repository` 只接受动态发现的直属 Git 仓根 `AGENTS.md` 或 `CLAUDE.md`。
- `global_codex`、`global_claude` 和任何其他用户级目标均被拒绝；全局用户规则只能通过 `global-rules-plan/apply/rollback/check` 从 tracked `rules/global/` 源投影。
- 每个项目 desired file 都应由“当前全局规则 + 当前项目规则 + 项目代码/脚本/CI/README 事实 + 已核依据”独立推导，不能从控制仓模板直接复制覆盖。
- 仓内无关 dirty paths 会记录在 plan/receipt 中并原样保留；只有目标规则文件的 before hash 参与 freshness 阻断，流程不暂存、不提交、不回滚其他文件。
- `reviewed_by_type=ai` 永远拒绝；`human/user_supplied` 是审阅声明，不是密码学签名，apply 仍要求当前命令的显式 token。
- apply 不修改全局用户规则、provider、auth、model、sandbox、plugin/native host 配置，不自动 commit/push，也不把文件写入等同于 fresh-session 加载或真实用户验收。

执行模型为 `preflight-all -> apply-one-by-one -> receipt-after-each -> fail-fast`。后续目标失败时，先前成功目标保留并可从 receipt 单独 rollback；rollback 必须重新提供与 receipt 一致的 workspace/Codex/Claude control roots，但 action allowlist 仅允许 repository。修复阻塞后可用 `--resume <receipt.json>` 继续。全局规则变更必须先修改 tracked `rules/global/codex/AGENTS.md` 或 `rules/global/claude/CLAUDE.md`，再走专用 global-rules 投影流程。
