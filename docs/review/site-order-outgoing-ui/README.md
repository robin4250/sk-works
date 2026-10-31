# Outgoing input and explicit consent UI — source draft

Base: PR #1689 at 6559b76e52abdf08dcb09bc16a99cda80a9174d5. Its
independently reviewed consent/job purpose and 22 passing CI checks are retained.
No canonical helper, C, Auth, database object or production switch changes here.

The existing RAM entry and registered target selection remain the input route.
A new composition page persists prepare IDs before the fixed prepare command,
then loads an unsigned server preview. It compares the full semantic body with
RAM input before showing an unchecked issuer-stamp consent checkbox. Explicit
confirmation calls the existing atomic consent/job SDK only once. Unknown
prepare results use same-SID status before a fresh preview; unknown consent
results remain status-only. No result is automatically retried or cleared.

Returning to input after preparation explicitly retires the unsigned preparation.
Only verified retirement enables a new entry with retained editable content and
new document/request IDs. An unconfirmed/advanced retirement removes the stale
preview and does not enable editing or consent. Scope changes and backgrounding
mask RAM contents. Recovery remains available while generation is OFF.

Creation availability reuses the unchanged public C access receipt through the
captured session. Unknown, missing, OFF or mismatched receipts fail closed.
Historical viewing remains separate. The new workflow covers composition UI,
existing RAM entry/retirement, repository, directory and PDF-body regressions.

This is not a complete delivery flow. Original PDF registration, actual sharing,
receiving-company end-to-end behavior, production dependencies and iPhone checks
remain unfinished. The UI labels a saved consent as not yet shared and exposes
no send-success action. No real invitation or message is sent by this draft.
