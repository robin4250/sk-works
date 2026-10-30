# Review-only site-order package foundation

Production HOLD; no SQL applied, no feature enabled, no app route or live delivery claimed.

A private original PDF receipt and immutable canonical job are fixed to the sender, exact registered counterparty, current connection fingerprint, real source site, actor and live SID. One send transaction stores the legacy delivery item, pending recipient inbox, immutable package and two durable notice intents. Repeated identical requests return one receipt; changed requests fail. Notice intents are not proof of delivered app notifications.

The public site projection is an explicit allowlist. It excludes notes, customer-name lookup, prices, amounts, payroll rates, PDF URLs and canonical evidence. No recipient site is created by send. Recipient approval, its real site creation, acceptance reply intent, after-commit PDF worker, app notification dispatch and UI remain separate unimplemented work.

## Legacy approval safety

The existing legacy response can otherwise accept a new package without its required reply transaction. The review-only guard replaces only the private function body at its existing OID, after its recipient lookup and not-found check. The public SQL wrapper, private/public full attributes and ACL remain unchanged. Ordinary legacy shares continue to respond with the new master flag OFF. Foreign IDs retain the legacy not-found result.

Installation requires a fresh exact full `pg_proc` attribute capture supplied in a temporary table and the pinned deployed source hashes. Any attribute drift stops installation. No permission broadening, function rename or client execute grant is introduced.

## Evidence

The disposable PGlite fixture passes 27 package checks after inherited canonical and manager checks. It first reproduces unsafe old approval inside a rolled-back transaction, then verifies an already-prepared public call resolves the guarded same private OID. It tests full-attribute drift refusal, sanitized projection, duplicate replay, OFF refusal, foreign recipient, ordinary legacy OFF behavior and immutable package storage. The native PostgreSQL 17 CI repeats the prepared-call boundary; its result must be checked on the published exact head. Synthetic auth is not real JWT proof.

Legacy function fixture bodies come from a read-only deployed `pg_catalog` metadata capture; no business records were read and no production mutation occurred. Fixture tables use captured column names/types; UUID defaults required by the actual legacy insert are present.
