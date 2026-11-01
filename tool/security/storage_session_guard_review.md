# Staged worker-document live-session read guard

Baseline: #1134 actual local GoTrue/Storage tests confirmed that a still-unexpired
access JWT can read worker-document objects after real logout removes its Auth
session. This candidate adds one restrictive authenticated SELECT policy for
`worker-documents` only. Other buckets and INSERT/UPDATE/DELETE policies remain
unchanged. Existing company/feature/ownership policies still apply with AND.

## Default OFF and narrow authority

The new private rollout row defaults OFF, has RLS, and grants no client/table
access. There is no public setter/RPC. When ON, the private boolean-only helper
requires an authenticated actor, permitted account, correctly shaped session ID,
and the exact matching `auth.sessions(id,user_id)` with null/future `not_after`.
Missing/malformed/mismatched/deleted/expired sessions fail closed. The matching Auth user must also exist and must not have a future banned_until. A missing gate
row also fails closed. The function has fixed empty search_path, private placement
and authenticated-only execution. It returns no session metadata and grants no
new client access to `auth.sessions`. Company IDs, membership roles, users and
Apple/Google provider identities are not rewritten by the candidate SQL.

The SQL is REVIEW ONLY outside migrations. No production apply, activation,
automatic deployment or existing migration/source modification occurs. Before
any production permission/auth change: protected backup, tested restoration,
administrator preservation and the user's explicit final approval are required.
The global gate would affect all worker-document reads when enabled; this is
not an automatic per-company rollout or a recommendation to enable immediately.

## Verification contract

PGlite checks actual candidate policy/helper with synthetic SQL claims: default
OFF compatibility, valid session, missing/malformed/wrong-actor/unknown/expired
session, anonymous/wrong role/account restriction, deleted gate, other-bucket
preservation, OFF restoration, original-policy restoration, unchanged rows and
unchanged Auth-session table ACL. These SQL claims are not real Auth issuance.

Isolated CLI2.121.0 CI uses a new local GoTrue/Storage stack and real Auth-issued
owner/self/manager sessions. It verifies normal access with gate ON, existing
company/feature/account denials, actual logout removing the Auth session followed
by a NEW authenticated Storage request rejecting the old JWT, and gate-OFF
restoration of the prior behavior. If a local legacy signing key is available,
negative session metadata is tested through actual HTTP with fixture-only signed
tokens after a positive trusted-key control. Otherwise negative claims are tested
only in the actual SQL helper and their HTTP status is explicitly UNVERIFIED.
No production key or external provider key is acquired or guessed.

The fixture snapshots/restores its synthetic owner company membership, confirms
owner Auth ID and legitimate photo access survive, restores original policies
and feature state, and never prints tokens, URLs, emails, identities or local keys.
Each stack is created in an empty private temp directory and only that project
is stopped/deleted in cleanup. No real/current administrator is altered.

## Residual exposure and compatibility gates

Already issued signed URLs still work before TTL even with the guard ON and
session removed; the real HTTP test explicitly demonstrates this. The guard
does not erase downloaded bytes, purge caches, revoke signed URLs, cancel an
already-running fetch or enforce immediate mid-request revocation. Local origin
TTL behavior does not prove hosted CDN/browser-cache expiry. Broader Storage
buckets, arbitrary RPCs and other API paths are outside this policy's scope.

The helper is provider-neutral and checks GoTrue session structure. Actual
Apple/Google sign-in, account linking, refresh, recovery and administrator flows
with this gate ON are UNVERIFIED and must be validated before activation. Do
not label the candidate production-ready or all-session revocation complete.
