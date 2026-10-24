# Independent collector proof registration candidate

This is a new candidate built from actual main `71f7ec3a4a37a8137066db734e7d1c47b7f7c5c3`. It is not a reconstruction of the three missing historical collector scope/proof files, and does not recover their provenance. Do not merge it into build 12 or apply it to production during the release freeze.

## Current gap and bounded changes

Current main's handler has no `master.security_collector.read` entry. Both staged SQL scope mappers and issuers also lack that operation. The unchanged collector consumer requires that exact operation with target `{"scope":"decoy_collector"}`. The missing producer registration prevents an honest end-to-end success proof from the current sources alone.

The candidate changes only these existing implementation files:

- `supabase/functions/reauthenticate-operation/handler.mjs`: register the exact operation under existing `master_security`, and reject every other collector target shape/value before password verification.
- `tool/staged/reauthentication_proofs.sql`: register the exact operation and validate the exact collector target in its issuer.
- `tool/staged/master_device_lock_reauthentication.sql`: preserve that registration and validation when this staged unit replaces the mapper and issuer.

The SQL files are review-only staged units, not applied historical migrations. No migration/integrity manifest, rollout table, seed, production grant, default, master record, account, company or role is changed. Existing `master_security` remains OFF by default. Existing session/actor/operation/target/expiry/one-time consumption logic is reused without modification. The collector SQL remains byte-for-byte SHA256 `b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207`.

## New isolated proof and its limits

The new fixture reuses main's real local GoTrue/Edge/PostgREST test strategy and pinned Supabase CLI 2.121.0. It runs only in an owned disposable CI stack without hosted configuration. All user JWTs are issued by that local GoTrue. There is no user JWT fabrication or production connection.

Two RPC bridges are created only inside the fixture. Their `fixture_` names, source location in the test script and JSON receipt distinguish them from a product API. They preserve the real request JWT and call the exact existing private consumer/consume function. **Current product source still has no public collector read route or corresponding app wiring.** A passing test does not complete that missing interface or make the collector production-ready.

The fixture also creates a second Edge function containing the exact known baseline handler (main Git blob `61ba5442f997ff9c4b95c8495ea9787fbb77fbe4`, SHA256 `4dd554c9a298c312a88b255303e55324020b3dc81b21ee2e913b4cc530104be6`). Its bytes are obtained by removing only the two candidate additions and checked against that known hash. This is the known current baseline, not the missing historical collector-aware handler. With a real GoTrue JWT, it must reject the collector operation before creating a temporary password session or proof.

The candidate fixture then checks actual Edge password verification, distinct temporary-session cleanup, the original session remaining usable, the exact private collector read, one-time consumption, another master actor, another session, platform/collector scope separation, target shape/value, TTL, revoked session, default-OFF and disabled gates, and unchanged identity/provider/company/member/master/device values. Read-disabled failures must not burn a proof. The device extension is loaded after the base SQL so both registrations are exercised.

## Validation status

Local syntax checks passed. All 23 existing Node handler regressions passed. Native GoTrue/Edge/PostgREST execution is pending remote CI; do not describe prepared cases as passed. No production deployment, gate activation, real OAuth/SMS/email, real trusted producer, key provisioning, honeypot operation, dynamic defense, device validation or iPhone verification has occurred.

Official references checked while preparing: Supabase changelog (2026-10-24) and Auth session documentation. The current session documentation identifies JWT `session_id` with `auth.sessions` and recommends checking the row for sensitive operations after logout; this candidate retains the existing implementation of that check.
