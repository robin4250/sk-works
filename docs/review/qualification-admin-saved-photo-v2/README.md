# Qualification retained-photo connection source (WIP)

Fixed source base fc09f65. Reuses saved client70a0378 and immutable#1241 SQL with the separate20261021 ordered-baseline patch. No main or production changes.

The old exact8key/version1 management capability cannot attest the ordered-baseline guard. This candidate requires exact9key/version2 with expected_photo_paths_required=true. The new review-only forward SQL changes that response only after exact baseline-ready body8db1b9ad7b141c6d132ae4252f363288 and dedicated owner/ACL checks; old SQLs stay unchanged. Do not apply any old/new capsule without fresh full dependency/authority review, stop design and separate production approval.

The management detail entry keeps direct edit/delete blocked and opens a dedicated retained-photo approval flow. Unknown/missing capability fails closed. Metadata changes and new uploads remain unavailable. The capability is display evidence, not a substitute for server authorization/CAS.

Client fixed request UUID, original ordered viewed baseline, actor/company/worker/target/original SID and stage are persisted before prepare. Unknown outcomes never resubmit. Explicit recovery only calls get_photos for the same ID. A fresh SID may read an existing same-actor/company request using a newly verified live lease; that does not authorize a new mutation. The server result binds ID/target/requester and selection, not company/worker/SID attestation. Final acknowledgement archives the confirmed approved/rejected receipt before clearing the active journal.

The existing TradeDocumentFormSession supplies exact SDK session/gateway/lifecycle retirement; no global Auth file changes. Local journal uses existing SharedPreferences and an in-process key exclusion; this is not a cross-device database lock. Corruption fails closed. A confirmed draft after an interrupted prepare is retained for manual resolution; auto-submit/cancel is not implemented. Current general review queue is reused only through existing server actions and still requires runtime compatibility validation.

Validation pending: new client tests, actual SDK synthetic transport, old read-only hold compatibility, and baseline/attestation fixture. No real Auth provider, hosted RLS/Storage bytes, native concurrent rollout, production installation, feature enabling or iPhone proof. Existing source successes are not reused as this candidate's latest CI evidence.
