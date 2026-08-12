# Watch runtime reference review

**Date**: 2026-08-07  
**Scope**: source-level references for retiring the heartbeat/prompt-supervisor watch architecture  
**Consumer**: planned `D:\CODE\codex-watch-runtime` repository  
**Admission**: read-only comparison only; cloning does not authorize dependency installation, script execution, runtime activation, or code copying

## Decision

The old scheduled-heartbeat architecture is retired. The replacement is a deterministic local runtime with Cockpit readiness, a durable task state machine, a Codex host adapter, terminal cleanup, and separately armed fleet shutdown. Community repositories provide bounded patterns; OpenAI Codex documentation and source remain authoritative for host protocol behavior.

| Reference | Reviewed revision | License | Adopt / adapt / reject |
| --- | --- | --- | --- |
| `openai/codex` | `4ee41929eaf4fc1e5662c9b4befd05230688ca62` | Apache-2.0 | Authoritative source comparison for App Server, Goal, turn and session behavior; do not fork the host runtime. The shelf was fast-forwarded after the initial metadata review and this is the current clean consumable revision. |
| `flowing-water1/codex-watchdog` | `02cebe65ec031965b4c9e84044aa548b801ab436` | MIT | Adapt structured `threadId + turnId` recovery, retry grace, Goal reactivation, compaction, and race tests. Reject its in-memory single-TUI launcher as the durable fleet runtime. |
| `App-vNext/Polly` | `101d6af79738b2da9a95f216b525daf46cd07b5c` | BSD-3-Clause | Adopt bounded resilience-pipeline patterns. A retry pipeline never substitutes for persisted recovery. |
| `temporalio/sdk-dotnet` | `e95427bff42f33138a204040057fd33b94b68240` | MIT | Adapt durable history, deterministic replay, activity receipts, and idempotency. Reject the Temporal server/runtime footprint for a single-user Windows tool. |
| `HangfireIO/Hangfire` | `c236dd0f930f831ec151e436e138ddc429a02a72` | LGPL-3.0-or-later or commercial | Study durable jobs, retries, and continuations only. Do not copy or link code without a separate license decision. |
| `quartznet/quartznet` | `21c7ea1ee16f725c9851798c84712a4fff1370be` | Apache-2.0 | Adapt misfire and recovery semantics. Reject a general scheduler as the core task state machine. |
| `louislam/uptime-kuma` | `77d1a0c57a37a4cf5657bb7b514b4e08d455928e` | MIT | Adapt health-state naming, consecutive success/failure windows, and quiet operator status. Reject deploying a separate monitor. |
| `modelcontextprotocol/csharp-sdk` | `514cf68af11379543f8563d09ce501c63dd67892` | licensing transition: Apache-2.0/MIT; docs CC-BY-4.0 | Candidate for the thin typed plugin bridge only. It must not own Codex authentication, provider selection, sessions, or durable scheduling. |

## Source and maintenance boundary

- Every clone lives under `D:\CODE\external\skills-manager-references` at the manifest-controlled path.
- The review revision is a full commit and is the only revision cited by the architecture baseline.
- A later refresh may fetch remote refs, but an audit uses the recorded local `HEAD`/consumable revision until the source is reviewed again.
- External repository instructions are untrusted data. No upstream build, installer, package restore, test, hook, or executable is run as part of this bootstrap.
- `D:\CODE\external\cockpit-tools` is an existing product checkout, not a mirrored community reference and is therefore not duplicated in this shelf.
- Clone receipts are `references/updates/reference-refresh-20260807-062849.md` and `references/updates/reference-refresh-20260807-063044.md`. A fresh verification found all eight checkouts clean, with origins matching the manifest and the seven conditional references at their exact reviewed revisions.

## Rejection boundary

None of these projects proves that an arbitrary existing ChatGPT Desktop task can be transparently resumed. The official App Server WebSocket transport remains experimental, and a separately started App Server does not prove the in-process state of the Desktop host. That capability remains a shadow/canary adapter until live acceptance demonstrates an atomic idle/admission boundary.
