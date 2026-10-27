# Apple OFF deployment and root recovery candidate

This reuses the existing four Apple protection/enrollment modules, adding only
root-maintenance reconciliation and retention plus an atomic deployment envelope.
It does not configure hosted Auth, link a real identity, change a session, seed an
allowlist, enable Apple or set a rollout row.

## Source and generated artifacts

`prepare.py` combines the five explicitly listed review-only source transactions
in dependency order into one BEGIN/COMMIT. The production-pinned
`install-off.guarded.sql.review-only` and `restore-unused.guarded.sql.review-only`
are generated only with `--snapshot production-before.private.json`; that snapshot
is an earlier read-only managed catalogue, not fresh approval or a row backup.
The full source metadata is preserved separately in
`production-catalog.private.json`. Root must refresh the catalogue, compare all
pins and retain the originals in the existing durable backup before deployment.
An unknown difference aborts; never remove a pin to force installation.

`verify_isolated.mjs` generates **fixture-before.json**, **fixture-install.sql** and
**fixture-restore.sql** from its disposable database's own OIDs. Those files are
not production inputs and the verifier never writes the production-pinned SQL or
manifest. Source hashes in manifest.json bind all five components, including the
new root-recovery source. No fixture or captured private catalogue is exported to
Git by the transfer list.

## Installation boundary

The single transaction bounds lock waits to 5 seconds and statement execution to
45 seconds. It requires the postgres operator/session, five absent module schemas,
six absent public APIs, exact Auth/company/deletion table catalogue and existing
Auth helper/schema/default ACL fingerprints, and actual TRIGGER privilege plus
managed drop-trigger permission. It locks the five relevant existing relations,
compares whole-row multiset counts/digests internally before/after, installs one
OFF identity guard and the new private routines, and verifies original catalogue
and helper preservation. Actual user/session/identity/password/metadata row
payloads are not returned, copied into fixtures or stored in the catalogue file.

The six public broker RPCs are service-only and additionally require the existing
server-call context. Root reconciliation/retention functions have no client or
service grants. Empty policy and rollout tables mean OFF; access-token hook
configuration, provider configuration and external endpoint deployment remain
separate prerequisites. Managed TRIGGER/drop permissions were read from metadata,
but actual managed DDL operation has not been attempted by this candidate.

## Never-used removal and emergency handling

Unused restoration requires the same root operator/session, original managed
catalogue, exact installed module catalogue/function/sequence metadata, no module
rows, no statement-level use mark, and no unknown outside dependencies. It removes
the identity trigger, APIs and modules in reverse dependency order with RESTRICT,
never CASCADE, and proves all original catalogue fingerprints and existing row
digests are restored. A use mark remains even after configuration rows are deleted.
Do not delete real history to satisfy this guard.

Root must independently confirm that hosted hooks and endpoints are unconfigured
and set the transaction attestation
`sko.apple_restore_hooks_and_endpoints_unconfigured=true`. This operator statement
is **not** automated evidence of hosted settings; SQL alone cannot inspect those
settings. Once used/configured, this removal is unavailable. Stop new enrollment,
retain protection/ownership/replay state and review each HOLD instead of dropping
the guard or changing a UID.

## HOLD reconciliation and retained history

`reconcile_request` is root-only, reasoned and command-idempotent. It drains actual
identity writers, locks the current actor/session/company context without waiting
in reverse row-lock order, and requires current same-UID protection and exact
saved credential/profile/company/Google context. A committed same-UID Apple link
can become completed; a provably absent link can become cancelled after removing
only that actor's temporary subject permit. Changed/deleted accounts or ambiguous
identity state remain held for manual review. It never edits auth.users,
auth.identities, auth.sessions or company membership.

Explicit retention (30–3650 days) redacts only old completed/cancelled request
snapshots in bounded batches (1–1000). NULL limits/reasons are rejected before any
state mutation; `LIMIT NULL` cannot turn into an unbounded cleanup. HOLD snapshots,
actor/subject ownership, used-token replay tombstones, original context hashes and
append-only reasoned recovery outcomes remain. No scheduler, default deletion,
credential reset, subject reassignment or automatic HOLD release is installed.

## Verification and remaining prerequisites

Prior MethodChannel/Swift/iOSSDK/Dart/GoTrue successes are reused. New PGlite checks
cover six recovery/retention cases and 21 deployment/restore assertions. Native CI
also exercises same-command reconciliation and an actual in-flight identity write
drain; until CI succeeds those two races are not complete. Synthetic runtime setup
uses a fixture-only service-call context and cannot substitute for managed GoTrue
configuration or the owner's iPhone test.

Remaining: root exact-head CI review/main integration; fresh managed snapshot and
durable backup; guarded OFF installation/receipts; hosted password-isolation,
native-only, token-hook and provider settings; actual endpoint/key resolver/rate
limits; current-Google/Face ID and Apple device verification; explicit approval
and evidence before enabling any gate. Apple-only new signup policy remains a
separate unresolved boundary. No deployment, activation or public invitation has
happened here.
