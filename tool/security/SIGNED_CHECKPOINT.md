# Signed controller checkpoint (offline beta)

This extends the synthetic controller from #1009. It does not deploy a honeypot or connect to production.

A trusted operator supplies a runtime-generated, nonextractable HMAC-SHA-256 CryptoKey and a separate monotonic ledger. No literal key, environment key, Supabase credential or file-based key is used. Tests generate disposable keys inside the process and never export/log them. Key ID and isolated controller scope are authenticated with version, revision and exact controller state. Requests cannot choose those values or call this operator interface.

Restoration validates bounded exact fields, verifies the signature, then atomically consumes the revision before applying the copied state, with no intervening await. Invalid signatures do not consume revisions; concurrent restores consume a revision once. Cross-scope, different/retired key ID and fresh untrusted ledger restores are rejected. No request-derived data, IP, body or identities enter checkpoints.

**Protection limit:** MemoryCheckpointLedger is process-local trusted state, not a durable anti-rollback database. Replacement controllers sharing the same ledger preserve replay rejection; a full process restart loses the key/ledger. This implementation fails closed with a newly empty ledger instead of claiming durable restoration. Before public deployment, management needs isolated durable monotonic state with atomic compare-and-set, an authenticated operator and key lifecycle/recovery that does not restore the ledger from an attacker-controlled snapshot. Possession of the signing key or execution in the trusted operator process can mint state; this is not an OS compromise defense.

The underlying DecoyLab.restore remains the deliberately unsigned low-level lab primitive. Management should use SignedDecoyController; neither interface is exposed to HTTP or SKO. This addition authenticates valid-shaped tampering for the wrapper only. Existing plain fixture snapshots are intentionally not accepted by it. Key rotation uses a replacement controller with the new key/ID and the same trusted ledger; old signed envelopes are rejected, and new checkpoints must be issued.

Run `node --test tool/security/*_test.mjs`. The existing dedicated workflow discovers these tests. Ten new cases cover authentic restore, valid-shape tamper, replay/rollback across replacement, concurrent restore, wrong key/scope/key ID/ledger, mutation during verification and malformed bounds/extractable key. No notification transport, public endpoint, production auto-blocking or paid service is introduced.

## Strict high-water policy

Only the latest issued revision may restore, once. Issuing a newer checkpoint immediately supersedes older envelopes, even when asynchronous signing completes out of order. Every successful managed rotate/quarantine change also advances the ledger, invalidating prior snapshots; issue a fresh signed snapshot after such a change. This is strict anti-rollback rather than an arbitrary historical-restore facility. A rejected old envelope cannot undo a quarantine or rotation. Recovery uses the latest authentic state, and older-state rollback requires an independently authorized recovery design that is not provided here.

A ledger binds to exactly one scope at controller construction. Different scopes must use separate trusted ledgers; sharing a global revision floor across scopes is rejected. Replacement/rotated-key controllers in the same scope reuse the same ledger. Calling the plain injected lab directly is trusted operator bypass, outside this wrapper boundary.
