# Site outgoing editor/body adapter (source only)

The shared `TradeDocumentTouchEditorPage` and `TradeDocumentFormDraft` remain
unchanged. The site-specific factory consumes a verified, captured source
context plus the existing exact `TradeDocumentTermsSnapshot` reference. Its
six-field content-addressed terms reference is the same reference checked by
the canonical artifact job; it does not fetch or invent a contract version.

New creation initializes the already adopted form defaults only. Missing total,
tax, row unit price and row amount remain null, so validation blocks preparation
until explicitly supplied. Null site periods stay blank. Reopening a prepared
body never calls default initialization, preserving payment conditions, explicit
blanks and saved terms. Incoming orders must follow their existing receiver flow;
this adapter accepts only the captured issuer's own `order` direction.

The editor requires `company_seal_snapshot` to draw its preview, whereas the
canonical prepare contract explicitly rejects that field and
`company_seal_enabled`. The adapter verifies the frozen editor snapshot and
removes only these two fields from a validated canonical candidate. The server
continues to derive actual consent/seal evidence from its own registered source.
Editable fields cannot replace company identities, parties, transaction, seal
or terms. Amounts never update payroll, invoices or source rows.

This factory is neither permission nor proof that a document is new. The future
writer must capture current company/session, keep the body RAM-only, durably
save request IDs before HTTP, require unchanged source/seal digests and use
expected revision zero. The existing canonical prepare must reject collisions.
Prepared server bodies must be retrieved, displayed and explicitly reviewed
before the same-transaction unsigned guard plus consent wrapper is called.

Remaining: real editor route, retained input on back navigation, counterparty
selection, source refresh admission, guarded preview/consent, original/PDF/send
terminal receipt reconciliation, full production catalog composition and hosted
deployment. No new route or writer is activated by this source contract.
