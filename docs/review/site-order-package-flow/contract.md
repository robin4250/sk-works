# Review-only site-order package foundation

Production HOLD; no SQL applied, no feature enabled, no app route or live delivery claimed.

A private original PDF receipt and immutable canonical job are fixed to the sender, exact registered counterparty, current connection fingerprint, real source site, actor and live SID. One send transaction stores the legacy delivery item, pending recipient inbox, immutable package and two durable notice intents. Repeated identical requests return one receipt; changed requests fail. Notice intents are not proof of delivered app notifications.

The public site projection is an explicit allowlist. It excludes notes, customer-name lookup, prices, amounts, payroll rates, PDF URLs and canonical evidence. No recipient site is created by send. The approval adapter creates the real recipient site and immutable acceptance reply intent atomically. A private reviewed-consent adapter and after-commit canonical PDF registration path are tested. App request/UI integration, automatic worker scheduling and notification dispatch remain unimplemented.

## Legacy approval safety

The existing legacy response can otherwise accept a new package without its required reply transaction. The review-only guard replaces only the private function body at its existing OID, after its recipient lookup and not-found check. The public SQL wrapper, private/public full attributes and ACL remain unchanged. Ordinary legacy shares continue to respond with the new master flag OFF. Foreign IDs retain the legacy not-found result.

Installation requires a fresh exact full `pg_proc` attribute capture supplied in a temporary table and the pinned deployed source hashes. Any attribute drift stops installation. No permission broadening, function rename or client execute grant is introduced.

## Evidence

The disposable PGlite fixture verifies package receive and approval checks after inherited canonical and manager checks. It first reproduces unsafe old approval inside a rolled-back transaction, then verifies an already-prepared public call resolves the guarded same private OID. It tests full-attribute drift refusal, sanitized projection, duplicate replay, OFF refusal, foreign recipient, ordinary legacy OFF behavior and immutable package storage. The native PostgreSQL 17 CI repeats the prepared-call boundary; its result must be checked on the published exact head. Synthetic auth is not real JWT proof.

Legacy function fixture bodies come from a read-only deployed `pg_catalog` metadata capture; no business records were read and no production mutation occurred. Fixture tables use captured column names/types; UUID defaults required by the actual legacy insert are present.

## Approval adapter

Exact recipient filtering precedes state lookup. Approval validates the selected registered customer connection, locks the pending inbox and creates a real recipient-owned site in the same transaction as immutable approval, reply intent and approval/pending notice intents. A forced late intent failure rolls back site/inbox changes. Replay returns the same site and intent; changed request fails. No arbitrary notes or money enter the public site.

The acceptance body preserves all received commercial conditions and reverses only document direction and party roles. Its status is explicitly `awaiting_explicit_consent`; approval does not fabricate seal consent, render under approval locks or claim dispatch. The reviewed adapter below satisfies the own-seal preview/epoch/hash contract. Without that adapter the base intent remains awaiting consent; no path reports a reply as sent.

## Explicit reviewed consent and after-commit registration

`preview_approval` fixes an immutable body, document UUID, actor/SID, recipient registration/fingerprint, own seal and 15-minute expiry. It creates neither a public site nor canonical document. It is review evidence, not recorded consent.

`approve_with_consent` requires the exact reviewed body hash, seal hash and affirmative confirmation. It uses a guarded clone of the approval transaction with only the reviewed document UUID substitution. The real site, unchanged acceptance body, canonical prepare/local binding, existing own-seal decide, immutable ready job and inbox approval commit together. A forced final ready-job failure rolls all of them back. Source/attribute drift in own-seal dependencies stops candidate installation.

The disposable fixture passes 68 package/approval/consent checks. It invokes the actual manager coordinator and Dart renderer only after approval statement COMMIT, then verifies original bytes/receipt reuse. This proves the internal path, not deployed worker scheduling, real JWT, user-visible preview display, acceptance delivery or notification receipt. All public grants and production changes remain absent.
