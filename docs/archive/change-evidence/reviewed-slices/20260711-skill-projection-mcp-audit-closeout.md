# 2026-07-11 Skills / MCP / Plugin 治理收口证据

## 1. 依据与边界

- 风险等级：中风险宿主配置投影；先 dry-run/备份，未重启进程，未执行审查建议 apply。
- 当前落点：`skills.json`、`src/Commands/SkillProjection.ps1`、MCP Codex 投影与 `reports/skill-audit/20260711-000457-811/`。
- 目标归宿：保留 `.codex/skills` 与 `.agents/skills` 的并集和独有技能，通过可重建、可回滚的平台投影消除同名重复；MCP 默认只启用高频文档能力。
- 目标仓：`ClassroomToolkit`、`classroom-answer-toolkit`、`skills-manager`、`k12-question-graph`、`local-ai-dev-orchestrator`、`ai-content-delivery-studio`、`github-toolkit`、`qq-codex-bot`、`vps-ssh-launcher`。
- 排除：`external`、`governed-ai-coding-runtime`、`physicist_chinese_poster_batch_tool`、`文档`。

## 2. 技能重复修复

- 源条目 200，唯一名称 116，同名重复 81 组，非主路径 84 个，内容冲突 57 组。
- 选主：`.system` > source priority > source order/path；105 个主副本来自受管 `agent`，11 个独有主副本来自 `.agents/skills`。
- 未删除、移动或覆盖 `.agents/skills`；两个源目录都保留。
- `~/.codex/config.toml` 含 1 个完整受管块和 84 个 `[[skills.config]] enabled=false` 条目。
- manifest：`reports/skill-projection/current.json`，包含 `name/content_hash/package_hash/source/target_platforms`、canonical、disabled 和 conflict 记录。
- 最近备份：`C:\Users\sciman\.codex\config-backups\config.toml.skills-projection.20260711-001244-942.bak`。
- 当前任务未重启 Codex；投影需要新任务重新加载。文件级结构、CLI 配置解析和构建链已验证。

## 3. 上下文预算

- 去重后 116 个直接技能的名称、描述、路径估算为 43,461 字符。
- 当前已启用插件的缓存技能估算约 4,376-6,026 字符；路径位置与运行时版本会导致估算波动。
- 总规模仍明显超过官方“上下文未知时 8,000 字符”的 2% 回退预算。Codex 会截短描述或省略部分技能，因此不能把约 4.8-5.0 万字符说成每轮完整注入，但默认技能过多的问题仍存在。
- 本轮只解决同名重复；唯一技能的默认/编码/浏览器/数据库/.NET/内容/PPT profile 化属于下一阶段，不能通过继续删除重复副本完成。

## 4. MCP 与 Plugin 裁决

- Codex 可见 9 个 MCP：`node_repl`、`microsoft-learn`、`openaiDeveloperDocs` enabled；`codebase-memory-mcp`、`context7`、`filesystem`、`github`、`playwright`、`postgres` disabled。
- `skills.json` 已显式记录 8 个受管 MCP 的 enabled 状态；同步器保留宿主拥有的 `node_repl` 及其 `.env` 子表。
- 默认禁用 6 个 MCP 的判断正确：本地 filesystem 与 Codex 文件能力重复；GitHub 已有 plugin；Playwright 编码任务优先 CLI skill；Postgres、Context7、codebase memory 均按专项任务启用。
- 10 个 enabled plugin 与用户用途大体匹配。Office 四件套、GitHub、Chrome、Computer Use 保留；`template-creator`、Browser、Visualize 有重叠，但本机调用日志没有可靠频率数据，本轮不凭猜测停用。
- Plugin 数量不是固定成本的可靠代理；应按其实际技能、MCP、App、hook 和工具面判断。

## 5. 最新审查包与四类建议

- run：`reports/skill-audit/20260711-000457-811/`；旧 `20260710-230917-033` 包基于过时目标集合和 MCP 状态，不作为最终结论。
- recommendations preflight：通过，issues=0；dry-run：通过，persisted=false；apply：未执行。
- 技能新增 1：原序号 `[1] microsoft-code-reference`。Microsoft 官方 skill 为多个 .NET/WPF 仓补充 API 签名、官方代码样例和弃用信息检索，复用已启用的 Microsoft Learn MCP。
- 技能卸载 0：重复副本已用路径投影处理，物理卸载会破坏独有技能或回滚能力。
- MCP 新增 0：现有能力已覆盖，继续增加常驻 MCP 会扩大工具面。
- MCP 卸载 0：6 个专项 MCP 保留配置但默认禁用；`postgres` 完成替代实现和凭据迁移后再决定卸载。

## 6. 验证

- `codex --version`：`codex-cli 0.144.1`；`codex --help` 可见 mcp/plugin/doctor。
- `pwsh -File build.ps1`：exit 0。
- `pwsh -File tests/run.ps1`：exit 0；Unit/E2E 无失败，E2E 12/12。
- `pwsh -File skills.ps1 doctor --strict --threshold-ms 8000`：exit 0；仅历史 `apply_targets` / `build_agent` 性能告警，strict 不阻断。
- `pwsh -File skills.ps1 构建生效`：exit 0；再次得到 entries=200、unique=116、disabled=84、conflicts=57。
- `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`：exit 0。
- `pwsh -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`：exit 0；full gates passed。
- `git diff --check`：exit 0；仅 Git 的 CRLF 未来转换提示，无 whitespace error。

## 7. 回滚与 N/A

- 配置回滚：从上述 `config.toml.skills-projection.*.bak` 恢复，或禁用 `skills.json.skill_projection` 后重新生成受管块；恢复前先备份当前配置。
- 代码回滚：撤销投影模块、集成点、配置契约和对应测试后重新执行 `build.ps1`；不得删除用户技能目录。
- MCP 回滚：恢复 `skills.json` 中原 enabled 状态并执行 `同步MCP`；同步器必须继续保留 `node_repl`。
- 审查 apply：`gate_na`；reason=用户未明确批准真实安装/卸载；alternative_verification=preflight + dry-run；evidence_link=本文件和最新 run；expires_at=用户明确批准 apply 时。
- 进程重启：`platform_na`；reason=当前任务禁止未经确认重启 Codex；alternative_verification=配置结构、manifest、CLI 和新任务复核条件；evidence_link=本文件；expires_at=用户明确授权重启时。
