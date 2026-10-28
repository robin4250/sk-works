# Individual document exemption — real Auth boundary candidate

This test adds real GoTrue JWTs and PostgREST to the already-reviewed #1492/#1495 product SQL. It uses a disposable Supabase CLI 2.121.0 stack and rejects hosted credentials/endpoints. Application tables and the account restriction/barrier fixture remain synthetic. The real `auth.uid`, `auth.jwt`, users and sessions are retained, and the session helper is extracted unchanged from the staged contract.

Coverage: owner/admin/manager mutation, same-worker read, viewer/foreign-company/anonymous/forged JWT/user-metadata forgery rejection, CAS, real signout/session deletion, direct private-table ACL, account restriction, OFF preserving an existing exemption, revocation restoring attention, existing bank/photo completion conditions, unchanged source document rows and attention function attributes.

No production migration, activation, employee decision, app signature or business record is changed. The user's existing deployment backup and current production snapshot are not committed here. This is not iPhone validation, managed-project compatibility proof, retention or after-use recovery proof. CI must succeed before this gap is called verified.
