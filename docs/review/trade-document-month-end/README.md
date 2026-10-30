# Month-end and registered issuer presentation candidate

Not deployed. The live metadata read found no `validate_trade_document_form_fields`; install and review the existing v1 form guard prerequisites before this guarded v2 extension. Do not skip predecessor checks. No application rows are changed by this candidate.

Schema 1 remains exact and numeric day 31 remains 31日. Schema 2 adds only the exact `month_end` progress cutoff plus editable role/amount captions. The role is a document label, not a replacement for registered representative identity. The workspace capability is returned only through the existing authorized source. Missing capability blocks extended attached inputs; local standalone PDF generation supports the new fields without claiming persistence.

Only new form initial values receive the user-requested defaults; existing form fields, explicit blanks, saved parties, signatures, bank, terms and financial amounts are retained. Contacts come from the authorized own company; no name/phone fallback invents a company.

New order and acceptance drafts use とび工事; the editable amount caption
下記「施工単価内訳書」による; all three payment choices 無; month-end progress
cutoff; 10日 invoice cutoff; 100% cash; 翌々月5日 payment; 仮設材他 supplies; and
`[特記事項]　（右記工事請負契約条項に記載されてない事項を記入）` once.
The first of nine rows contains とび工　安全施設・足場組立解体作業（一般作業員）,
quantity 1, unit 人日, and **null unit price and line amount**. No rate from the
reference scan is invented and no financial source values are recalculated.

Automatic appendices respect existing auto-generation OFF and saved snapshots.
Only unsaved, unlocked adopted forms opt into defaults. A marked historical form
without `form_fields` is not a new document merely because that key is absent.
The normal invoice builder already loads an authorized workspace and appends the
resolved acceptance. Its multi-page order is corrected to all invoice details,
acceptance front, complete terms, then expense details. The user's exact missing
attachment cause remains unproven: explicit null, disabled auto-generation, or a
missing persisted invoice ID/revision are distinct paths, not grounds for a
silent forced attachment.

Both issuer headers share one layout relative to the unchanged formal grid.
The company-name right edge retains its seal anchor; the representative occupies
a separate full-width row below the seal, so short company names do not shrink
the representative into an illegible space. Registered contacts can be refreshed
only with explicit confirmation, current authorized workspace/version checks,
and the normal explicit save. Existing snapshots are not overwritten on load.

The SQL supports either exact original source or exact bank-wrapper predecessor;
the bank wrapper remains byte-for-byte unchanged while its original delegate is
extended. Owners, ACLs, security flags, search paths, OIDs and other function
attributes are checked before and after. Authentication and source financial
guards are retained. This is not an installation or a production authorization.

Local verification: PGlite core 45 checks and bank 46 checks passed against the
full existing form fixture. An initial harness JSON-literal escaping error was
fixed before SQL ran; the first bank run correctly rejected an unhandled bank
predecessor, followed by explicit predecessor support rather than bypassing the
guard. Native PostgreSQL, Flutter analyzer/widget tests and actual rendered PDF
checks are separately configured in `trade-document-month-end.yml`; their result
must be read from the actual CI head. No local Flutter SDK is available.
