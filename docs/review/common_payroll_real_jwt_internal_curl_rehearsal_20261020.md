# Common payroll: restored-clone GoTrue / Data API rehearsal candidate

Status: review-only executable candidate. Python local HTTP/source-boundary tests pass; actual Docker/GoTrue/restored-database execution has not been performed on this host. This is not production rollout or owner Google login evidence.

## Reuse and immutable images

Reuses the unchanged `owner_payroll_common_rehearsal.py` installation builder and its existing four original SQL sources, plus the unchanged stopped-restore source/isolation/database-property definitions from `owner_expense_off_rehearsal.py`. The source database is `database-restore-01qyi5py`; original stop status, image digest, label, local Unix Docker context and network=none are required.

The issued-JWT method reuses the mechanism already measured in `platform_auth_gotrue_e2e.mjs` and PR #1245: admin-create an email-confirmed **synthetic** user, perform an actual GoTrue password grant, and check that its issued JWT session ID exists in `auth.sessions` before Data API calls. It deliberately does not run #1245's empty-database fixture on a real restored schema.

Required additional images, verified from DockerHub Registry manifests and corresponding CLI 2.121.0 service versions:

- `supabase/gotrue@sha256:1736a63078f5922b198c4cbe50f80ab9a2d3b54fe8b7b6cfb2e9dc5dbbc12c6b` — v2.197.0; Linux amd64 and arm64.
- `postgrest/postgrest@sha256:d155c6718ed9a9f990d159a2ab7c0a3f16944dbb6d0a0344557421042acfe0df` — v16.4; Linux amd64 and arm64.

No CLI, Node, npm package, Kong, Edge runtime, SMTP, SMS or Google/Apple provider is required by this candidate. It uses the existing PostgreSQL image’s curl through `docker exec -i`; Mac Python only orchestrates Docker and captures bounded responses. No extra image is needed. The existing exact Supabase PostgreSQL 17.6.1.166 base image is reused through a private local commit of the original stopped restored container.

Version sources: `supabase/cli` tag v2.121.0, `apps/cli-go/pkg/config/templates/Dockerfile`, `apps/cli/src/commands/start/services/gotrue.service.ts`; original Auth settings are not copied from the hosted project. The exact Auth/PostgREST version/config parity of the hosted project is a separate question.

## Isolation and credentials

A new Docker **internal** bridge network contains a new DB clone, GoTrue and PostgREST. No service publishes a host port. Docker Desktop’s internal network produced an empty published-port list in the first attempt; this revision removes all port publication instead of changing network isolation. The DB container executes curl to a fixed literal IPv4 address inspected from each service on the single internal subnet. The curl request configuration (including Authorization and JSON bodies) goes through stdin, with no secrets in process arguments. The response stays in bounded memory. curl ignores its default config, disables proxies and redirects, permits HTTP only, and enforces connection/overall timeouts and a 1 MiB response cap. Any host port binding or service outside the exact internal network is rejected.

The original restore's `auth-host=reject` is unchanged. Only the new clone uses a separate HBA file allowing SCRAM connections from its private internal subnet to two random scoped login roles. The Auth login inherits the restored `supabase_auth_admin` role for Auth schema operations; the PostgREST login is NOINHERIT and may SET ROLE to anon/authenticated/service_role. Role credentials are newly generated, not the unknown hosted DB password.

All three containers use `--log-driver=none`. The host runner captures raw process output only in memory and never writes Auth/SQL stderr or HTTP bodies to logs. Only static failure codes, phase and SQLSTATE can be saved. JWTs/passwords stay in memory or temporary owner-only env files, removed during cleanup. HTTP disables environment proxies and refuses redirects. External providers are disabled, email is autoconfirmed, general signup is disabled, and no mail service exists on the internal network.

A locally HMAC-signed service-role bootstrap token is used only to administer the synthetic Auth users. **All user-access tokens for the tested Data API operations are actually issued by GoTrue.** No owner Google token, identity or password is created, copied, substituted or changed.

## Tested flow implemented

1. Verify both required immutable images before creating the test network.
2. Clone the original stopped restored DB, apply the already reviewed owner/ACL normalization only to the clone, and install the existing common-payroll candidates there.
3. HTTP requires separate connections, so candidate DDL and test changes are **committed only in this disposable clone**. This differs from the prior single-transaction SQL rollback tests; the original restore/backups remain unchanged, and the test containers are removed afterward.
4. Use the existing protected current-month automatic-draft row hash to fix one company/worker/type. Add synthetic GoTrue accounts for admin, viewer, another admin and an unrelated actor. Only new synthetic members are added; original owner membership/identity remains intact.
5. Real JWT -> common read: admin editable, viewer read-only, no-token/unrelated user denied. Existing payroll direct REST/RLS allows the scoped admin and denies the unrelated actor. A corrupted JWT signature must be rejected.
6. Real JWT -> common save of synthetic monthly earning/deduction: unauthorized callers denied, identical retry gives the original receipt, stale CAS fails. Another same-company admin cannot read the first actor's request receipt.
7. Explicitly activate the current month **in the clone only**, then real JWT -> read publication/save publication, unauthorized denial, identical retry and stale-CAS rejection.
8. Expire the actual synthetic Auth session (`not_after`) and retry all three common operations with its previously issued token: they must deny. Log out another actual GoTrue session and retry its previous JWT: the common read must deny.
9. Compare original users' credential/metadata, identities, companies and memberships while excluding only the added synthetic user IDs. Recheck that the original restore is still stopped/network=none.
10. Remove only the newly created container IDs and network ID; delete temporary env files. Cleanup failure prevents a verified result. Copy the safe result with pbcopy.

This first slice measures read/save/publication, actor, live-session and direct payroll RLS boundaries. It does not repeat all native payroll calculation/insurance/history tests or imply every sensitive table/RPC/Storage path is covered.

## Verification and remaining runtime uncertainties

- Python tests: 9 passed. Real local curl roundtrip verifies JSON Unicode/newline/quote encoding, Bearer transport, error bodies, redirect refusal and no stdout. Other tests exercise subprocess response limits/timeouts, internal IPv4/no-host-port inspection, route/header injection rejection, immutable image/isolation arguments, builder reuse and refusal before network creation if an image is missing. The local roundtrip substitutes only the Docker exec prefix; this host has no Docker.
- Identity fingerprint SQL executed in PGlite against synthetic table structure; no real rows were used.
- Docker runtime is unavailable on this Linux worker. Actual GoTrue migration compatibility with the restored Auth schema, inherited migration-owner privileges, internal Docker exec curl transport, RPC HTTP results and cleanup must still be demonstrated on Mac. Runtime failure saves only a bounded static phase/error code/SQLSTATE, without raw private responses.
- This synthetic email Auth proof is not phone-provider, Apple or real Google login, production gateway parity, owner-account authentication, new-app actor lifecycle behavior or readiness to distribute to employees/friends/partners.
- The missing real reauthentication proof consumer for collector storage and the one-use initial-QR/session cutoff remain separate security blockers.

## Files for a protected immutable loader

The runnable set consists of `owner_common_http_rehearsal.py`, unchanged `owner_payroll_common_rehearsal.py`, unchanged `owner_expense_off_rehearsal.py`, and `common_payroll_sources.json`. `manifest.json` records their SHA256 plus the test file hash. Run the new helper only after source review and fixed-commit/hash verification. Do not print environment files, JWTs, passwords, raw Auth responses, or a full Docker inspect payload.
