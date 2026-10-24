# Public trade-document API real Auth runner — review candidate

This is a new CI-only proof runner, not a deployment. It reuses the local-stack lifecycle pattern in the existing payroll GoTrue runner and the existing consent/invoice/monthly fixtures. It must run on a disposable runner with Docker and no hosted Supabase credentials. It creates its own random local project, validates loopback ports, requires empty application/Auth tables before use, creates only synthetic example.invalid accounts through the real local GoTrue admin endpoint, signs in through the real password flow and calls PostgREST with the resulting access tokens. Local keys, JWTs, passwords, connection URLs and subprocess output are never logged. Cleanup stops only its owned project and removes only its created directory.

Command from the combined repository tree with existing locked pg fixture dependencies installed:

```sh
CI=true SKO_TRADE_DOCUMENT_REAL_AUTH_HOOK=contract-v1 node tool/trade_document_auth_api_gotrue_e2e.mjs
```

`RUNNER_TEMP` must already be set by the CI runner. Ports 53980–53989 must be free. Root owns the workflow; no workflow or GitHub changes are included here.

The fixed in-process `auth-http-setup` hook adapts only the known fixture bootstrap: it removes synthetic role/Auth schema/uid declarations, the fake auth.users table and its exact known seed insert. Real `auth.uid`, `auth.jwt`, users, identities and sessions remain intact. App fixtures cannot write Auth rows; unknown Auth write SQL is refused. Existing app SQL, source guards and real invoice approval adapters remain unchanged. SQL setup may set local request claims for fixture seeding, but the public API proof itself uses actual GoTrue-issued JWTs over HTTP.

The runner asserts:

- Actual issued JWT subject/session maps to a real local Auth session.
- Current owner workspace/preview → monthly content review plus issuer seal, with financial parent byte-for-byte unchanged.
- Original command/request replay and read-only receipt return the original result.
- Receiving company gets a separate stable local document ID and identical immutable rendered evidence; it cannot use the issuer preview.
- Viewer and unrelated company cannot prepare or confirm, and explicit seal-choice refusal changes no protected app state.
- Saved invoice invokes the existing real final approval adapter, preserves total/tax and freezes the registered seal.
- Auth functions and all preexisting synthetic identities/sessions are unchanged by application operations.
- Real local GoTrue signout removes the session; the previously signed JWT cannot preview, confirm or read its receipt through the public API afterward. Signout is the intended explicit session mutation, distinct from app operations.

Local validation performed: JS syntax and diff checks; unchanged ordinary PGlite path passes 230 checks. The current host has no Docker, so the real GoTrue/PostgREST runner has **not yet been executed**. First root-owned CI execution is required; this document does not claim successful real-JWT proof. Its surrounding application tables and access predicates remain synthetic; it does not establish production RLS/config/ACL, OAuth/device behavior, native concurrent public API races or production deployment.

## First CI correction

First root-run CI reached all four real GoTrue logins and passed the unchanged private fixture checks, then failed in the broad setup phase with 22023. Source inspection identified the HTTP-only monthly attachment seed omitted the required `issue_date` (the invoice branch supplied it). Both kinds now explicitly supply issue date, intro and payment conditions as the already-passing monthly fixture does. Setup phase labels now distinguish public API installation, parent creation and each kind's workspace/save. Failure logging accepts only six fixed, literal validation messages from the existing attachment saver; it never prints arbitrary SQL messages, details, values or tokens. Successful HTTP completion still requires the next CI run.
