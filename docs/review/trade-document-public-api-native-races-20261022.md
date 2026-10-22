# Public confirmation API native race candidate

Source baseline: `5e4cee0a571e154f5beddcd2a59d3d039cfaf432` (contains API fixture `6e33062` and HTTP fixture `eff69da`). Only the new race module and this review note are owned here. No API, financial SQL, Auth, shared fixture, workflow or UI source is changed.

## Cases and evidence

| Race | Expected evidence |
| --- | --- |
| Same public confirmation command/request while its first transaction is uncommitted | Second connection is observed waiting on the first PID; after commit it returns the identical result. Exactly one real invoice approval audit, consent/event, primitive receipt, financial receipt and public API receipt are stored. Read/replay leaves the whole captured state unchanged. |
| Material invoice edit wins | Public confirmation waits for the editor transaction; after its commit the old command fails with SQLSTATE `40001`. No approval, seal consent/event or receipt appears; the post-edit state is unchanged by the rejection. |
| Public confirmation wins | Material edit waits for the confirmation transaction. After commit, the actual material-change trigger reopens approval; current render rejects stale content. Archived approved evidence, seal, all receipts and saved revision are unchanged; original request replay returns its original immutable receipt without approving the changed invoice. |

Both connections use `SET ROLE authenticated`, checked explicitly, and the fixture owner's existing synthetic `auth.sessions` row plus matching SQL claims. The module invokes public workspace, preview, confirm, receipt and render functions. Direct owner SQL creates synthetic fixture invoices and edits the financial parent to exercise the verbatim existing edit triggers; this does not prove a public editing endpoint.

The test observes `pg_stat_activity.wait_event_type = Lock` and the actual holder in `pg_blocking_pids`; elapsed delay alone cannot pass a race. Connections have bounded statement/lock timeouts and cleanup releases the holder before draining the waiter. The main fixture connection only observes state and creates test data. Captured state includes approval rows/audit, revision body/binding, all receipt layers, seal selection fingerprint and unrelated payment-parent fingerprint.

## Minimal integration owned by root/API fixture owner

At the end of `verifyConfirmationApi` in `tool/trade_document_confirmation_api_fixture.mjs`, replace the native concurrency limitation log with:

```js
if(c.openNativePeer){
 await (await import('./trade_document_confirmation_api_races.mjs'))
  .verifyPublicConfirmationApiRaces(db,c);
}
```

Retain the separate real JWT/HTTP limitation. No new environment flag or product fallback is needed: the existing API fixture remains gated by `SKO_TRADE_DOCUMENT_API_REVIEW_HOOK=contract-v1`, under the monthly fixture gate `SKO_MONTHLY_PAYMENT_REVIEW_HOOK=contract-v1`. Include the new module path in the root-owned workflow trigger paths if required. In its PostgreSQL 17 service job, use the existing disposable loopback fixture URL/database and run:

```sh
SKO_MONTHLY_PAYMENT_REVIEW_HOOK=contract-v1 SKO_TRADE_DOCUMENT_API_REVIEW_HOOK=contract-v1 node tool/verify_trade_document_bound_seal_consent.mjs /tmp/sko-consent/node_modules/pg/lib/index.js postgres
```

`SKO_CONSENT_FIXTURE_URL` must already be set to the owned disposable loopback database `sko_document_consent_fixture`; the existing verifier rejects another host/database. Invoke once on a fresh disposable database, as the whole existing fixture creates its schema.

## Validation and limits

Local `node --check` and `git diff --check` pass. Native PostgreSQL binaries/service are unavailable locally, so these new race assertions have **not yet executed**. Root must connect the above hook and run the native CI job before claiming concurrency success. PGlite and existing private coordinator races cannot establish this public API race result. The module skips when independent native peers are unavailable; the standard hook does not enter it in PGlite or the HTTP setup stage.

No real JWT verification, HTTP concurrency, lost-COMMIT recovery, production application or iPhone behavior is established by this SQL-role race fixture. Real GoTrue/PostgREST verification remains a distinct existing stage.
