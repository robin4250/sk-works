# Resident annual owner delivery candidate

This is a review-only alternative transport for the already prepared annual
resident-tax installation. It does not change SQL, migrations, authorization,
application code, or the original checkpoints. It has not connected to production
and is **not ready for an owner execution command**.

## Exact inputs and source

The fixed target is project `ztktgquxvcxcjxtluspu`, session-pooler host
`aws-0-ap-northeast-1.pooler.supabase.com`, port 5432. The runner accepts the exact
prepared SQL SHA256 `bd9f2a93b3762c4f8374e34de4562f1a8040bbd5011cdc084d2935113555ea20`,
the original private before checkpoint hash and original observer hash. The
private artifact bytes, runtime binding, credentials and observations are never
tracked in this source repository. The existing annual preparation generator
must match SHA256 `0952c04fb3bb0a1400c66c6e19377f5bb1ca12a43630070b81cf20ab69d3b656`;
its exact regenerated output must equal the prepared SQL before any connection.
This is a validation comparison, not replacement or regeneration of the input.

The original two owner capture helpers are copied byte for byte from the
reviewed expense source at `994342fc136045d8ce6769b55f606952111808e6` (original
helper lineage `fa87c9390f6ec08797c74538f9e3fae4d10389e0`). Their hashes are enforced
before import. The expense operator/bootstrap and its approval binding are not
used. Its `CliPsqlTransport` was not reused because its artifact names, manifest,
state machine and read-result shape are expense-specific.

The new psql boundary follows the original clean-environment and TLS strategy,
but is new code requiring its own proof. The owner-record CLI, psql and CA hashes
are pinned, not supplied as arbitrary executable hashes. The runtime-binding
private file only provides these fixed objects' absolute locations. The original
CLI parser obtains a short-lived connection through the signed-in official CLI,
never evals its output, and never opens token/keychain/password files. No such
operation has been run while preparing this candidate.

## Once-only installation and recovery

The dedicated owner folder is
`~/SKO-source-backups/resident-annual-owner-20261024` (0700). An exact read-only
before comparison precedes an exclusively created, fsynced attempt marker.
The exact installer is delivered at most once. A nonzero result, timeout,
interruption, missing acknowledgment or observation mismatch never permits a
resend. A new invocation may only run `recover`, which makes read-only calls.

Successful verification runs the existing reviewed SQL postflight in a
read-only transaction, compares consecutive observations, and prepares (but
never executes) the existing unused-removal SQL. Both new evidence and existing
evidence are checked byte for byte. Changed/used annual rows, source drift,
changed protected originals, or tampered evidence leave the result incomplete.
The receipt does not claim insurance/common allowance activation, tax entry,
owner HTTP/JWT authorization, installation on iPhone or release distribution.

There is no new `SET ROLE`, JWT fabrication or weakening of the original
installer's `current_user='postgres'` requirement. A preflight identity read
requires current user postgres, a CLI session user, database postgres, native
PG17, read-only mode and no JWT/auth actor. This is deliberately fail-closed.

## Validation performed

- Python syntax compilation passed.
- Fourteen mocked transport/lifecycle tests passed: exact before, stale refusal,
  acknowledgment, unknown commit with successful readback, unknown/no-change,
  later read-only recovery, marker-before-delivery, tampered after/removal files,
  used/drifting after refusal, symlink marker refusal, no resend, clean PG
  environment/TLS command and secret suppression.
- The actual private prepared bundle was copied to a temporary private folder
  for offline verification. All three hashes and generator byte equality passed
  for 248851 installer bytes; no CLI, credential or database operation occurred.

## Required native proof before owner use

Add a dedicated native PG17 disposable fixture job reusing
`tool/verify_resident_annual_deployment_review.mjs` and
`setupPayrollScopeFixture`, with a loopback-only destination and no hosted
credentials. The current production-pinned `Proof` and `INSTALL_SHA` must not
be made configurable for fixture convenience. A separate test fixture may
construct `Proof`-equivalent synthetic artifacts and patch constants only in
the test process, while exercising the actual `operate` and psql boundary.

1. Exercise the real psql command against the existing annual fixture under
   verify-full TLS, not just a pg-js adapter or mocked subprocess. Prove the
   CLI-session/current-role relationship. A plain fixture CLI login without a
   postgres current role must fail before any attempt marker or installer.
   Do not silently add `SET ROLE` to make a test pass.
2. Test an owner-equivalent fixture session whose current role is postgres;
   prove before equality, exact install, empty annual tables, existing originals
   unchanged, exact unused-removal generation and no removal execution.
3. Inject disconnect after commit and before the acknowledgment. Restart only
   in recover mode, show successful readback and a single installer delivery.
   Test disconnect before commit/no-change and stale input with zero delivery.
4. Verify runtime/bundle/marker tampering and changed original rows are refused.
   No server-side filesystem or OS commands, external producer, real SMS/email,
   project role change or production credential is part of this proof.

The server-side default role of the real CLI temporary login remains unproven
for this new runner. The existing capture tool explicitly gives `--role=postgres`
to pg_dump; that does not prove a fresh psql session starts as postgres. Until
the native boundary and real maintenance-identity preflight are proved, this
candidate must not be presented as user-ready.
