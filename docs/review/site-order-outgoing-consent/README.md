# Outgoing unsigned review and explicit consent — source draft

This candidate does not install production objects, activate orders, merge main,
register an original PDF or send a document. The application writer/send UI is
not connected. Existing orders remain OFF.

## Why two metadata tables

`preview_receipts` records each fresh unsigned human-review snapshot. Reopening a
review may create another receipt; it has no consent or send authority.
`decision_receipts` records at most one confirmed decision for an operation and
one job, with unique operation, preview, request and job constraints. It links
back to the existing canonical consent ledger instead of duplicating consent.
The differing lifetimes and uniqueness rules require separate tables. Both hold
IDs, digests and timestamps only; no body, stamp image, PDF or amount is copied.

## Private operations

- `preview_unsigned` reuses the unchanged unsigned prepare guard and registered
  own-seal evidence, then returns a strict preview-only envelope.
- `confirm_unsigned` requires an explicit confirmation, current live actor,
  company, role, original SID and master ON. Company-pair and operation locks
  precede exact own receipt lookup. New decisions run unchanged manager consent
  and job preparation plus the purpose receipt in one transaction.
- `decision_status` supports current authorized observation under OFF or a new
  live SID. Missing or advanced results do not permit replay, clearing or send.

The fixed outgoing handler exposes only fixed parameterized commands under its
existing verified JWT/internal connection boundary. New database functions and
metadata tables are owner only. Existing eight helpers, C, Auth and canonical
renderer CLI are not modified. Original registration remains a separate
post-commit transaction using the existing approved renderer.

## Client behavior

The actual SDK repository parses the strict server envelope and stores only
identity/digest references before consent mutation. The append-only client
quarantine survives fresh repository instances. Unknown, mismatched and absent
results retain it. A new valid SID may inspect an old reference but cannot
confirm it. It never clears the original prepare journal or registers/sends a
preview. A second quarantined confirmation is directed to status observation.

## Evidence and remaining boundaries

The dedicated workflow composes frozen public-source exact-eight plus C and the
existing fourteen modules. New tests cover rollback, old receipt/job borrowing,
OFF/new SID, actual Native lock waits in both retirement/confirmation orders and
source/role/seal/feature drift. Fixed ES256 HTTP discards only the ACK after a
real commit and reconciles the same job without another mutation. Native
synthetic receipts are hashed, uploaded and downloaded into the actual SDK
repository/journal tests. Latest-head CI and independent review must be checked;
this README alone is not evidence of success.

Real GoTrue, hosted Edge, production dependency catalog, original registration,
delivery, UI input/prepare integration and iPhone confirmation remain separate
uncompleted stages. The immutable helpers are actual public-source bodies;
identities, keys, company rows and isolated fixture triggers remain synthetic.
