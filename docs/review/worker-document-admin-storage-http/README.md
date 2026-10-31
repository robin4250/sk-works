# Actual local document Auth / Storage / Data API check

This review-only test runs a fresh disposable Supabase stack pinned to the
existing CLI setup. It creates synthetic users and generated one-pixel PNGs.
It never accepts hosted endpoints or links a project, uses no production secrets,
and never invokes a deployed application function.

It exercises the unchanged administrator-own correction SQL through genuine
local GoTrue, PostgREST and Storage HTTP. Two saved original images are removed
from the current document list by an authorized metadata correction, yet remain
in the shared history and private object-identity archive. Authenticated Storage
PUT and DELETE attempts must preserve original bytes/IDs. An unretained generated
object is a positive deletion control. Genuine logout invalidates the old SID
for the new RPC; a fresh login may recover the same opaque receipt without
rewriting its original SID. OFF must stop a new correction while allowing receipt
recovery.

The application tables and narrow permissive Storage policies are disposable
fixture scaffolding; the unchanged baseline/new restrictive policies are applied
on actual Storage. This does not claim hosted/CDN/provider equivalence or grant
service-role erasure authority. Real privileged cleanup is reviewed separately:
the deployed current account-deletion worker rejects official document buckets
and its lifecycle release gate remains false. Its single-path reference index
must not be treated as complete multi-photo/archive classification if that
separate bucket stop is ever lifted.

No main, production, feature activation, Release or iPhone change is performed.
