# Offline deception / MTD lab (beta)

Scope: Issue #273, 2026-10-14 06:40 JST approval. This is the first **synthetic offline controller**, not a deployed honeypot, WAF, or proven production defense. Existing app, authentication, database, LINE, and notifications are unchanged.

Run: `node --test tool/security/*_test.mjs` (Node 22+). No dependencies, network listener, DNS, outbound fetch, shell execution, database connection, environment credentials, or real records. `Request` is synthetic test input only. The `.invalid` host is reserved fixture text; tests never resolve it.

## Controller

- A low-interaction lure returns a constant empty synthetic dataset. It never accepts credentials or executes input.
- Operator rotation changes only the decoy generation path; retired generations remain detectable. This demonstrates the state transition needed for limited MTD; predictable numbered paths are **not** endpoint secrecy or infrastructure MTD.
- Logs contain only fixed event kinds, generation, sequence and clock time. Headers, body, query, address and identities are never retained or echoed. The body is cancelled without reading; target length is capped at 2048 characters.
- The bounded memory sink stores at most 128 events (configurable 1–1024), default retention one hour (maximum 24h). Overflow evicts oldest records. This deliberately does not provide durable audit evidence; production needs a separately reviewed bounded sink and dropped-event metric.
- Hits require human review. No automatic production blocking, notification, attribution, or account changes. Manual quarantine affects only this decoy and has a tested release path.
- Checkpoints include controller version/generation/quarantine only; restoration validates exact schema and clears request history. No production backup claim.

## Deployment gates still open

Public hosting and durable monitoring are not provisioned. Confirm free conditions using official provider documentation before selecting a host; do not create billing contracts. A deployment must use a separate credential-free environment with no route to production, platform ingress size/time/concurrency/rate limits, egress denial, operator-authenticated rotation, log retention/overflow metrics and an independent isolation review. The pure controller does not claim these platform protections. Never mount real data, Supabase keys, employee credentials or LINE tokens into it.

Do not import into SKO, expose an HTTP listener, attach production credentials or deploy automatically. This PR has no production hook. Next phases: independent review; isolated transport fixture and bounded durable sink; hosting/cost review; controlled deployment and false-positive exercise. Actual MTD topology changes and honeypot security benefit remain unverified.

## Local review sink and checkpoint limits

ReviewSink accepts only exact metadata from current/retired-lure events, rejects stale/future/duplicate sequences and additional fields, bounds its queue, and allows manual dismissal. This is an in-memory review queue, not an email/LINE transport. A dismissal has no production or decoy quarantine side effect. A fresh controller after restore starts a fresh sequence scope; recreate its review sink too.

Checkpoint validation rejects malformed or injected fields atomically, but does not authenticate valid-shaped tampering or prevent rollback. Keep checkpoints in trusted operator storage only. Signing and anti-rollback require a separately provisioned management trust boundary before deployment; no production key may be borrowed.

The dedicated CI workflow runs all synthetic tests on changes to tool/security and this workflow, with read-only repository permission and a three-minute timeout. No existing CI is rewritten.
