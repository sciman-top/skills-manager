# Global rule 9.73 project-contract evidence

- Repository: `skills-manager`
- Scope: project rule mapping only; no business-code or host-runtime mutation.
- Official basis: current Codex AGENTS loading/precedence and rules semantics; Claude platform delta remains separately verified.
- Git profile: baseline=`main`; upstream=`origin/main`.
- Before AGENTS SHA-256: `AF2761A06D7EA4F9F348138E5868F2E6623B3C7722B83012FBCCE5E2C4B163AD`
- After AGENTS SHA-256: `6F5222AD16408260AAE1DE176B19C2B1543B8BABC48FF5D5E257BD7003CCAA40`
- Planned gate: `pwsh -NoProfile -File scripts/quality/run-local-quality-gates.ps1 -Profile full`
- Current verification: `pending`; results will be recorded after fresh gates.
- N/A: host loading and live acceptance remain outside repository-static verification.
- Rollback: revert only this repository's `AGENTS.md` and this evidence file to the recorded before hash.
- Truth boundary: `repo_verified=pending`; `host_loaded=not_run`; `live_accepted=not_run`.
