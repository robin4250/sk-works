# Canonical receipt / actual SDK / UI isolated bridge

Not deployable, not in Phone Release. Dedicated workflow starts disabled for source review.

Base is fixed72ef (canonical receipt Native9); old46773/77dc/1728 heads remain frozen. Product SDK repository, journal, DTO and pages are the exact existing46773 blobs. This focused bridge reuses canonical fixture setup only, not the nine-check suite. It uses actual prepare_receipt, synthetic Storage object metadata and actual submit_with_receipt before manager UI operations. No artificial claim receipt path column exists.

The actual SDK HTTP transport, manager confirmation, controlled committed-but-null ACK, observe-only result query, original applicant notice and canonical personal history RPC are exercised. The rendered ExpenseClaimsPage input carries the decoded canonical receipt path. The test never opens or fetches photo bytes. before_row stays original claim JSON; separate receipt_snapshot and unchanged canonical metadata/path/hash/object metadata are checked. attached_metadata_only explicitly does not establish actual object bytes or real Storage preservation; missing/unknown metadata must not be reported as photo proof.

The gateway is exact-route/body allowlisted and loopback-only, uses synthetic identities with actual authenticated SQL role and SID checks, bounded connection/query/HTTP operations and final connection shutdown. This is not real PostgREST, GoTrue, Storage, push, iPhone, shared financial-reader admission or legacy rollout. deployable:false and financial-reader RED remain.
