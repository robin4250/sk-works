# Persisted issuer continuity and owner-evidence composition — OFF candidate

The pure continuity verifier is now connected to a private PostgreSQL head and
signed-transition inventory. `commitOwnerIssuerTransition` captures own-data
proposal/checkpoint snapshots before acquiring a connection, locks the exact
authority head, reuses the existing verifier against DB time, appends original
canonical payload/old+new signatures and both pins, then compares-and-swaps the
entire old pin/epoch to the verified successor in the same transaction. A final
DB-clock expiry condition still applies at the update. No automatic retry occurs.

The private ledger has unique authority/from-epoch, to-epoch and transition-head
keys plus an ordinary append-only trigger. Failed insert/update, unexpected
full-pin state or expiry rolls both head and original signed history back.
Separate PostgreSQL connections racing a duplicate or sibling fork can commit
only one transition. The losing caller must not treat refusal as successful
rotation; unknown commit outcomes need independently authenticated reconciliation.
No reconciliation endpoint or external checkpoint publisher is implemented.

`recordOwnerDecisionUsingStoredIssuer` is a new, default-OFF entry into the
existing owner-evidence transaction, not a separate evidence writer. It loads
the stored current issuer under a shared row lock, validates the full supplied
authority checkpoint (including current key and retired-history digests), and
uses the existing live-session/device/challenge/pending/request, cancellation,
signature and append-only evidence checks. The issuer lock precedes the existing
device -> challenge/pending -> request order and is held through evidence commit.
Rotation waits for an already admitted receipt; receipts beginning after rotation
cannot use the retired issuer. Historical signed receipt bytes remain intact.

The earlier fixed-pin evidence entry remains unchanged for existing OFF callers.
This is not enforcement across a deployed public handler. Any future rollout must
select the stored-issuer entry server-side and close fixed-pin fallbacks/low-level
paths; no request may choose its issuer mode, checkpoint, authority or DB pool.

## External trust remains external

The SQL seeds no genesis and exposes no bootstrap API. An already independently
reviewed authority pin must exist. The supplied checkpoint still must be freshly
authenticated from the real external authority; the adapter does not fetch or
authenticate it. Two stale local copies remain insufficient anti-rollback proof.
Local row locks/CAS reject concurrent local forks, not privileged DB rollback or
an external authority fork. A privileged operator can disable ledger triggers.
No independent custody, source-owner identity, lost-old-key recovery, management
API, publication or deployment is delivered. Only public verification keys and
signed protocol evidence are stored; no private signer key is accepted.

No original master device/key, active-key mapping, password, Auth configuration,
production DB/grant, signed document or individual-document-exemption OFF flag is
changed. Devices remain pending; there is no actual key activation or route.

## Scoped verification

The disposable composition reuses actual candidate possession-to-pending and
owner-request code before invoking the actual owner-evidence consumer with the
persisted issuer. It checks default-OFF zero acquisition, signed-history retention
and later verification, replay/stale-fork rejection, old-issuer/stale-checkpoint
and replaced-history refusal, unchanged original receipt bytes, full-pin CAS miss
and late-update-failure rollback, pre-await caller-mutation snapshots, client ACL
and ordinary UPDATE/DELETE/TRUNCATE refusal, and unchanged legacy devices/keys.
The PGlite composition passed locally, as did the existing 15 continuity/receipt
unit cases after the shared checkpoint-validation refactor.

The native PostgreSQL runner additionally races separate connections for identical
and sibling transitions and observes a real `pg_stat_activity` lock wait while
the actual receipt transaction holds its issuer share lock. Native CI is pending
for this head and is not represented by the local PGlite result. Authority signers,
checkpoints and Auth identities are explicit synthetic fixtures. Real external
authority/managed Auth/least-privilege pool and device verification remain required.
