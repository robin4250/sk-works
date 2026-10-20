# Payment expense v2: request representation negotiation

Issue #273. Baseline main: c8216d9a31e0d8340c9ec123307907bc148191a8.

The opted-in payment repository now sends `x-sko-payment-source-version: 2` on the payment table query and the two payment detail RPCs only. The default reader remains unchanged; the Supabase client global headers are never modified.

The review-only SQL candidate requires the existing reviewed OFF v2 backend. It adds a restrictive SELECT policy and guards the SECURITY DEFINER readers. Existing company membership and role checks remain in force. A header declares representation support; it is not authentication, device attestation, or proof of app identity. A caller can forge it without gaining company access.

## Verification

The fixture verifier reuses the expense fixture and real v1/v2 candidate. It confirms:
- Legacy rows remain readable without the header.
- V2 table rows and both RPCs reject absent, wrong, numeric, malformed and non-object headers.
- The exact string version permits the authorized reader.
- A nonmember cannot gain access using the header.
- Saved documents and reader owner, ACL, search_path and security mode remain unchanged.
- Reapplication fails instead of silently accepting an unknown baseline.

Run from the repository root:
`node tool/verify_payment_expense_source_negotiation.mjs file:///absolute/path/to/pglite/dist/index.js`

The fixture uses test.uid, not an issued JWT. Real PostgREST/JWT checks, native restored-DB rehearsal, guarded deployment/undo, and Flutter CI remain separate gates. This candidate is outside migrations and must not be auto-applied.

## Rollout constraints

Ship a new app containing the header before enabling the company v2 gate or converting its draft. Installed 0.2.0(5) does not contain this header. Do not treat hidden v2 rows in an old app as deleted documents. Preserve confirmed documents, manual edits, consumption and settlement history.

No production DDL, gate change, conversion, upload or installation is performed by this PR.
