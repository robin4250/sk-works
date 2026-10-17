# R26 known analysis-group confinement (review only)

Five new files. Source/catalog metadata and policy definitions only were read;
no business rows, identifiers from data, credentials or production writes.
Original administrator/company/role/friend/member data is untouched.

## Observed paths and changes

The real invite definer validates existing member/friend relationships but does
not call the shared group-access helper; it directly inserts a notification.
The real respond definer only checks pending invite ownership before inserting a
member. The invite-list definer returns group names without a group boundary.
Existing member SELECT uses can_access_communication_group; direct member INSERT,
UPDATE and DELETE have no permissive policy in the observed catalog.

The candidate adds explicit NULL-safe known-group checks before access/member
mutations. For a known analysis group, both inviter and invitee must be current
enabled Masters; recipient must also have no row in the authoritative account
restriction table. That condition is matched to the exact hash of the existing
account_access_allowed source; no user_metadata/GUC/client status is trusted.
Original member/friend/company/duplicate/self checks remain in the original body.
Respond resolves the owned pending invite first, then refuses non-Master known
groups before member/status writes. Master access retains original membership
requirements. Ordinary groups do not gain any Master requirement.

Known invites are filtered from the non-Master private invite-list definer.
R19 notification classification resolves chat_group_invite action_id through the
private invite row into known analysis lineage, restricting future SELECT of old
stored notifications without deleting them. Missing/orphan provenance is not
invented. Existing cached or external deliveries cannot be withdrawn by SQL.

A helper-only fix would be incomplete: actual chat_messages/chat_attachments have
additional PERMISSIVE moderator SELECT policies. Three new RESTRICTIVE ALL
policies therefore protect messages, attachment metadata and group-member rows,
including old-row USING/new-row WITH CHECK. Original policies are not replaced.
Other operations still require their original permissive policies. No Storage
object policy or signed URL lifetime is changed by this candidate.

## Verification

Exact eight target function body/owner/config hashes are checked; OID/owner/ACL/
config/SECURITY DEFINER remain unchanged. Existing nullable/default ACLs are
preserved rather than silently edited. All three new policies and all function
changes are in one transaction. A last-function drift test proves earlier changes
and policy creation roll back, followed by exact original definition restoration.

The fixture runs exact real access/invite/respond/list/member bodies. Synthetic
friendship/group/account rows and a deliberate permissive moderator-read branch
exercise both the ordinary path and OR-policy bypass. The complete production
review-moderator predicate, chat safety helpers, Data API pre-request barrier,
GoTrue/session revocation and all UI callbacks are not reproduced. Actual policy
metadata is preserved in the catalog for an explicit integration comparison.

Local tests cover non-Master/disabled-Master known-group denials, account-restricted
recipient refusal, list/notice filtering, member REST policy boundary, old/new group
reparent denial, original ordinary invitation acceptance and valid Master-to-Master
invitation. PG17/PostgREST must separately verify actual HTTP denial, hidden rows,
ordinary and Master positive acceptance, snapshot restoration and metadata rollback.
Fixture public wrappers are not new product endpoints.

## Remaining blockers and deployment

Known lineage is not complete provenance. Group creation-before-lineage, other
writers/custom chat creation/site membership helpers, moderation definer payloads,
old cached/pushed invitations, orphan notifications, previously copied data,
unknown groups and actual Storage delivery remain separate checks. Existing
invites, members, messages and notifications are not deleted or reclassified.
This is not complete confinement or TestFlight approval.

Protected backup, successful relevant restore, current metadata/ACL/dependency
comparison, ordinary/Master UI comparison, impact report and explicit approval
are required before production. No automatic migration or deployment hook exists.
