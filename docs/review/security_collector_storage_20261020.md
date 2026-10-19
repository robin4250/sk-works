# Decoy collector storage: isolated review slice

Status: review-only; deployment_ready=false. No production migration or deployment.

## Purpose and boundary

The existing decoy lab and transport are loopback fixtures. Their synthetic
incident contract remains unchanged. This candidate defines a distinct private
store for trusted collector observations; touching a lure never confirms an
attack, identifies a person, or authorizes automatic blocking.

The candidate deliberately has no public RPC, HTTP listener, Edge deployment,
SMS/email/notification dispatch, DNS, secrets, source IP storage, or production
account edits. It cannot make the honeypot or moving target defense operational.

## Implemented slice

- Three private RLS tables: default-OFF read/ingest controls, sanitized events,
  and master read audit. No API-role table grants or policies.
- Separately provisioned NOLOGIN/NOINHERIT collector bridge role, validated to
  have no superuser/BYPASSRLS/role creation/replication/database creation powers.
  The role receives only schema usage and one ingest function. No direct table
  read/write, audit mutation, or master read authority is granted.
- Ingest accepts exactly seven fields: random event and collector UUIDs,
  observed timestamp, current/retired-lure event kind, bounded generation,
  64-lowercase-hex correlation pseudonym and UTC daily key epoch. Unknown keys,
  null/wrong types, raw addresses, stale/future observations and altered retries
  fail. Identical retries do not duplicate events.
- Received timestamp and provenance are server generated. Trusted collector
  credentials can still falsify an observation; role isolation is not an
  independent proof of the request's origin or of malicious activity.
- Master-only reading rechecks account access and requires consumption of a
  separate `master.security_collector.read` / `{"scope":"decoy_collector"}`
  proof. This operation/scope is a prerequisite, not registered by this slice.
  Successful reads record the server actor, time and count transactionally.
  If audit insertion fails, proof consumption and reading roll back together.
- Returned observations are capped at 100 from the last seven days. This is a
  bounded query window, not a deletion/retention job or continuous coverage.

## Verification

`tool/security/verify_collector_storage_candidate.mjs` passes 60 assertions in
PGlite 0.3.14 with synthetic roles, auth and a one-use proof fixture. It checks
direct/transitive bridge membership, upstream role membership and privileged-role rejection, default-OFF
gates, anon/authenticated/service_role ingest denial, lack of table
permissions, writer isolation, metadata allowlist, malformed/stale/forged data,
idempotence/conflict, master/account restrictions, proof reuse and audit failure
rollback. It returns both fixture gates OFF.

The proof fixture is not the production issuer. No native PostgreSQL 17,
production RLS, real Auth session, external signatures, OS isolation, concurrent
writers, provider rate limits or actual intrusion tests are claimed here.

## Remaining deployment prerequisites

1. Separate decoy execution environment with no production credentials and
   independently verified host-level outbound deny rules; bound inbound bytes,
   connections and rate limits before the process. Do not deploy the privileged
   collector bridge inside the exposed decoy process.
2. Trusted collection pipeline outside the lure: authenticate and enroll actual
   collector identities, enforce signature/replay bounds, use short-lived
   scoped credentials, rotate keys and pseudonym epochs, and test compromise
   recovery. A caller-provided collector UUID alone is not authentication.
3. Register the new proof operation/scope in the existing issuer and verify its
   exact actor/session/lifecycle/revocation behavior; use a reviewed private-to-
   public read adapter and master UI that displays the distinct provenance.
4. Persist collection gaps, retries and dropped-event counters; define and test
   capacity/backpressure and deletion retention before enabling ingestion. The
   seven-day read filter alone leaves stored records on disk.
5. Native PostgreSQL role/concurrency verification, backup/restore/checkpoint,
   independent security review and rehearsal in an isolated environment.
6. Only after prerequisites: an explicit deployment plan, bridge principal
   provisioning with least privilege, reviewed real transport, rollout and
   default-OFF gate activation. Existing synthetic incidents stay separate.

This slice changes neither live application endpoint locations nor business
routes. Moving target rotation, lure retirement tracking and recovery controls
remain separate work; they must never rotate or interrupt real login endpoints.
