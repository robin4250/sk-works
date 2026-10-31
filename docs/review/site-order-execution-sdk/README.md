# Outgoing execution SDK source candidate

This continuation reads actual persisted original/package evidence separately
from unsigned review and consent preparation. A consent job alone is never
reported as original storage or recipient delivery.

The concrete repository has explicit original and share methods. Both persist an
append-only IDs/digest-only local stage intent before mutation, verify the
captured session again, and inspect persisted status in a separate request after
a successful response. Any existing intent blocks another mutation, including
an explicit repeated call. A failed or lost acknowledgement retains the intent;
`not_observed` never means safe to retry. OFF/new sessions can use status reads,
while mutation requires the original captured session and server authorization.

The decoder checks the complete reference, expected job and recipient identity,
original receipt/hash/length nullable group and exact package state. Recipient
inbox storage does not assert recipient approval or device push delivery.
Unknown/foreign package state stays unresolved. No journal completion or clear
method is introduced.

Dedicated tests cover malformed/boundary decoding and durable local quarantine.
The Native fixture records actual ES256/SQL handler outcomes and immutable
original/package statuses. A same-head artifact plus SHA-256 sidecar crosses into
the real SDK repository tests. SDK sessions and replay HTTP transport are
synthetic; the upstream Native handler verified its synthetic ES256 token, not a
real GoTrue login. No external counterparty is contacted.

UI original preview, final send confirmation, authoritative PDF byte retrieval,
verified terminal journal completion and new revision/reconsent UX remain
unconnected. These methods are not yet exposed as completed UI actions. No
production schema, role, Auth helper, feature switch or main branch is changed.
