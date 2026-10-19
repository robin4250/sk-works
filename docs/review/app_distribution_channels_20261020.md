# SKO invitation distribution channels — review only

The current production referral settings were inspected read-only: invitation
and public flags are OFF and no referral/initial-registration TestFlight URL is
configured. The channel snapshot API and its link tables are absent. This is a
configuration and backend connection gap, not evidence that a message was sent.

This candidate implements the already existing client's three channel APIs:
snapshot, save links, prepare. It reuses the existing invitation ledger, account
checks, Master checks and sender history isolation, while recording the selected
channel/kind in a private table. Public wrappers are invoker-only, and the private
dispatcher rechecks authorization. New tables have RLS with no API table grants.

Invitation flags remain unchanged. Empty URLs can be saved and remain not-ready.
Only a previously configured valid legacy TestFlight/App Store URL is copied into
its matching new channel during candidate installation; no URL is invented.
Saving new channel URLs does not modify or activate the legacy settings. The
server rejects friend invitations to TestFlight/WEB and requires the existing
public flag and public URL for the public channel. Internal TestFlight/WEB links
can only be prepared by company owner/admin or Master, even after general
invitation access is made public. Saving URLs is not publishing a release.

The new flags-only RPC updates only the three existing booleans and timestamp.
It never reads a URL into the client or sends a URL back. The modern client's
existing flag method now uses this atomic RPC. Missing/denied RPCs fail without
falling back to the old read/write sequence. The actual current production legacy
page still uses its explicit legacy URL editor because it has no channel snapshot.
The modern backend and atomic RPC must be installed together before enabling it.

TestFlight internal tester membership and public join URLs are different Apple
distribution routes. This candidate does not create either, invite a tester,
turn public settings ON, prepare a real recipient, send SMS/email, issue/reset
login credentials, create a friend relationship, or award referral points.
Prepared/compose-opened history continues to say delivery is unconfirmed.

The existing configuration and both link records are locked in the same order
before writes/preparation. No share-to-update lock upgrade is used. Native
PostgreSQL concurrent setting changes and production dependency equivalence still
need verification; PGlite assertions alone do not establish those guarantees.

Validation: 69 assertions in isolated PGlite 0.3.14 using the existing original
referral migration and synthetic actors/URLs. They cover OFF gates, empty links,
private tables, Master settings, sender isolation, public channel restrictions,
internal link restrictions, malformed/forged URL hosts, phone normalization,
history metadata, unchanged legacy URL, flags, account restrictions and no
client-attributed registration/points. An SDK transport test covers atomic flag
payload and missing/denied API behavior. No real communication is performed.

Remaining before real use: native PostgreSQL role/concurrency verification, checkpoint
and restore rehearsal, current-production function/constraint compatibility,
reviewed server deployment, the actual intended Apple distribution route and
URL (without broadening owner-only testing), explicit scoped enablement, and
iPhone invitation/composer/recipient onboarding checks. Registration attribution,
points and registration-completion notifications remain separate unfinished work.

## Legacy bypass closure and deployment conditions

The candidate also makes the smallest guarded change to the original private
referral dispatcher: legacy friend preparation must use the public channel API,
and general users cannot prepare legacy TestFlight invitations. Owner/admin and
Master legacy administrative invitations remain compatible. It preserves all
other settings/history logic, function identity, ownership and existing grants.
It does not rename or expose the old function. Direct private-dispatch calls are
tested alongside the public wrapper so the old RPC cannot bypass the friend
restriction. An already copied URL or already opened external composer cannot be
recalled by this database change.

The original dispatcher body hash `3ccced6e2d9a82d715e07c6b3f25b490`,
SECURITY DEFINER and empty search_path are checked before any object creation.
The hash matches the checked-in original migration and read-only current
production metadata. Different/newer definitions fail without replacement. The
whole candidate is transactional. A second/stale application is rejected by the
definition guard. This is not a substitute for a backup or current dependency
audit.

Final ACL checks allow only each new table's owner and, for each new function,
its owner plus authenticated EXECUTE without grant option. Additional default
grantees abort the entire candidate. Private-table, private-function and public-
function default-grant fixtures verify rollback, new-table absence and original
legacy-dispatcher preservation. Existing legacy dispatcher ACLs are preserved.
The normal successful installation also seeds the current-production-style
public-function defaults for anon/authenticated/service_role, then verifies all
four new public wrappers deny anon/service_role EXECUTE and permit only
authenticated EXECUTE. The candidate's explicit REVOKE includes service_role.

The same unchanged fixture is also wired to an isolated PostgreSQL 17 CI service
through a minimal `pg` adapter using the existing pinned fixture dependencies.
Before connecting it permits only loopback, fixed disposable database name
`sko_distribution_fixture` and fixture credentials, with no URL query/fragment.
After connecting it requires version 17 and no user schema/relation/routine.
The independent guard test checks valid loopbacks and ten invalid destinations
without connecting to a database. Native results are pending; no production URL
or credential is accepted by this adapter. Parallel database sessions, backup /
restore and actual Auth/RLS dependency equivalence are not claimed by this test.

Before any production application save the exact dispatcher definition, owner,
ACL/config, referral settings, existing invitation rows, constraints/dependencies
and intended new-object absence. Verify that invitation/public flags are OFF and
both URL configurations contain no invented values. Replay the exact before
checkpoint and a failed deployment in native PostgreSQL. Rollback must restore
the saved definition and settings, preserve existing/history/channel rows and
not unconditionally delete invitations created after deployment. Restoring the
old definition reopens its known legacy friend/beta path; gate OFF and re-review
are required. Do not apply the original migration to a live existing database.

Existing app flows remain separate: employee initial registration issues its
existing one-use credentials/QR through create-employee-invite, not this referral
API. Employee additional URL sending and company recipient picking already open
the referral page with existing contact information. New APIs only choose/store
the distribution channel in that existing page; they do not reissue credentials,
add company membership, approve company links or establish friendships. Those
unchanged entry points and actual recipient onboarding still need iPhone and
current-server verification; source reuse is not an end-to-end completion claim.
