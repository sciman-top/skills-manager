# Audit Runtime Evidence

- mode: dry-run
- run_id: 20260502-k12-refresh
- recommendations: reports\skill-audit\20260502-k12-refresh\recommendations.json
- success: True
- persisted: False
- timestamp: 2026-05-02T21:47:04.2825015+08:00

## Commands
- ".\\skills.ps1 审查目标 应用 --recommendations "reports\skill-audit\20260502-k12-refresh\recommendations.json" --dry-run-ack "我知道未落盘""

## Key Output
- changed_counts: {"add_total":0,"add_planned":0,"add_installed":0,"add_failed":0,"remove_total":0,"remove_planned":0,"remove_removed":0,"remove_not_found":0,"remove_ambiguous":0,"mcp_add_total":0,"mcp_add_planned":0,"mcp_add_added":0,"mcp_add_updated":0,"mcp_add_already_present":0,"mcp_add_failed":0,"mcp_remove_total":0,"mcp_remove_planned":0,"mcp_remove_removed":0,"mcp_remove_not_found":0,"mcp_remove_ambiguous":0,"mcp_remove_failed":0}

## Rollback
- 无