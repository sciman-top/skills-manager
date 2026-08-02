# P1 real-input and governance-weight repair

## Scope and root cause

- `capability-inventory` only accepted dictionary-like config values while the runtime truth uses arrays, so the CLI returned reference descriptors with zero runtime descriptors.
- `rule-audit` constructed repo truth but did not pass extracted constraints to the advisor or call repository reference checks.
- Full verification was described as an every-slice requirement, and CI duplicated repo-owned gates while Azure/GitLab silently skipped nonexistent supply-chain and waiver scripts.

## Changes

- Normalize array and legacy dictionary shapes for vendors, imports, mappings and MCP servers; keep configs redacted and read-only.
- Extract only explicit `Global Rule -> Repo Action` mappings and bounded backtick path/command references; verify command entrypoint files without executing commands.
- Make AI scope control subtractive: targeted tests during iteration, quick for shared seams, full once at closeout/release, and one evidence file per logical slice by default.
- Route GitHub CI through the repo-owned full gate and remove duplicate or permanently skipped Azure/GitLab steps.
- Add `agentskills/agentskills` as a core standards reference and move MCP server examples to secondary; runtime truth remains `skills.json`.

## Verification boundary

- Regression red state: 3 expected failures for array runtime descriptors, CLI runtime count and Rule Advisor coverage; 2 expected precision failures for slash labels and unobserved command entrypoints.
- Targeted green state: 19 repaired regressions passed; the final affected-file run passed 229/229 with Pester 4.10.1.
- Real read-only CLI: 178 unique descriptors = 154 runtime (8 vendors + 44 imports + 97 mappings + 5 MCP servers) + 24 reference; duplicate ids=0, writes=0, provider calls=0, and `skills.json` SHA256 remained unchanged.
- Real rule audit: coverage=5, reference states=`verified:24`, `not_observed:1` (`git diff`, not executed), `out_of_root:2` (declared external read-only paths); writes/provider/native mutations/commands executed=0.
- Contracts passed: planning tasks=7/done=7/open=0, P4 decision=`not_started/deferred`, strict doctor, dependency baseline, skills config, and host capability matrix (hosts=5/evidence=7).
- Reference shelf: `agentskills/agentskills` cloned at `38a2ff82958afee88dadf4831509e6f7e9d8ef4e`; `modelcontextprotocol/servers` retained at `d31124c982401739917fd817c2a59db344529c16` under `secondary`, with the old core path absent.
- Full ordered gate: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` exited 0 after the worktree settled; Unit=663/663, E2E=17/17, skill integrity=105, routing findings=0, and all downstream contracts passed.
- One earlier full invocation overlapped a timed-out child process and concurrent RulePatch edits, producing 17 transient Unit failures; a no-concurrency Unit rerun passed 663/663 and the final serial full run above is the acceptance evidence. No lock service or additional governance surface was added for this orchestration-only condition.
- Highest possible state is `repo_verified`; no host load, live workflow, provider, native mutation, commit or push is claimed.

## Rollback

Revert only the inventory/rule-audit source and tests, the concise rule/product/CI policy edits, reference manifest/docs and this evidence file; rebuild `skills.ps1`. Do not alter P3 files, runtime imports, `skills.json`, host state or unrelated user changes.
