# Exemption activation boundary fixtures

Source-only, synthetic verification. No actual catalog receipts, company IDs,
personal data, credentials or approval are included. Production HOLD and the
existing master OFF remain unchanged.

`prepare_activation.py` generates a catalog-bound, unused-only global management
switch transaction. The default approval gate always rejects. It does not add an
activation API or any employee exemption. Its generic catalog query covers
function attributes/ACL/bodies, relation columns/defaults/constraints/indexes/
options/triggers/policies/RLS, sequence attributes, private schema ACL and default
ACL. Sequence bigint attributes are text to avoid JSON number precision loss.

`pglite.mjs` verifies guard drift/CAS/approval/rollback with synthetic functions.
`native.mjs` uses the existing verifier's literal synthetic auth fixture and the
verbatim existing exemption candidate. PostgreSQL 17 checks actual two-connection
lock waits around ON and OFF, rather than inferring them from delays. The
post-use OFF statement is fixture-only boundary verification, not a generated
post-use production capsule. Existing saved decisions remain active while new
changes are disabled. This is not real GoTrue or iPhone verification.

The receipt writer publishes a new mode0600 file atomically and exclusively in
an owned mode0700 directory. A collision cannot overwrite a prior receipt.
Prepared, unknown, commit-confirmed and readback-confirmed are separate receipt
phases. This is not external WORM custody: filesystem owners can still alter or
remove files. No database writes occur in receipt-writer tests.
