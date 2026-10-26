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
than 90 days and records deletion counts plus the removed event-set digest. No
caller-selected cutoff or business table is available. Scheduling this function,
retention of its own audit and an independent external integrity anchor still need
operational review. HMAC keys live in an owner-only registry, so this is not a
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

Local Node: current reauthentication handler 33 checks and new ingest handler 24
checks passed. No local Flutter/Dart or local database was run. The new remote
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
