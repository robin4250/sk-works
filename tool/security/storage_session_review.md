# Worker document Storage / session review — 2026-10-16

Baseline main: `04d90559c8929c71b0b91f743066795b28007067`.
`storage_session_catalog.json` contains SELECT-only production catalog definitions,
not real accounts, tokens, business rows, filenames, signed URLs or image bytes.

## Finding and deliberately staged contract change

The actual `worker_document_photo_managed_read` policy permits company
owner/admin/manager by role, independently of `can_manage_people`. The actual
`worker_documents_read` is another PERMISSIVE policy that does check that feature.
These combine with OR: feature revocation alone does not remove manager access
to referenced worker document photos. The selected disposable SQL fixture
reproduces manager feature OFF reading the photo before the candidate.

This behavior was intentional in the earlier managed-photo registration repair:
`20261011053526_worker_document_managed_photo_storage.sql` and its existing test
explicitly preserve manager access without feature grants. The candidate is a
reviewed authorization-contract change, not proof the old implementation was
an accidental regression. Its impact on intended manager duties needs signoff
before production application. Managers need the people feature to retain read
access after this candidate. Owner/admin and employee-self read remain.

The review-only SQL changes ONLY that Storage SELECT policy, checks its exact
previous expression/roles/command first and refuses drift. It is intentionally
outside `supabase/migrations`, because Supabase CLI is unavailable here. No
production application, automatic deploy, business-row rewrite or existing
migration modification occurs. No upload, delete, overwrite or other bucket
policy changes. The underlying role-only `worker_document_statuses` policy and
managed upload helper remain and require separate policy-scope assessment.

## Executed proof and limits

The fixture executes six actual helper definitions, all four worker-document
SELECT branches and the restrictive account-access guard, with selected actual
business-table read policies. It uses minimal synthetic tables and omits the
redundant company-member owner-manage branch. Other bucket branches are outside
this fixture; `review moderator files` uses `content_file_reviews`, whose actual
definition only enumerates chat/note/album buckets. This is not a full copy of
all Storage policies, triggers, helper dependencies or production table schemas.

Checks include anonymous/other-company/viewer denial, manager feature OFF denial
after candidate, feature ON/owner/admin/self preservation, account-restricted
denial, permission ON→OFF for the same subject, exact-policy drift rejection,
late-failure transaction rollback, and synthetic saved rows/object payloads
unchanged. Native PostgreSQL 17 CI and PGlite run the same fixture. Existing real
worker photo editor draft and managed/self repository HTTP tests run separately;
their mocked backend responses do not prove production Storage HTTP authorization.

The current actual `account_access_allowed` checks `auth.uid()` and account
deletion restrictions, not `auth.sessions`. Permission-revocation checks use a
fresh DB permission state with the same fixture subject. They do NOT demonstrate
GoTrue refresh/access-token revocation, logout invalidating a still-valid JWT,
or deletion of an Auth session making an issued access token unusable.

Actual Storage HTTP signed-URL expiration and reuse after permission revocation
remain UNVERIFIED. No simulated URL is offered as evidence of real Storage
behavior. No real signed URL, object or JWT was requested. A disposable Storage
service with fixture-only keys and files is needed for that follow-up. This
candidate does not claim immediate revocation of a previously issued signed URL,
removal of previously downloaded bytes, or resolution of every Storage risk.
