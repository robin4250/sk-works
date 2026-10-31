# Atomic canonical document evidence — review only

This draft creates the final canonical scoped RPC directly in one transaction. It does not install PR 1663's legacy RPC body change, nor sequentially replace an intermediate scoped implementation. Source UI and PR 1667 / 1670 remain frozen. Production application is prohibited without separate approval.

## Target and impact

Only persistent objects created: `private.current_user_required_document_attention_for_company(uuid)` and the same-name public invoker wrapper. The private endpoint reads the live authenticated actor/session, explicit company membership, unique active worker and required-document evidence. Existing functions, schema privileges, relation definitions, document originals, employee evidence, exemption decisions and exemption history are not changed. Existing individual exemptions may already exist; no count-zero assumption is made. The separately approved global exemption switch remains ON; this candidate does not toggle it.

The final canonical endpoint never invokes `public.current_user_required_document_attention()`. Its body is pinned and preserved as an existing object. Therefore the legacy correction in PR 1663 is not an installation dependency. Existing older clients continue to call their unchanged legacy endpoint until separately updated.

## Pins and stop conditions

Catalog-only capture uses PostgreSQL 17.6 (`170006`). Exact fingerprints cover all attributes of the five existing authentication helpers and the legacy endpoint, public/private/auth namespace ownership and ACLs, all current default ACL entries, and nine directly/transitively used relation catalogs including columns, constraints, policies and triggers. Vacuum/statistics counters and transaction horizon columns are intentionally omitted from relation fingerprints; business rows are never fingerprinted or locked for a count-zero assumption. A concurrent legitimate exemption save therefore does not invalidate the installation merely by changing its business rows.

The same catalog fingerprints must match immediately before and after creation. Version changes, any helper body/owner/ACL/attribute change, schema/default ACL changes, relation contract changes, pre-existing endpoint/overload, or postcondition failure abort the entire transaction. Default privileges are pinned from the actual public-only configuration; PUBLIC, anon, service_role, new roles and grant-option leakage are rejected by the exact post-creation ACL seal. Existing helper grants remain untouched.

The two created functions must have the expected owner, UUID input, JSONB result, language, invoker/definer mode, volatility, strictness, parallel mode, empty search path and exact body MD5. Their ACL must contain only owner and authenticated EXECUTE, without grant option. No new schema grants are issued.

## Validation and recovery

This draft is NOT yet validated as a production-ready application candidate. Local isolated PGlite adversarial guard tests passed 14 checks, including actual public-default grant shape, unknown-role and grant-option rejection, complete new-object catalog seal and preservation of an existing waiver/history. The fixture substitutes its own catalog fingerprints only in the in-memory test string. Native verification, independent review and final immutable source/manifest checks remain required. The frozen predecessor has Native/PGlite evidence and client CI, but those successes do not validate this new guard bundle.

Before any separately approved application: re-read the catalog and compare the pinned source hashes, verify the old endpoints remain usable, and verify no new endpoint exists. Apply once using a transaction-capable controlled path. After COMMIT, read back exact new-function definitions/attributes/ACLs and the unchanged catalog fingerprints; then test authenticated scope/unknown handling with an explicitly authorized user. Do not infer business readiness from COMMIT or CI.

If the transaction fails, it rolls back both new endpoints. If COMMIT result is unknown, query the catalog/read receipt; do not blindly retry. After a confirmed commit, recovery requires a reviewed forward change. Never overwrite legacy authentication bodies, drop employee evidence or restore exemption/history snapshots. Release/install/device checks remain separate.
