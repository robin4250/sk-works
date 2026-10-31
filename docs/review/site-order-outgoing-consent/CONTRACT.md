# Unsigned review and explicit decision coordinator

SOURCE ONLY. No production installation, feature activation, main integration or
claim of working delivery. Orders remain OFF.

Owner: order composition. Base: 113b42b57ac0d1a9a49e900cecca47cb6150da9e.
New source lives only in this directory, the unsigned preview renderer, dedicated
consent SDK files and dedicated tests. Existing canonical renderer, eight helper
bodies, C authorizer, Auth and financial RPCs remain unchanged.

## Metadata ownership

Proposed private objects: `site_order_outgoing_private.preview_receipts` and
`site_order_outgoing_private.decision_receipts`. They are not installed by this
document. Preview receipts allow repeated human reviews of one unsigned operation.
Decision receipts uniquely attest one explicit decision and the matching job in
the same transaction. The two lifetimes and uniqueness rules differ.

Keep only IDs, digests, renderer contract, timestamps and result IDs. Canonical
revision bodies, seal snapshots, consent and render jobs remain in their existing
authoritative tables. No raw financial body, signature, seal image or PDF is
duplicated into these metadata tables. Owner only; no client/service grants.

## Transaction and replay contract

1. Verify current actor, live SID, company and management permission. A successful
   decision retry requires the original SID and current master ON as well.
2. Read an exact own immutable coordinator receipt before unsigned-only checks;
   an already advanced revision is expected after success. Read-only observation
   under OFF or a new valid SID cannot authorize mutation or send.
3. For new decisions preserve existing company-pair, operation, scope and consent
   lock order. Do not acquire an independent receipt or job lock before calling
   unchanged `require_unsigned_prepare`.
4. Under the operation serialization recheck all identity, body/source/seal and
   preview bindings. Only an explicit human confirmation invokes unchanged
   manager `decide` then `prepare_job` in the same transaction.
5. Inspect the actual returned job row: company, actor, SID, request, site,
   document/revision, peer, trade, connection fingerprint, body/render hashes and
   consent seal must match. The existing job early return is insufficient proof.
6. Record coordinator receipt only after both mutations and all checks succeed.
   A failure rolls the whole transaction back. A legacy consent/job without the
   new exact coordinator receipt remains advanced/unresolved.

ACK loss is unknown until exact receipt lookup. Never blind replay, clear the
prepare journal, invent consent, register preview bytes as an original or send.
The approved canonical PDF registrar remains a separate after-commit operation.

## Preview envelope

Use a separate unsigned-review envelope with explicit preview-only purpose and
false registration/send capabilities. Bind the prepared operation, preview ID,
body/source/seal hashes and fixed renderer contract. Reuse the existing pure A4
canvas; do not change the approved canonical CLI or fabricate its consent array.
The renderer receives trusted server evidence; parsing alone is not authorization.
PDF byte identity is not promised because metadata timestamps can differ.

## Required evidence

Exact frozen eight and C metadata must remain unchanged. Native two-connection
retirement/decision waits in both orders, borrowed-job rejection, post-lock source
change, same-ID ACK reconciliation, OFF/new SID and invalid permissions require
meaningful tests. Fixed ES256 HTTP through SQL and SDK must use the same receipt
contract. Real GoTrue, hosted Edge, production connection, original registration
and send remain separate unproven stages.
