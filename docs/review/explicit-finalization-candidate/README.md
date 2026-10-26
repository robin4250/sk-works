# Explicit final save — review candidate

Base: `112b989978b2f784e66854d12315fec649ecbadf`. DEFAULT OFF. Not deployed by this candidate. Replaces the uninstalled old financial-transition candidate; do not apply that older transition first.

Verified implementation head: `a19828dfc3d8f65493df99f8ced2f9f4395bde01`, [Native run 40271435718](https://github.com/robin4250/sk-works/actions/runs/40271435718).

- Ordinary PostgreSQL 17: **217 checks**, job `121404904285`.
- Independent route-document PostgreSQL 17: **79 assertions**, job `121404904107`.
- No local Flutter/Dart, local PostgreSQL or production data mutation was used.

## Behavior

Reporter signature provisionally saves actual category, registered allowances and hours confirmations. Supervisor signature stores evidence only. `finalize_shared_daily_report` requires both current real signature receipts, unchanged signed content, complete actual source/facts and exact CAS, then invokes the unchanged financial writers atomically. Any missing/protected/blocked output rolls back the whole final-save transaction. No category, time, customer, amount or signature is inferred.

An actual participant on the report's same company/day/site roster may coordinate the saved facts and hand off signing/final saving to another actual member. This records a distinct `site_coordinator` confirmation and audit, never manager or self consent. Existing unique closed clock pairs may be linked with audit; open, ambiguous, foreign-report or mismatched sources are not fabricated or moved. The same fourth-step operation can prepare a peer who genuinely clocked out after the reporter's provisional signature. Confirmed initial hours cannot be changed after capture without editing and new signatures; initially unconfirmed NULL hours may receive their first explicit value.

`start_shared_report_finalization_edit` preserves original signatures/facts in audit, clears current signatures and requires fresh capture. It also recovers an older document-only draft with actual signatures and missing category through explicit input and re-signing. Once explicitly finalized, general approved editing is held atomically with `explicit_report_finalized_edit_requires_attendance_management`. Highest authorized attendance management remains available through actual 03/04/05 proof-backed CRUD, records management-only provenance and preserves prior signatures in audit. Ordinary callers cannot acquire that exception. When the last participant is deleted through the existing audited management flow, attendance is removed and the report is cancelled/hidden while its audit parent and related provenance remain. This preserves the original management contract; it does not force physical deletion of the audit parent.

Route-visit documents use separate evidence capture, explicit `finalize_route_visit_report`, roster-scoped discovery/handoff and audited edit/re-sign. This completes the intermediate document; it does not independently create ordinary payroll entries.

## Proven scope and limits

The ordinary proof runs the four actual financial producers and captured non-route invoice dependencies without modifying their bodies. Its explicit synthetic fixture has neutral tax/leave conditions: two participants each acquire one payroll day, and the actual invoice contains two man-days / 20000. Retry does not duplicate projections; producer errors and protected invoice early returns roll back. Tests additionally cover later peer checkout/preparation, OFF six-key legacy submit compatibility, legacy document conversion, reversed registered-choice order without dropping identity/names/rates, approved-reset refusal, and actual 03/04/05 edit/delete/new attendance with salary-day and invoice-amount consistency.

Both modules prove unused restoration/reinstallation and used restoration refusal. Restore reinstates original routine OIDs/definitions/owner/ACL/config/security/volatility and original confirmation constraints. Explicit dependency-order drops use no CASCADE; an unknown external view dependency causes refusal and full rollback.

Legacy free text and a pre-existing nonzero adjustment (1375 in the synthetic proof) remain unchanged when NULL selections become validated typed empty selections. Without a trusted financial source, reporter submission remains a safe hold with no financial/signature changes. **Positive financial conversion of such legacy cash is not supported or claimed.** Physical report deletion outside the audited management cancellation path, normal route pricing, individual real tax/leave outcomes and device/iPhone behavior are outside this Native proof. Existing real drafts still need actual user input and fresh signatures; no production report was auto-completed.

## Files and exact pins

`prepare_candidate.py` assembles the checked-in technical originals and core pieces offline. Reassembly must leave checked-in generated SQL byte-identical. Installation checks body hashes and captured metadata, postgres execution, absent new schema and exact original constraints in one transaction, with 5-second lock and 45-second statement limits. All rollout rows are absent/default OFF. Used enrollment remains sticky and does not fall into legacy implicit finalization if activation is disabled.

| Artifact | SHA-256 |
| --- | --- |
| explicit-finalization.sql.review-only | `0a9702297ccfd98ba8afb2eea4f89e00b7cbb2419f8e2d5d9423b8390cab5b01` |
| explicit-finalization-restore-unused.sql.review-only | `58c32195ad4a699f2df7b72ca25ab0cd48105d099d91aa459022b42cbb7bc65c` |
| explicit-route-finalization.sql.review-only | `3792946537a3e6143a91116d18a6ac26a5f1363eab48a80442657e634e1c86dd` |
| explicit-route-finalization-restore-unused.sql.review-only | `931247e94f5f250716963f04bc95ef6a9cf226a968136971e4da92fb3c01ca48` |

Source originals are technical definitions/catalog metadata, not live employee records or credentials. Main integration, production backup/comparison, application and activation remain the root owner's sequential work.
