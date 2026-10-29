# Adopted SKO order / acceptance form candidate

The approved original form is identified by SHA256
`942bad918b696b4c2c527dbf2fca9d050e4fb38a3674cff115eb0755793b8a18`.
Its exact measured geometry is preserved in
`docs/fixtures/trade-document-design/original-design-20261029.json` and the
matching Dart constant: A4 portrait, 34pt side margins, the original column
ratios, vertically merged 支払方法, unselected 有・無 labels and nine data rows.
Registered snapshot company names replace the sample names. No sample company
or photographed seal is copied into product output. Order: issuer=own ordering
company, counterparty=supplier. Acceptance: issuer=own accepting company,
counterparty=customer. The own registered seal, when enabled and verified by
name, overlaps the measured right end of that company's printed name, contained
inside its header row. Disabled/empty seal metadata prints unsigned; no new seal
is invented from an empty snapshot. A different registered name fails closed.

## Immutable legal source and renderer selection

The user-confirmed source is preserved byte for byte at
`docs/fixtures/trade-document-terms/user-confirmed-20261029-v1.json`.
SHA256: `3acf9090f2c027840bba43351f4d9e173759baa8b7c0340c05db9e28731f0d1f`.
The 22 `[title, paragraphs]` entries are never corrected, paraphrased or reordered.
The generated Dart constant embeds those exact JSON bytes. Unit tests compare
the bytes/hash and every original title/paragraph to the permanent source file.

New unlocked, unsaved monthly drafts and new standalone order/acceptance payloads
receive the strict `contract_terms` reference: schema, version, title, source
hash, renderer contract `sko-original-form-20261029-v1`, and approved design hash.
This immutable content-addressed reference binds both the legal source and form
version without consuming the unchanged 16KiB attachment limit. It selects the
adopted form front and the second A4 page `[ 工事請負契約条項 ]`. Unknown version,
hash, title, renderer, null or extra fields fail closed. No-reference historical
bodies continue through the exact previous front renderer and get no new page.
Future versions MUST append registry entries and retain every historical source
JSON, design geometry and renderer implementation. Never replace/delete v1.

Existing attachment saving preserves the reference. Confirmation SQL excludes
only seal metadata when copying attachment fields into the approved body; the
canonical body hash therefore includes the complete reference. Exact-SQL
fixtures verify requested body omission is refused, body hashing, issuer consent,
preview, issued, received and archive all preserve it for order and acceptance.
Stored PDFs, original signatures and historical bodies are never rewritten.
The seal renderer contract is separately checked by the existing approval
adapter; it does not substitute for the body-hashed form/terms contract.

## Review-only saved-reference guard

`docs/review/trade-document-terms/save-guard.sql.review-only` accepts only two
exact predecessor pairs, with body hashes, owner, ACL, volatility, security and
search_path pinned:

- Current original source `ebcc7093...` / save `82fa3793...` -> terms wrapper.
- Frozen supplier-bank source `1f877168...` / save `b7711fe5...` -> terms wrapper,
  with the original source/save delegates additionally pinned and retained.

The bank candidate must precede terms when both are reviewed together. Applying
bank after terms or applying terms twice fails closed. Original save bodies
remain intact behind owner-only delegates; canonical authenticated ACL remains
unchanged. The wrapper takes the original appendix advisory lock, performs
original source/company/management admission, locks the selected saved row, then
requires existing terms reference OR absence to remain exactly unchanged. First
save allows legacy absence or the known exact reference; unknown references are
refused. Original 16KiB, CAS, locked, source_changed, seal and bank snapshot guards
still execute inside the unchanged delegate. No production SQL, grants, flags,
data or Auth helpers were applied/changed by preparing this candidate.

## Routing and actual evidence

Existing entry routing is preserved and widget-tested: customer/取引会社 ->
standalone acceptance, subcontractor/協力会社 -> standalone order. Monthly invoice
uses acceptance; payment certificate uses order. Canonical supplier ID, never
names, selects an optional supplier-bank snapshot on orders only. Acceptance
adds no bank lookup. A parent invoice/payment first page plus a new two-page
appendix is a three-page bundle, while old saved/locked bundles stay unchanged.

Local PGlite checks use synthetic Auth/catalog data: base confirmation238 plus
saved-reference18 checks; supplier-bank49 plus saved-reference18. Native SQL,
Flutter/routing, all22 legal text, original geometry, name/stamp placement and
actual rendered pages require successful CI on the published exact head.
The legacy comparison renders the exact pre-change parent source in a temporary
CI copy, restores corrected files with a trap and SHA256 verification, and
compares the unmarked legacy pixels/text against the corrected source output.

## Explicit remaining stages

The existing work/date/amount/conditions/notes inputs supply available snapshots.
New structured nine-row detail, individual payment choices/dates/amounts and
phone/fax entry are NOT yet connected; their form cells remain blank rather than
being inferred from totals or free prose. The visible grouped input/settings
entry on each generator is a required follow-up in this lane, not completed here.
Registered own/peer company identity must remain automatic and scope-bound.

A4 two-page canonical output is this increment. A3 landscape imposition and A4
long-edge-duplex output selection are further required work. They must preserve
canonical bytes, approved body/archive hashes and original signatures, and must
not expand received-document permissions or delivery. Physical printer/driver,
production rollout, supplier-bank activation and counterpart delivery remain
unverified. Root separately owns the People supplier-bank button hook.
