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

Validation: 51 assertions in isolated PGlite 0.3.14 using the existing original
referral migration and synthetic actors/URLs. They cover OFF gates, empty links,
private tables, Master settings, sender isolation, public channel restrictions,
internal link restrictions, malformed/forged URL hosts, phone normalization,
history metadata, unchanged legacy URL, flags, account restrictions and no
client-attributed registration/points. An SDK transport test covers atomic flag
payload and missing/denied API behavior. No real communication is performed.

Remaining before real use: native PostgreSQL role/concurrency tests, checkpoint
and restore rehearsal, current-production function/constraint compatibility,
reviewed server deployment, the actual intended Apple distribution route and
URL (without broadening owner-only testing), explicit scoped enablement, and
iPhone invitation/composer/recipient onboarding checks. Registration attribution,
points and registration-completion notifications remain separate unfinished work.
