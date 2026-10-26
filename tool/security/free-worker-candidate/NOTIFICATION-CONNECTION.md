# Trusted observation notification connection — integration contract, not sent

Collector owner: the roleless/v2 Collector candidate. Free-Worker owner: this
candidate. Root owns production integration, keys and deployment. No collector
SQL/function or existing notification/import routine is edited here.

The existing incident import path is labeled `synthetic_fixture`; its exact
ID/version outbox must **not** be reused by pretending a live observation is that
synthetic import. Collector currently has authenticated observation evidence,
owner-only key versions, proof-gated reading and retention, but no live
notification outbox. A matching new trusted-provenance connection remains needed.

## Required handoff

1. Free Worker persists exact seven-field event/body/ID before acknowledging
   collection. Its outbox never changes occurrence time, body, identity or
   provenance to bypass collector's freshness window. Repeated-source inference
   is absent unless its trusted correlation scope has been explicitly added.
2. Signed v2 ingress authenticates collector ID/key version and original UTF-8
   bytes. In one owner-only collector transaction, persist/authenticate evidence
   and an explicit notification candidate keyed by exact event ID or a real
   incident ID/version. Same ID/content retry creates no second candidate;
   conflicting content remains an error. Collector ID never selects a recipient.
3. The server binds the recipient to the verified Master/company association
   from trusted registration. A body/header cannot set company, actor, target
   user, real-person identity or notification title/free text.
4. Only fixed metadata/reason codes reach the Master notification: observation
   time, current/retired contact kind, source scope confidence, correlation window,
   coverage/drop/delivery state, event/incident/version and current review state.
   Contact means `observed`, never automatically `confirmed attack` or a named
   employee. No raw address, token, request data, salary or DB snapshot is copied.
5. Initial notice deduplicates on recipient + event/incident + version/type.
   Continuations are bounded/coalesced, not one message per hit. Coverage loss,
   delivery expiration, recovery and operator dismissal use distinct fixed
   types. Late evidence cannot silently reopen an already reviewed incident.
6. Delivery is outbox-driven with fixed timeout/lease/attempt bounds and a stable
   idempotency key. Unknown ACK reconciles that same key; failures remain pending
   or explicit held status. Do not delete evidence on a send attempt. No external
   LINE/email/broadcast is implicit; this contract is for authorized Master-only
   in-app visibility unless separately authorized.

## Authorization and receipt

Master listing/detail/action require the real current account/company/session
and dedicated read/manage proof; no `user_metadata` authorization or fabricated
actor. A forged/expired/other-company proof returns no record and causes no
notification state change. The observer ingress/key has no read or notification
recipient-setting privilege. User dismissal records who/when/reason and exact
incident version, does not erase evidence, and does not revoke real accounts.

The app must distinguish `persisted`, `notification queued`, `delivered`,
`displayed/read` and `reviewed`. A successful database insert is not proof the
administrator saw it. The current build20 is retained; no fabricated screenshot
or fake live UI is added to claim receipt.

## Acceptance checks still required

Use synthetic disposable inputs to verify initial/duplicate/concurrent input,
same-ID conflict, notification-write rollback, ACK loss/retry, recipient role or
company change, expired proof, coalescing limits, coverage/delivery-expired notice,
read/dismiss CAS, no raw-secret retention, restart and retention preservation.
Then separately record actual Master iPhone display/read and false-positive
review/closure. These tests/real sends are **not performed by this design file**.
No notification or production authorization is enabled here.
