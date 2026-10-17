# Read-only production inventory / isolated onboarding baseline

Scope approved by root: inspect existing definitions and verify ONLY synthetic
local Auth/Storage/Data-API behavior. No product RLS/auth/UI modifications, beta
pause removal, real files/URLs/JWTs or production changes. Base main
`6022d7bfa795b99c289c989e77fd608842846138`; source app files are unchanged from
the preceding `f68d46de96d7fb8c8d27585649cbf7d1b03c7569` inventory.

## Current contract, not a new restriction

Catalog-only capture contains actual deployed onboarding Storage policies,
private upload/review/account helpers, public profile/state RPC definitions and
their execution ACL, and actual Data API pre-request account guard/barrier key.
The pre-request configuration is `private.check_account_access`; its presence is
important because the profile RPC itself does not directly check account access.
The local fixture verifies the copied hook actually runs before evaluating its
restricted-caller test. Function-body text alone is not the full API boundary.

Current restrictive `license_document_pilot_insert_scope` includes the onboarding
bucket in its restricted list but offers exceptions only for worker/qualification
photos. Therefore valid onboarding invite states do not currently allow new
onboarding image uploads. The existing update pause also blocks overwrites. This
is preserved and explicitly tested, not "fixed" or bypassed.

The DEPLOYED `save_employee_onboarding_profile` rejects any nonempty portrait or
my-number image path with `official_document_uploads_paused_for_initial_beta`,
but permits the normal required text fields with all three image paths NULL.
Thus the backend contains a no-photo initial-beta submission route. The fixture
proves its pre-membership applicant can progress to approval_pending through the
actual public RPC. Its notification dependency is a synthetic local sink only,
not a claim of delivery through the production notification subsystem.

Source review must distinguish that route from current main's UI. In
`lib/features/auth/auth_gate.dart` L42-55, profile_pending maps to the employee
profile page; approved/no-employee state takes the normal company/setup path.
`employee_onboarding_pages.dart` requires three selected photos in `_complete`
and uploads all three before `submitProfile`. `employee_onboarding_repository`
passes their nonempty paths. No photo-skip or saved-path submission option was
found in this reviewed page/repository flow. The original
`20260922004500_add_employee_onboarding_profile_and_approval.sql` still requires
photo paths, differing from the deployed beta RPC. This is a specific UI/server
contract mismatch, not evidence that every registration route is blocked.

The beta intent is supported by actual pause expressions/error and
`docs/review/license_document_upload_pilot_20261009.md` L7-24, particularly its
other-two-buckets-stop and no blanket my-number-route approval. The original
creation of the live pause/profile replacement was not located in the reviewed
source subset; do not invent a deployment migration reference. Root should
reconcile that source/deployment history separately before changing behavior.

## Actual local verification

CLI2.121.0 starts a separate empty temporary project. Actual GoTrue creates and
logs in synthetic applicant, owner, admin, configured approver, manager, viewer,
other-company admin and unrelated user. The applicant has NO company membership.
A generated one-pixel PNG represents an old saved object, seeded by local
service authority to test retained-image access; ordinary new uploads stay paused.

The fixture executes current selected READ/INSERT/UPDATE/DELETE policies and all
relevant restrictive branches. Worker/qualification-only helper interfaces raise
if reached; they are not allow-all stubs or proof about those other buckets.
Minimal schemas model only the columns consumed by the copied functions. The
public profile/state RPCs are actual captured definitions and ACL, not reimplemented
authorization. Private helpers are not exposed as public RPCs. Account-restricted
Storage and Data API callers must be denied, and then recover after fixture-only
restriction removal. Owner/admin/configured reviewer and self legacy reads remain;
unassigned manager/viewer/other-company/unrelated/anonymous reads deny.

Other checks: every invite state still respects current upload pause; overwrites
deny; nonempty-photo profile submission rolls back; NULL-photo submission works;
reviewer revocation denies new reads while old signed URL remains usable before
TTL and expires at the local origin; actual logout removes the applicant session
but the unexpired old JWT still reads under current policies (confirmed remaining
exposure, no new session guard here). Restore checks retain original invite state,
company memberships/roles, owner Auth identity, Auth table ACL and legacy bytes.

No actual photo/MIME recognition, full approval workflow, company creation,
Apple/Google provider login, existing production clients, CDN/browser cache,
notification delivery or every Storage policy is proven. The regular root/company
registration path is not changed; owner state=null is checked, but this is not an
end-to-end company signup claim. Real production permissions/auth changes require
protected backup, tested restoration, administrator preservation and the user's
explicit final approval. This PR does not make such changes.

All credentials, synthetic user identifiers and signed URLs stay private in the
temporary stack/process and are never printed or uploaded. Only fixed status/
classification output is retained. Cleanup stops/deletes only this temp project.
