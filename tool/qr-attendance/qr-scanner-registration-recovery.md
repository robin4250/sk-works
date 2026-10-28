# QR scanner registration result reconciliation — OFF candidate

Before this candidate, an acknowledgement lost after a successful registration
COMMIT left the proof and key challenge consumed. Retrying registration rejects,
and challenge delivery deliberately hides consumed rows. It cannot prove whether
the original registration committed.

The new private SQL wrapper calls the **existing** exact-target proof consumer,
scanner registry writer and audit writer, consumes the original key challenge,
and records an exact-challenge receipt in the same transaction. It acquires the
existing per-device advisory lock and binds the one newly written audit event.
The request adapter first verifies the real Ed25519 challenge signature. A late
receipt insert failure rolls back registry, proof, challenge and audit together.
It does not substitute the subject employee's Auth identity.

The receipt records the original company/actor/SID/device/public key and actual
audit event. Its FKs refer only to review-only QR candidate tables; no Auth,
session or business-table FK/table is changed. No original rows are backfilled.
Existing unreceipted rows retain their old deletion behavior. Newly receipted
challenge/audit originals are retained through NO ACTION FKs, while receipt
UPDATE/DELETE/TRUNCATE is rejected. There is no cascade, automatic deletion or
claim of independent immutable custody: an owner/privileged actor could disable
guards or roll back storage. Retention/erasure/restore and deployment guards
remain unreviewed activation blockers.

`createRecoverableScannerRegistrationAdapter` is default OFF and allows only
one attempt per request instance. Unknown COMMIT returns no success and cannot
automatically resend or re-register. A separate authenticated read requires the
same original live SID, current company/attendance permission and QR gate, plus
the exact original key still active in the scanner registry. It returns the
same historical receipt after challenge expiry without extending expiry or
consuming another proof. Changed/revoked keys, another SID (even same UID),
deleted/expired sessions or OFF deny receipt access. This neither activates a
device nor reverses revocation. A missing receipt is an unknown/unconfirmed
outcome, not permission to reissue a challenge or repeat registration.

Local validation: seven new Node tests, plus existing exact-proof/PoP composition
executed through the new wrapper on isolated PGlite 0.5.8 with pgcrypto. The SQL
suite covers lost COMMIT, repeat read/no extra audit, replay/expiry/revocation/
key/SID rejection, new receipt retention, unchanged unreceipted deletion,
TRUNCATE denial, ACL and full rollback on a late receipt failure. Native PG
concurrent completion and the disposable real-GoTrue composition are added to
dedicated CI and must not be reported passed before that CI completes.

The real-GoTrue fixture adds unknown-COMMIT recovery and same-UID other-SID
rejection through the exact-bearer verifier. Business permissions and the DB
pool remain explicit fixtures. No listener/public endpoint, production grant,
real device key custody, canonical attendance writer, QR verification mode,
photo/route/report compatibility, production deployment or iPhone verification
is completed. The legacy private adapter remains unchanged and is not silently
made recoverable; all registration routes need a separate activation review.
