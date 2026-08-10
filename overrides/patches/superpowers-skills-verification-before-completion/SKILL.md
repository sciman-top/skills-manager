---
name: verification-before-completion
description: Verify a completion, fixed, or passing claim with fresh lowest-sufficient evidence. Use immediately before the claim; reuse an exact-current receipt and do not escalate to broader gates without a risk or repository-contract reason.
---

# Verification before completion

Evidence must match the claim. Before reporting completion:

1. State the exact claim and select the cheapest command or current receipt
   that directly proves it.
2. Reuse an exact-current passed receipt when its source fingerprint and dirty
   policy match. Otherwise run the focused affected check.
3. Read the exit code and relevant failure count or invariant result.
4. Report the proven boundary. Distinguish repository verification, host load,
   real invocation, external effect, and live acceptance.

This skill does not itself authorize a full suite, CI run, repeated audit,
new evidence file, wider write set, network probe, deployment, or host
mutation. Escalate only for a current independent failure mode, a shared or
high-risk seam, or an explicit repository closeout contract. Run each required
layer once after the inputs are frozen; after a fix, re-run only the invalidated
layer. Stop when the declared claim is proven.
