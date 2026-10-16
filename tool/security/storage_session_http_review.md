# Actual isolated Auth + Storage HTTP follow-up

This suite starts Supabase CLI **2.121.0** in a new empty temporary project,
using only a disposable local Docker stack. It never links a remote project,
imports production data, reads production keys or changes the app. CLI-generated
local credentials stay in a mode-600 temporary JSON file; Auth users/passwords,
tokens and signed URLs stay in memory and are not printed or uploaded. Cleanup
stops only this temporary project and removes its volumes/files even on failure.

The script refuses non-127.0.0.1 API/database endpoints and non-empty fixture app
tables or pre-existing Storage policies. Four users are created by actual GoTrue
admin HTTP, then log in through actual password HTTP. No test JWT is self-minted.
The worker-document selected catalog helpers/policies and the review-only
feature-boundary candidate are installed only into that local fixture. A private
bucket holds a generated one-pixel PNG; no real image is fetched or copied.

Actual HTTP covers anonymous/other-company denial, employee-self/owner/feature-ON
manager downloads, permission-OFF denial, actual signed-URL issuance/short expiry,
and a previously issued URL after DB feature revocation. The latter is explicitly
observational: continued access before expiry is a remaining bearer-URL exposure,
not proof of immediate revocation. Likewise, the suite logs out through GoTrue,
checks the matching Auth session was actually removed, probes the old JWT's
Storage access, and checks refresh-token rejection. If the old JWT still reads,
that result is reported as a remaining gap, not a failed simulation or security
completion. Only status/classification is printed, never credentials or URLs.

The suite has no hosted CDN or browser cache. Origin expiry success does not prove
edge-cache expiry, cache purge, loss of previously downloaded bytes, or production
equivalence. Selected policies/minimal schemas inherit the limitations documented
in `storage_session_review.md`. Production runtime versions, complete schemas,
hosted Auth settings and network paths remain different and require separate
review. There is no production migration/deploy in this follow-up.

Official references checked 2026-10-16:

- https://supabase.com/changelog.md (recent TLS/CBC, self-hosted Auth URL changes inspected)
- https://supabase.com/docs/guides/auth/sessions (JWT may remain usable after logout; strict checks require session_id lookup)
- https://supabase.com/docs/guides/storage/cdn/smart-cdn (signed URL expiry and cached-response lifetime differ)
- https://supabase.com/docs/reference/javascript/storage-from-createsignedurl

CLI init/start/status/stop help was inspected with the pinned binary before
authoring. The local authoring runtime has no Docker; real-stack execution is
performed by the isolated GitHub Actions job, and success is recorded separately
from source presence. Do not label this suite verified until that job passes.
