# Master device lock/unlock — staged child of #1132

Only `set_master_device_locked` is covered in this phase. Bootstrap, device
status/listing, revocation, dual-code emergency recovery, recovery contacts,
ordinary feature capability and all existing login providers remain unchanged.
Do not report all Master server authentication complete.

The new global operation scope `master_device_lock` defaults OFF in its own
private singleton table, without altering #1132's three scope rows. A fresh
primary-password proof is bound to `master.device.lock` and exact JSON target
`{"device_id":"UUID","locked":true}` (or false). The issuer checks an own,
nonrevoked device; the consumer checks it again under a row lock. Proof
consumption, lock state update and original audit append are atomic. Rollback
also restores consumption. An ON gate rejects the unproven legacy setter; OFF
preserves its original operation and audit semantics.

The existing management page discovers `master_device_lock_capability`. Only
PGRST202 (new API absent) or explicit OFF keeps the legacy setter. Permission,
network and malformed capability failures do not downgrade. ON asks for the
primary password, then sends the exact proof once. Credentials/nonce remain in
memory only; actor changes, app backgrounding and stale async results cannot
complete the operation. Cancelling the prompt sends no mutation.

All gates remain OFF and no SQL/Edge/configuration is deployed here. Apple,
Google and OAuth-only users without a primary password lack a supported server
reauthentication alternative: do not enable this global scope until legitimate
alternatives and real Auth-project temporary-session behavior are verified.
Existing IDs/roles/company/membership/provider identities are not migrated.

Dedicated PostgreSQL 17 tests use synthetic data only and check target/value,
role/account/session/revocation/expiry/replay, failed business precondition and
transaction rollback, concurrent proof consumers and OFF-to-ON transition,
identity/owner/history preservation and exact original function/ACL restoration.
Widget/SDK tests exercise the actual device page and proof dialog with mocked
transport. These are not a real phone or production recovery/login test.

Dedicated CI run `38896353671` at commit
`0e1be472d4523e664e76f532134d0e5d8de3c8d3` passed both jobs: PostgreSQL 17
restore/authorization/concurrency and 23 Edge tests (`116957647427`), plus
Flutter analysis and all 10 page/dialog/SDK/existing-contract tests
(`116957647747`). The manually invoked stale callback fixture uses synchronous
assertions inside callbacks to avoid Flutter test-zone guard conflicts; its
single capability request, single proof and single completed mutation checks
remain enforced. Whole-application Flutter/iOS CI after retargeting to main
remains a separate integration gate.

Production application/enforcement still requires confidential backup, isolated
restore, normal-administrator UI comparison, an impact report and the user's
explicit approval. This branch does not satisfy or bypass that approval boundary.

A device lock is not JWT revocation and does not add step-up to the remaining
Master APIs. Those separate gaps remain in the coverage inventory.

Supabase CLI 2.121.0 generated the unlinked promotion filename
`20261016113647_master_device_lock_reauthentication.sql`; only review-only
`tool/staged` SQL is committed here. The pre-change lock routine fixture is a
read-only `pg_get_functiondef` copy; it contains no actual device/account rows.
