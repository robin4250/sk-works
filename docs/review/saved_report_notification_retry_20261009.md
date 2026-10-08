# Saved group report notification retry persistence

- Stores only the original saved report ID and company ID, in a user-specific device key; report bodies, recipient lists and credentials are never stored here.
- Persists before publication. Restarting the app or changing today's site/date never creates or saves a new daily report.
- Rechecks the exact report ID, company and `updated_by` using current authenticated access before invoking the existing source-bound publisher. The server remains authoritative for membership, original roster, rollout and durable deduplication.
- Lookup failures, access changes, missing RPC and a zero result preserve pending identity. Zero is ambiguous between OFF and a deduplicated prior publication, so it never clears a pending retry or displays “sent”. A positive confirmed count removes only that user's exact company/report pair.
- Retry checks all pending records independently so an OFF/zero oldest record cannot hide later retries. It is available even when today's attendance list is empty.
- A storage failure prevents publication. Invalid stored data is preserved and reported, not replaced or silently discarded. Concurrent in-process store writes are serialized.
- Device local state does not survive app deletion, device replacement or storage clearing. No background publisher or external email sending is added.
- Database migrations, auth, RLS, existing recipient selection and the receipt ledger are unchanged. Production staged rollout remains OFF.
- Local Flutter/Dart are unavailable. Added regression tests must run in CI; physical restart/retry verification remains separate from CI and installation.
