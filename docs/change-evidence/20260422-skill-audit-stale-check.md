# 20260422 Skill Audit Stale Check

- rule_ids: R1, R2, R4, R6, R8
- risk_level: low
- landing: `reports/skill-audit/stale-check/recommendations.json`
- target_disposition: dry-run only; wait for user confirmation before `--apply --yes`
- rollback:
  - discard `reports/skill-audit/stale-check/recommendations.json`
  - discard `reports/skill-audit/stale-check/apply-report.json`
  - re-add removed `manual|prd-to-plan` mapping/import if rollback is required

## Evidence

- `codex --version`: `codex-cli 0.122.0`
- `codex status`: `platform_na`; reason: non-interactive execution returned `stdin is not a terminal`; alternative_verification: `codex --version`, `codex --help`; evidence_link: this file; expires_at: `2026-05-22`
- profile import:
  - cmd: `.\skills.ps1 审查目标 需求结构化 --profile "reports\skill-audit\user-profile.structured.json"`
  - key_output: `已导入结构化需求`
  - post_check: `audit-targets.json.user_profile.summary` non-empty, `structured_by = outer-ai`
- recommendations self-check:
  - cmd: local JSON/schema/placeholder check
  - key_output: `SELF_CHECK_OK; new_skills=0; removal_candidates=1`
- dry-run:
  - cmd: `.\skills.ps1 审查目标 应用 --recommendations "reports\skill-audit\stale-check\recommendations.json" --dry-run-ack "我知道未落盘"`
  - key_output: `remove_total=1`, `remove_planned=1`, `persisted=false`
  - evidence_link: `reports/skill-audit/stale-check/apply-report.json`
- apply:
  - cmd: `.\skills.ps1 审查目标 应用 --recommendations "reports\skill-audit\stale-check\recommendations.json" --apply --yes --remove-indexes "1"`
  - key_output: `mappings: 90 -> 89`, `imports: 35 -> 34`, `remove_removed=1`, `persisted=true`
  - evidence_link: `reports/skill-audit/stale-check/apply-report.json`

## Gate Notes

- build:
  - cmd: `.\build.ps1`
  - key_output: `Build success: D:\CODE\skills-manager\skills.ps1`
- test:
  - cmd: `.\skills.ps1 发现`
  - key_output: listed 96 discoverable skills; installed set includes `prd-to-issues` and no `prd-to-plan`
- contract/invariant:
  - cmd: `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - key_output: `Your system is ready for skills-manager.`
- hotspot:
  - cmd: `.\skills.ps1 构建生效`
  - key_output: `构建完成：agent/ (共 89 项技能)` and target junctions refreshed
