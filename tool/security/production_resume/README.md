# Decoy producer continuation — review candidate, not deployed

Base main: `74d4c2f578e26ca1f7f21628f19a1da6b2fdeee9` (2026-10-26 JST).
Issue #775 / #273. No production mutation, listener, external delivery, new account,
provider subscription, real data or production key is introduced.

## Reuse first

| Existing work | Reuse boundary | Still absent from its claim |
| --- | --- | --- |
| PR #1009, `tool/security/decoy_lab.mjs` | Synthetic contact events, generation rotation, decoy quarantine/release | Public production service / infrastructure MTD |
| PR #1013 Draft | Signed operator checkpoints, replay refusal within a trusted process-local ledger | Durable monotonic state, restart-safe operator/key recovery. Current controller accepts only `MemoryCheckpointLedger`, so an external durable ledger cannot simply be passed in |
| PR #1126 / #1149 | Bounded loopback HTTP and Docker `network=none` isolation proof | Public ingress plus durable protected monitoring and actual normal SKO traffic validation |
| `collector_signed_transport_candidate` and PR #1336 / #1339 | Exact signed seven-field metadata, bounded admission, actual PG integration candidate | Trusted contact producer wiring, separate host/key provisioning, sustained production delivery |
| PR #1375 staged preparation | Guarded deployment preparation and managed-role constraints | Executable role provisioning under observed managed Postgres authority / live deployment |
| Existing platform log adapter | Sanitized server-only API log windows | Real visitor correlation, public WAF, data-plane admission control |

This inventory does not certify historical PR CI from titles. Root retains exact
head/result evidence and must refresh the actual production catalogue.

## Small new missing connection

`DecoyCollectorProducer` transforms the existing `DecoyLab.inspect()` contact
events into the existing collector's **unchanged** seven-field JSON protocol.
It does not replace the collector, SQL persistence, transport signer, lab,
operator controller or platform-log adapter.

- An explicitly supplied collector ID, startup session ID and separate 32-byte
  derivation key bind deterministic event identities. No secrets are discovered
  from the environment or SKO. Never substitute a Supabase/employee credential.
- Retry uses the exact immutable UTF-8 `body` and same event ID. The existing
  signed handler authenticates those bytes; the durable collector owns insertion
  idempotence and conflicting same-ID refusal.
- Sequence reuse with changed content keeps the same event ID, allowing the
  existing database conflict guard to reject it. A new startup session separates
  the lab's reset sequence. Persist the original envelope/session in the reviewed
  durable outbox for restart retries; regenerating under a new session/key is not
  an acceptable retry. This candidate does not yet supply that outbox.
- Only current/retired contact events are emitted. Rotation, quarantine, restore
  and transport-limit records are not mislabeled as detected attacks.
- Extra fields such as IP, company, session, body or headers are rejected. The
  output does not expose the lab's sequence/startup session or derivation key.
- Correlation means **same decoy generation in the same startup session**. It is
  not the same visitor, IP, account, company or person. Do not use it for automatic
  production blocking. Trusted ingress pseudonymization for repeated-source
  tracking remains a distinct unresolved boundary.
- Stale/future timestamps, clock regression and use after explicit key disposal
  fail closed. Finite historical delivery windows match the existing collector;
  delayed evidence must be handled by an independently reviewed replay/import
  process, not relabeled with a new occurrence time.

## New verification only

Eight new tests passed using Node v24.22.1. The integration case imports actual
unchanged DecoyLab and collector handler bytes after SHA-256 checks, generates an
ephemeral signing key, and checks fresh/retired contacts plus same-byte retries.
All requests are in-process `Request` objects with `.invalid` labels. No actual
DNS/HTTP listener, send, database operation or production key is involved.

```sh
SKO_SECURITY_SOURCE_ROOT="$PWD/sk-security-collector/tool/security" node --test security-production-candidate/decoy_collector_producer_test.mjs
```

For repository publication, place the new files in a dedicated candidate
directory and set `SKO_SECURITY_SOURCE_ROOT` to that checkout's `tool/security`.
The source tree is explicit and both existing imports are hash-checked. No old
successful test suite was repeated or weakened.

## Real deployment and MTD remain unfinished

No hosting target is selected by this producer. The final host must demonstrate
credential-free isolation from the production DB, outbound network denial,
bounded public ingress, independent management authentication, persistent
metadata with tamper evidence, bounded retention and key recovery. A loopback
bind or absence of `fetch` calls is not host-level isolation proof.

Real MTD must name a **deployed admission policy or protected decoy workload**
whose state actually changes, the exact detector/authorization and bounded
actions, normal-traffic exclusion, idempotent operation, timeout, recorded
before/after version and a tested release/recovery path. Merely changing the
existing `g1` path to `g2` is insufficient. Do not move the real DB schema or
modify normal Supabase URLs. A decoy-only rule does not protect direct Supabase
traffic: Auth/RLS/Storage/RPC boundaries must still deny it independently.

Before any live activation, root must connect and verify durable event delivery,
operator review/notification, source provenance, the real host controls, rollback
and restart recovery, then record normal/unauthorized-access and iPhone results.
This new connection is implemented/tested only; it is not main-integrated,
deployed, enabled, or a complete honeypot/MTD defense.
