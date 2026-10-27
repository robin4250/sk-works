# Root-only exemption deployment preparation

This folder is separated from product PR #1492, merged into the build24 integration branch. The product implementation remains unchanged by this guard-only candidate. It is preparation code, not production deployment approval or a completed rollout. No production writes were executed. The product candidate remains OFF.

## Exact scope and preservation

The installer creates only:

- `private.worker_document_exemption_settings` (single OFF setting)
- `private.worker_document_exemptions` (company/worker/requirement ID, active/revoked, CAS version, reason and actor/session/time)
- `private.worker_document_exemption_events` (previous/current decision, actor/session in those snapshots)
- `private.worker_document_exemption(text,jsonb)` and authenticated-only invoker wrapper `public.worker_document_exemption(text,jsonb)`

It changes only the body of `public.current_user_required_document_attention()` by adding one scoped `NOT EXISTS` exemption predicate. Its owner, SECURITY DEFINER, search_path, ACL and every other pg_proc attribute must remain identical. Existing bank/photo rules are kept. It does not update document status, requirements, attachments, employee, company, membership, payroll, bank-account or signature rows. No Storage change is made.

`read-snapshot.sql` returns no personal row contents: it captures full-row count/hash for companies, company_members, workers, document_requirements, worker_document_statuses, worker_document_status_history, worker_private_bank_accounts. It captures the attention definition/body/attributes and the session/account helper definitions/body/attributes. Production catalog already read-only checked: attention owner postgres, SECURITY DEFINER true, `search_path=public, pg_temp`, execute postgres/authenticated/service_role; body MD5 `c3181853d52c25d11ff4c9af1d21b3ce`. Re-read before deployment, do not rely on that stale observation.

The new exemption audit records intentionally have no cascading FK to company/worker/requirement/user rows. Mutations validate and lock the real active parent records. This avoids changing established parent-deletion behavior or silently deleting exemption evidence. Do not treat this as an independent retention/erasure policy.

## Preparation sequence (root, not company admin)

1. Read `read-snapshot.sql` on the existing project and save the extracted `snapshot` JSON as a protected before snapshot. Confirm candidate tables/functions absent and all seven original tables present. Save the actual SQL and snapshot to the existing backup ZIP under a new non-destructive entry; preserve earlier ZIP entries and hashes.
2. Generate `install-off.guarded.sql.review-only` using `python3 docs/review/worker-document-exemption-root-guard/prepare_guard.py --before BEFORE.json --candidate-dir docs/candidates/worker_document_exemption_20261027 --output OUTPUT`. This has no network or DB connection. It writes SQL only.
3. Root reviews the generated SHA/diff. The generated transaction locks the seven original business tables in SHARE mode, binds all before function bodies/pg_proc attribute hashes, checks full original-row counts/hashes and new-object absence, then runs the frozen raw installer. Postconditions recheck original rows, attention body/attributes, OFF and zero usage. The underlying raw installer and Native tests enforce restricted permissions. A lock timeout or any drift rejects the whole transaction; refresh evidence and inspect, do not bypass the guard.
4. Only root may execute an independently approved migration/DDL transaction. Immediately rerun `read-snapshot.sql` and save the actual after snapshot. Business hashes must be identical and the product setting must be OFF. Record implementation/main merge/DB installation/activation/iPhone as separate states.
5. Generate `restore-unused.guarded.sql.review-only` using the same before plus `--after ACTUAL_AFTER.json`. The generator refuses if original business hashes differ. It binds the exact actual installed function body/attribute hashes, then wraps the candidate unused restore.
6. The unused restore locks candidate rows, requires OFF plus zero decision/history rows, verifies candidate function body hashes, removes only the added attention predicate, and drops only the new tables/functions with RESTRICT behavior (no CASCADE). Postconditions require original function attributes/body and all original business hashes, with new objects absent.

## Do not restore after use

If any decision or history row exists, the unused restore rejects. Do not delete exemptions/events to force it. Keep saved documents and decisions/audit; disable only new exemption changes and use reviewed forward recovery. OFF preserves already-saved active exemptions, so existing administrator decisions do not turn into false missing-document alerts. Revocation, rather than OFF, returns one employee/document to the original missing/submitted rule and records the reason.

No company administrator or subadministrator can activate the private setting. No activation API/UI is delivered by this candidate. Root deployment toggles need a separate reviewed/audited operation; actual configuration and iPhone/GoTrue validation remain unfinished.

## Local isolated evidence

`tool/verify_worker_document_exemption_root_guard.mjs` runs the frozen candidate's real SQL/security tests with generated before/after guards against a disposable PGlite fixture. It proved guarded OFF install, unchanged original hashes, attention owner/definer/config/ACL preservation, generated unused restore, reinstallation, and refusal after usage. It does not connect to Supabase. The product PR separately runs Native PostgreSQL 17 and Flutter CI. The separate `worker-document-exemption-root-guard.yml` workflow executes the generator and generated SQL in disposable Native PostgreSQL 17. Refer to the current PR head CI for its result. Passing that fixture still does not mean production installation, activation, GoTrue or iPhone completion.

The generator pins raw installer SHA-256 `585a8f71afbd542d06ae921e71fa10a9064a98b24c2a8db6fc0b7fe99a863ca1` and unused restore `657f3170a4eaed0ac7ee5053c29c4016d40dcf69be3706652a97813938e70c06`. Input validation remains active under Python optimization. The Native harness reuses the pinned existing product SQL verifier and adds function-body, ACL, helper, and nonempty original-row drift rejection, instead of duplicating application logic.
