# Global rule 9.73 project-contract evidence

- Repository: `skills-manager`
- Scope: project rule mapping only; no business-code or host-runtime mutation.
- Official basis: current Codex AGENTS loading/precedence and rules semantics; Claude platform delta remains separately verified.
- Git profile: baseline=`main`; upstream=`origin/main`.
- Before AGENTS SHA-256: `AF2761A06D7EA4F9F348138E5868F2E6623B3C7722B83012FBCCE5E2C4B163AD`
- After AGENTS SHA-256: `7D26E9C13A47EA6B5C585D22EF8F420FE1E8D08C38CF3F40B39F0CCB221EE6AF`
- Canonical gate: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full`
- Current verification: clean `34a4baaa` full gate exit 0; 1121/1121 tests passed, generated sync and all contract/invariant gates passed, total `302224ms`. Fresh RuleEstate audit passed 9 targets, 144/144 textual mappings, 0 semantic gaps and 0 findings. Global budgets are healthy: Codex 13,699 bytes/110 lines; Claude 13,287 bytes/109 lines.
- Fresh host boundary: Codex CLI 0.146.1 `debug prompt-input` parsed and contained global/project v9.73, S1-S5 and the project mapping; the obsolete mandatory-router sentence was absent. Claude Code 2.1.206 help is available, but no provider-backed fresh prompt was run, so Claude `host_loaded=not_run`; business `live_accepted=not_run`.
- Rollback: revert only this repository's `AGENTS.md` and this evidence file to the recorded before hash.
- Truth boundary: `repo_verified=passed`; `full_gate=passed`; `host_loaded=codex_fresh_prompt_verified`; `claude_loaded=not_run`; `live_accepted=not_run`.
