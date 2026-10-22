# Public synthetic distribution checkpoint guard fixture

This is a test generator, not a production migration or deployment instruction.
It reuses the reviewed public PR1305 OFF install/unused undo and original referral
migration. Existing business-function bodies, API gates and public source remain
unchanged. It creates no real recipient, URL configuration, credential or message.

The template contains before/post guard logic and placeholders only. Neither
production expected-snapshot JSON, real OIDs, company values, settings timestamps,
private paths nor a hosted project reference is published. The SELECT template
names explicit dependency objects but obtains every OID and expected value from
the empty synthetic fixture at runtime. Production checkpoints are never loaded.
The generator asserts the reviewed public install's exact Git blob identity.
Function replacers preserve SQL dollar quoting when inserting the public payload.

The v3 postguard dependency containment uses explicit JSON extraction parentheses;
prefix-only tests did not exercise the prior operator precedence error. No pinned
production comparison or checkpoint was relaxed by this public test extraction.

The local existing PGlite dependency passed 17 prefix cases and the full OFF
install/postguard/unused undo roundtrip, 132 assertions total. Synthetic OID drift,
function body/ACL, table ACL, policy, constraint, feature/public ON, configured URL
and preexisting new object all refuse before sentinel DDL. Deliberately invalid
synthetic expected snapshots separately exercise explicit OFF/empty/absence guards.
The normal synthetic before snapshot reaches sentinel DDL in a rolled-back TX.
The full run keeps flags OFF, links empty and history unchanged, then restores
the unused original dispatcher and removes unused channel objects.

The proposed native job reuses the existing distribution_pg_adapter and its URL
guard. Only the disposable loopback PostgreSQL17 database with fixture credentials
is accepted, and the adapter requires an empty database before bootstrap. The
existing destination-guard tests run first. Local native PostgreSQL is unavailable;
native results must be read from CI. No local package installation or Flutter run
was performed.

Passing this suite is not a successful production-shaped installation, native
DDL-concurrency guarantee, real Auth/SMS test or a production undo receipt.
An actual deployment remains a separate reviewed operation with fresh pinned
before data and stopped/drained writers/DDL. Production undo remains sealed until
its exact generated-object after receipt exists and use/configuration is excluded.

