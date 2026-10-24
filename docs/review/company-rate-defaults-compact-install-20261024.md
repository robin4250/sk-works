# Compact full-checkpoint installer candidate

This adds separate preparation and Native parity verification files. It changes
neither the original generator nor the reviewed four-function candidate, its
authorization, original triggers, database objects, or operating instructions.
Production application is not part of this candidate.

The original installer repeats the complete private before-observation twice.
This candidate instead compares SHA256 of the **complete PostgreSQL JSONB text**.
Obtain that fingerprint together with the full observation from the generated
read-only query, keep both private, and strictly compare the returned observation
to the reviewed before checkpoint. Never derive the fingerprint by serializing
Python JSON, or substitute a fingerprint from a different observation. The
generator validates the original full checkpoint against the same manifest.

Before installation it repeats the exact original observer under the original
ordered company/rate locks and compares its server-side fingerprint. After
installation it removes exactly the four new routine signatures from that same
full observation, restores the four original missing routine names, and compares
the fingerprint again. No original relation, namespace, function, privilege,
definition, attribute or row-count/data-hash field is omitted. Additional
overloads remain in the observation and therefore fail the comparison.

All four newly installed functions additionally undergo the original explicit
source, owner, language, search-path, security-definer, volatility, return-type
and execute-ACL checks. The transaction retains postgres-only installation,
3-second lock/30-second statement limits, no application-row migration, and no
replacement or disabling of existing triggers. SHA256 comparison has the usual
cryptographic collision assumption; it is not a weaker selected-field check.

For the reviewed actual private checkpoint the generated candidate is 23,057
bytes, versus 114,626 bytes for the original. No private actual fingerprint is
stored in this repository. The read-only observation query returns both values
from the same transaction and includes the server encoding.

The dedicated PostgreSQL 17 proof applies the original full installer, removes
its code to restore the exact baseline, then exercises the compact installer on
that same baseline. It compares the installed definitions and attributes except
the newly allocated routine OIDs. It also checks wrong/stale fingerprints,
late-failure rollback, original-data mutation before postflight, added overload,
unknown default ACL, unchanged writer hashes, exact bounded code removal, and
refusal of removal after a legitimate fixture save. Authorization is synthetic,
and the invoice refresh leaf is a fixture recorder, as in the original proof.
Native CI must pass before an actual deployment candidate is considered ready.
