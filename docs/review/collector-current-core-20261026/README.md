# Collector-only current-core connection (review candidate)

Base main `74d4c2f578e26ca1f7f21628f19a1da6b2fdeee9`. No production application,
key provisioning, gate activation or external notification is performed here.
The earlier bridge-only bounded installer remains historical and is not an
alternate executable path for this candidate. It assumes an absent three-scope
proof core and must not be run over the now-installed four-scope core.

## Reused successful evidence

- PR1375 `643d52ca`, bounded lifecycle CI40134204286: success. Its documented
  managed-role refusal is valid, not a reason to remove catalog guards.
- PR1339 `d2f76aa7`, native transport CI40048570839: success, 14 HTTP/SQL cases.
- PR1345/1346: existing real GoTrue issuer and POST-reader tests succeeded.
- PR1372 `7a5a639f`, client CI40137740854 plus Flutter/iOS: success.
- The later strict calendar correction `69a235fa` passed client CI40163393038.

These retained results do not certify this changed current-core connection.

## Changed trust boundary

No bridge role is created or required. The isolated decoy receives neither a
Supabase service key nor employee/financial data. Only the trusted ingest Edge
has a service key. Its independent collector signing key authenticates a bounded
metadata-only envelope; it is never an access-proof key or user password.

Both the Edge and the service-only database RPC verify raw-byte HMAC SHA256,
collector ID, key version, timestamp and active key configuration. The version-2
domain is `sko-collector-v2\n<collector-id>\n<key-version>\n<milliseconds>\n`
followed by unchanged UTF-8 event bytes. The transport clock window is ±60 seconds;
the exact original seven metadata fields, daily correlation epoch and original
10-minute event age bounds remain enforced. The database additionally rejects
duplicate JSON keys. No client-selected RPC URL, table, actor, recipient or SQL
is accepted. Constant-length MAC comparison always examines 32 bytes.

The previous strict metadata validator and same-event dedupe/conflict behavior
are retained without changing their function body. Their old bridge grants are
removed from assembly: owner-only ingestion is reached only through the new
service-only signature-verifying wrapper. Keys, signed evidence and retention
audit have RLS and no direct API grants. Master output retains the original nine
event fields; no raw payload, key, signature or credential is returned to it.

The existing core is not reapplied. Only its exact current private operation
mapping and private issuer target check are extended for
`master.security_collector.read` / `{"scope":"decoy_collector"}`. The public
issuer and consumer stay unchanged. All four existing scope rows and their
values stay unchanged. The existing reauthentication Edge receives only the
corresponding two registration/validation lines. Attendance entry behavior is
not edited or activated by this work.

## Durable evidence, expiry and recovery boundaries

Signed original metadata bytes and first-receipt key version are retained beside
the event. An identical retry never overwrites that evidence; a conflicting same
event ID fails atomically. Revoking/rotating a key denies fresh ingress but keeps
historical evidence verifiable. Master reads fail atomically on an event/evidence
mismatch instead of showing an apparently clean partial record. Failed reads do
not consume their one-use proof or commit a read audit.

Owner-only fixed expiry removes events/evidence older than seven days, reads older
than 90 days, inactive keys without evidence after their grace period, and retention
audits older than 365 days. Each category is bounded to 1000 rows per call, and the
new audit records counts plus the removed event-set digest. No caller-selected
cutoff or business table is available. RPC/read/purge lock waits are bounded to one
second; five-second statement settings are pinned. Scheduling and an independent
external integrity anchor still need operational review. HMAC keys live in an owner-only registry, so this is not a
claim of tamper-proof evidence against the database owner or a compromised key
administrator. Existing private/API role separation and signed-payload checks do
not replace independent monitoring or a separately retained integrity checkpoint.

Installation starts with no registry keys and both collector gates OFF. The
separate Edge defaults OFF with no keys. Root performs final secret provisioning,
activation and live delivery only after reviewed infrastructure isolation and
fresh backups. A malformed secret configuration fails without printing it.

Unused restoration reinstates exact old function OIDs and full pg_proc metadata,
preserves the existing core/tables/proofs/roles and uses explicit reverse DROP
without CASCADE. Key provisioning, retained events/read audit, used audit sequences
or collector proofs block unused removal. Unknown external dependencies cause a
complete rollback. Used data is never removed by this unused-only restoration.

## Validation status

Local Node: current reauthentication handler 34 checks and new ingest handler 28
checks passed. Earlier PR1438 head `9270fcd558c36890b204d3d8aeb1f8c28087e61d`
passed Native66 and Node59 in CI40282966694. The expanded connection below requires
new exact-head CI; the earlier result is retained and is not relabelled. No local Flutter/Dart or local database was run. The new remote
PostgreSQL17 fixture covers current four-scope install, exact unused restore,
unknown-dependency refusal, signed ingress, wrong signature/source/version/time,
rotation/revocation, duplicate-key rejection, committed-ACK retry and transaction
rollback, API role denial, Master/current-session one-use reads, other-company
non-Master denial, integrity refusal and fixed retention. Its auth surroundings
are explicitly synthetic; it does not claim real GoTrue issuance or production
RLS. Record exact new CI results before claiming it succeeded.

Hosting, ingress admission/rate/concurrency controls, producer isolation and
delivery, production secret creation/rotation/recovery, monitoring/notification,
external audit anchoring, all live gates and iPhone confirmation remain incomplete.

## API credential and expanded integration boundary

The preserved reauthentication handler already had correct legacy Bearer/opaque
secret branching and `redirect:'error'`; its product diff remains two collector
operation lines. No duplicate credential fix is applied to that original. The
new ingest handler sends a legacy service JWT as both `apikey` and Bearer, and
uses `apikey` only for an opaque `sb_secret_` key. It never forwards incoming user
authorization. Upstream redirects are errors. An outer five-second deadline also
returns when an injected adapter ignores AbortSignal.

The expanded Native fixture runs actual loopback ingress HTTP through the new
handler and actual PostgREST16.4 JWT verification into PostgreSQL17. Its fixed URL
adapter changes only the fixture destination, never credentials or role claims.
Legacy `apikey` alone is separately denied. Existing PR1435 producer blob
`8e6251baff86cb70b22b521beb72f5d7f0c665e8` is reused unchanged and its actual body is
signed with the version-2 domain. Physical revocation/ingress lock ordering, a real
one-second locked-row refusal, and bounded latest-100 verification are included.
An additional focused disposable GoTrue/Edge/PostgREST fixture verifies the newly
registered operation, primary password denial, anonymous/authenticated service
impersonation refusal, current-session proof binding and cleanup of only the
distinct temporary credential-check session. It does not rerun unrelated device
or account-edit suites as new evidence.

Opaque key Gateway translation remains an actual hosted-platform deployment check,
not a simulated local-PostgREST success. The default index uses the existing legacy
`SUPABASE_SERVICE_ROLE_KEY`; root may explicitly select a named entry from
`SUPABASE_SECRET_KEYS` with `SKO_COLLECTOR_SERVICE_KEY_NAME` after that check. No
legacy keys are rotated/deactivated by this code. Key provisioning remains separate.

Primary references checked: [API keys](https://supabase.com/docs/guides/getting-started/api-keys),
[API-key migration](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys),
and [legacy service-role authorization](https://supabase.com/kb/troubleshooting/why-is-my-service-role-key-client-getting-rls-errors-or-not-returning-data-7_1K9z).
