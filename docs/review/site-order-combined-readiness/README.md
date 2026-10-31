# Combined dependency rehearsal — source only, not an installer

This new branch retains frozen #1702 and superseding #1703 without editing either branch. It adds a disposable test composition and an exact source inventory. It never applies production SQL, activates features, deploys Edge code, sends to partners or changes invoice/PDF UI. The compatibility SQL from #1703 replaces #1700's same-named proposal; do not run both sequentially.

## Bounded next gap

The same disposable database now contains the retained fourteen-module/C baseline, captured existing six consumer definitions, the #1703 compatibility transaction, registered targets and the unchanged prepare/consent/original/sharing chain. The returned directory ID is used in the actual prepared record. No broad financial confirmation API or unconditional permission helper is added. The six existing consumers are fixture reconstructions of production functions, not newly proposed production RPCs.

Only `private.company_data_delivery_items` is compared against the captured production catalog. Its seven columns/defaults, six constraints, primary plus two auxiliary indexes, RLS/owner/ACL, trigger records and other fields in the pinned normalized-catalog query are checked. Empty surrounding fixture tables are shaped from hash-pinned migration definitions. The adjacent inbox FK action and created_at column are fixture setup required by this table's reference triggers and existing reader; other surrounding relations are not represented as full production-schema parity. Receive-code setup is explicitly synthetic.

The two canonical package FK reference triggers introduced by the baseline are matched as complete expected records before exclusion from the old-table comparison. PGlite raw snapshots differ at created_at's timestamptz attlen8/attbyval bit: raw false is retained, and a comparison-only projection to true is explicitly constrained to that one column/field. An ABI explanation is an inference. Native performs no ABI projection. Raw and comparison artifacts are saved separately in each catalog capture; permissions, types, defaults, constraints or other attributes are not normalized away.

## Checks

The original target CHECK is reproduced rejecting site_share with exact 23514/constraint name. A forced late compatibility failure rolls back all six function bodies, CHECK and row digests. Successful compatibility installation changes only those six prosrc values and the named CHECK; complete pg_proc attributes, other table fields and rows remain equal. Fixture feature state is OFF across this stage.

The unchanged order chain subsequently exercises directory selection, preparation, explicit consent, fixed ES256 HTTP/SQL ACK-loss status, actual canonical original bytes and one package/notice set. At the end, the recipient is authenticated using the existing public uid/jwt bodies and a current fixture SID, with administrator membership checked. Legacy readers/save/pair/inbox refuse the order item; old qualification/personnel data still read, save and retransfer. Mixed batches refuse without consuming the receive code or adding saved items. The smoke transaction then rolls back, and complete row/proc digests match the pre-smoke state. Expected negative calls alone use savepoints; schema/module installation errors are never swallowed.

A bounded output guard requires all five distinct completion receipts even after an exit-zero child, rejecting missing/duplicate/malformed evidence and the observed partial fatal-runtime case. Child output is capped at 16MiB and execution at twelve minutes; temporary copies retain owned-file cleanup.

Local PGlite passes 315 checks, including the strengthened trigger assertions. An intermediate observation contained a fatal-runtime message and incomplete summary; the final completed log was re-read and passes the strict completion guard. The guard rejects any partial completion and contradictory duplicate kind markers. New Native execution, completed CI and independent final review remain pending. Earlier frozen Native evidence is not substituted for these new checks.

## OFF stages and stop conditions — design only

1. Re-query fresh metadata and resolve the exact approved source inventory. Any unknown existing namespace, source/ACL/schema change or ambiguous prior application stops preparation. Do not reset or drop it.
2. A future separately approved C/baseline stage must remain OFF. Existing absence of the feature row is fail-closed, not evidence of a configured false row. This rehearsal is not a production atomic installer.
3. The separately approved compatibility stage must use the superseding original-state proposal, with its 2-second lock and 20-second statement bounds and already-installed exact legacy response guard. A failure rolls back that transaction; a previously committed baseline remains OFF for explicit inspection/forward repair. Never delete used schemas, originals, receipts or history to undo it.
4. Install outgoing observation/prepare/targets/consent only after their pinned dependencies match. Keep OFF and re-check metadata/row state after each approved stage. Unknown or changed state stops further mutation; successful isolated tests do not authorize activation.
5. The fixed fourteen-file Edge/Wasm closure remains separately pinned. Full CLI dependency bundle size, hosted quotas/runtime and actual gateway/user authentication need their own evidence and approval. No deployment authority is supplied here.
6. No ON, partner operation or automatic receipt reply may be claimed until separately approved real-user tests are observed. Existing unknown delivery results require exact status reconciliation, never blind resend.

Remaining full fifteen-relation/caller contracts, real GoTrue, actual sender concurrency, hosted production integration, recipient approval/reply/push and iPhone installation/behavior are unresolved. Document-editing A/B approvals and individual-document exemption state are separate and untouched.
