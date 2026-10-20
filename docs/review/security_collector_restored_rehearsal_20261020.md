# Collector storage on the verified restored database: rehearsal candidate

Review only. No production DDL, gate activation, real event ingestion, signature transport, public endpoint, master login or moving-target rollout.

## Current dependency blocker

Read-only catalog checks on 2026-10-20 found no `private.consume_reauthentication_proof(text,jsonb,text)` and no private/public reauthentication-named routine. Existing account/master predicates are present; collector bridge role and event table are absent. The reviewed collector candidate explicitly requires this proof consumer. Its existence is a necessary dependency, not proof that `master.security_collector.read` with scope `{"scope":"decoy_collector"}` is registered or correctly implemented.

Do not ask the owner to run this rehearsal while that prerequisite is known missing. The helper will stop before collector installation; it will never create a permissive replacement proof verifier. Reuse the existing reviewed Master proof contract and verify it separately before this candidate can run successfully on the actual restored snapshot.

## Reused originals

- `owner_expense_off_rehearsal.py`: verified stopped restore source `database-restore-01qyi5py`, pinned Supabase PostgreSQL image digest, no-network clone command and exact observed database owner/ACL normalization. This module is imported without invoking its main function. Ship the existing hash-verified helper as a sibling; do not change the original expense script.
- Original `security_collector_storage_v1_20261020.sql.review-only` candidate, SHA256 `b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207`, bundled unchanged. Only its single outer BEGIN/COMMIT is removed to run inside the rehearsal's rollback transaction.
- Existing collector synthetic fixture: retained for SQL scenario smoke validation and the earlier separate PGlite/native PostgreSQL evidence. Successful synthetic proof fixtures are not substituted for the restored proof implementation.

## Procedure implemented

The Mac helper validates a local Unix Docker context, private backup directory, successful stopped original restore record, original container label, pinned base image, no network and no published ports. It commits the stopped local container to a private local image and starts a separate clone with `--network=none`, no mounts/ports, cron OFF and Unix-only PostgreSQL. It never starts/stops or changes the original container and never pushes the private image.

Only the clone database owner/ACL is matched to the already observed production baseline. The helper verifies prerequisites, privately captures all existing custom routine/role/membership/schema/relation/policy/trigger metadata and digests every ordinary table in public/private/auth/storage/vault/cron. Existing sequence state is captured separately, because transaction rollback does not reset a previously advanced sequence.

Inside one transaction it provisions a NOLOGIN/NOINHERIT unprivileged bridge, installs the original collector SQL, verifies both gates OFF, rejects API-role ingest/table access, temporarily enables clone-only ingest, and checks a single synthetic event, identical retry, changed retry conflict, unapproved metadata/stale event rejection and bridge read isolation. Restored account/master/proof functions are not replaced; actorless master reading must fail. It returns the test gates OFF, rolls back the entire transaction, then compares the metadata, table set/digests and sequence state with baseline and verifies all candidate objects/role are absent.

The clone is stopped in finally. A failed stop prevents a verified-success result. Result text is automatically copied with pbcopy. Private snapshots and error logs stay in a new `collector-restored-rehearsal-*` directory. Nothing containing real IDs, rows, function definitions or credentials is printed or uploaded by the helper.

## Verification so far

- Python lifecycle/source-boundary tests: 6 passed, including missing dependency refusal before install, failed SQL clone cleanup, original-container preservation and refusal to report success if stopping fails.
- Existing synthetic PGlite fixture: new scenario SQL, role switching, candidate transaction and rollback passed. Metadata/table/sequence query syntax also executed successfully.
- Actual restored DB execution: not performed. Currently blocked by the absent real proof consumer.
- Real signatures/collector enrollment, Master proof issuance/consumption success, HTTP ingress, external isolation, concurrency, rotation, retention, operational logging and actual honeypot/moving-target behavior: not established by this rehearsal.
