---
name: sandbox-slow-test-diagnosis
description: Diagnose and fix "tests take forever" in an agent sandbox (WorkBuddy/CodeBuddy/Codex shim hosts) where process spawns and directory deletions are billed. Use when a test suite or command is far slower inside the agent than in a plain terminal, or when a fixture-heavy suite stalls. Covers the fingerprint check, the per-directory cost model, and the fixture-reduction levers.
---

# Sandbox slow-test diagnosis

Agent sandboxes in WorkBuddy/CodeBuddy/Codex hosts inject shims that **bill
mutation-class operations**: process creation and filesystem deletion. The same
suite can be **10–100× slower** inside the agent than in CI. Do not report this
as code cost — diagnose it.

## 1. Confirm you are inside the sandbox

Check for the fingerprint before interpreting any timing:

- Env vars: `CODEBUDDY_SAFE_DELETE_ENABLED=1`, `CODEBUDDY_SAFE_DELETE_SANDBOX=1`,
  `CODEBUDDY_SAFE_DELETE_BROKER_DELETE`, `CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD`
  (default 50), `NODE_OPTIONS=<...>/node-language-shim.cjs`,
  `PYTHONPATH=<...>/cli/vendor/shim`, `HTTP_PROXY=http://127.0.0.1:*`.
- PowerShell: `(Get-Command Remove-Item).CommandType` — `Function` means wrapped.
- Never paste full `env` into chat/logs/commits (it carries long-lived creds).

If no fingerprint: the slow path is NOT this class (proxy/cross-drive temp/other).

## 2. Measure the two cost units (do NOT assume)

Deletion is **per directory entry**, not per call and not swappable:

| Operation | Sandbox cost | Notes |
| --- | --- | --- |
| Delete nested **directory** | **≈0.15–0.63 s/dir** (linear in dir count) | the dominant teardown cost |
| Delete flat **file** | ≈28 ms/file | ~5–22× cheaper than a dir |
| `[IO.Directory]::Delete(p,$true)` vs `Remove-Item -Recurse` | **same price** | interception is *below* .NET; do not try to bypass |
| One-by-one vs single recursive call | **1.1×** | call count is NOT a factor |
| Create dir/file | ≈3–4 ms/item | creation is cheap |
| Process spawn (`git`, `pwsh`, CLI) | 0.4–1.2 s hot; **can stall 60–228 s cold** | per spawn, unpredictable |

Reproduce with: build N dirs, time `Remove-Item -Recurse`; build N flat files,
time delete; compare `Remove-Item` vs `[IO.Directory]::Delete`. Scripts live
under `artifacts/work/ai-session-verify/probe-*.ps1` in skills-manager.

**Teardown is the hidden bulk.** Pester 6 deletes the whole `$TestDrive` once at
the end, so total cost ≈ (total directories created across the run) × per-dir
rate. A fixture creating 60 dirs × 37 tests = 2,220 dirs ≈ 5.5 min of pure
deletion.

## 3. Levers, in order of value

1. **Cut total directory count** (biggest win). Flatten fixtures; avoid deep
   nested trees; drop optional subdirectories.
2. **Replace multi-directory artifacts with single-file equivalents** when the
   consumer only checks existence. Example: a `.git` *directory tree* can often
   be a one-line `.git` file pointer — **but only if git never runs against it**.
3. **Prepare once, copy per fixture** instead of re-running `git init` /
   `add` / `commit` per test (240 spawns → 10).
4. Reduce subprocess count in production code paths (e.g. merge multiple
   `git status`/`git diff` queries).

## 4. The `.git` fixture trap

- `Get-*`-style code that accepts **either** a `.git` directory **or** file is
  common. A `.git` *file* marker is fine for existence checks.
- 🔴 A hand-written `.git` file pointing at a **nonexistent** gitdir is rejected
  by git ("not a git repository"). If the code runs real `git symbolic-ref` /
  `show-ref` / `remote`, the pointer must resolve to a **real** gitdir.
- ✅ Best pattern: `git init --bare --initial-branch=main <shared>` once, then
  write `gitdir: <shared>` into each fixture's `.git` file. Real queries succeed,
  zero nested directories. (Used in skills-manager `RuleEstate.Tests.ps1`.)
- `git init --template=` yields a **7-directory** functional repo (vs 9) — use it
  when you must copy a real `.git`.

## 5. Verify without the slow full run

Wall-clock full runs are unreliable under sandbox contention. Prove a fixture
change deterministically instead:

- `[Parser]::ParseFile` on every edited test file → syntax.
- Reproduce the fixture mechanism standalone (create the template, copy it, run
  the exact `git` command the test needs, assert the output) — no Pester needed.
- Report the boundary honestly: mechanism-proven ≠ end-to-end receipt. Say which
  layer you did not verify and hand the full run to CI.

## 6. Do not

- Do not disable/bypass the shim to "get a clean run" — change the execution
  location instead.
- Do not split deletions into small batches to dodge the bulk-confirm guard; that
  is circumventing a safety control. Report the path to the user instead.
- Do not conclude a run is hung from a 0-byte log — confirm the process is alive
  and check for a receipt first; sandbox spawn stalls mimic a hang.
