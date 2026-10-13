# Archived account deletion guard tests

Run from the repository root with Node 22 or newer:

```sh
node --test docs/recovery/account_deletion_source_20261008/verification/guard_tests.mjs
```

The suite imports the archived intake and worker **handler `.mjs` exports only**.
It never imports or executes either `index.ts` server entrypoint. All identity,
session, time, credential preparation, status, reservation and worker run values
are synthetic injected mocks. Global `fetch` throws and a final audit asserts
zero attempts. The `offline.invalid` Request URLs are never contacted.

Coverage includes current-subject/session status access, authentication and AMR
guards, explicit confirmation, input limits, disabled release/configuration,
safe error responses, pending intake versus completion, and worker method/key/
enable/job guards. Read-only checks preserve the archived false release flags
and existing unfinalized retention/classification policy.

These tests verify **mock handler guards, not the actual deletion lifecycle**.
They do not verify JWT authentication against Supabase, deployed RPC/RLS,
credential encryption/revocation, access restriction, storage/Auth erasure,
retained-record handling or completion email delivery. No deployment, database
mutation, account deletion, email, real token or real service key is used. Passing
these tests does not authorize changing either release flag to true.
