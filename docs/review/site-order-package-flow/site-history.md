# Site-scoped management history — review only

The management-site row now offers the existing financial editor and a connected
site-specific order history. History retains the existing saved工事名称/工期,
original-byte checks, pinch preview, swipe pagination and visible close action.
The ordinary footer site projection receives no financial data or document URL.

The new fixed Edge command accepts a site UUID and paired cursor. The private
SQL function derives company and management identity from the existing canonical
read actor, locks the current owned site, and filters before pagination. Outgoing
packages match the original render job site UUID; received packages match the
stored approval accepted-site UUID. Names, edited transport projections and
client company identifiers confer no binding. An unrelated same-name site is
empty. Missing/foreign sites are denied. Feature OFF retains existing archive
reads; it does not allow generation, send or approval.

No public RPC, grants, original mutation, financial save or master activation is
added. Existing private functions remain byte-for-byte unchanged. The SQL file
is review-only and is not a production migration or installation bundle.

Local PGlite composition: 45 new history checks, 295 existing package checks and
238 existing bound-consent checks pass. The fixture uses synthetic Auth and
surrounding tables; it does not prove live users, current production RLS, delivery,
Native execution or iPhone use. HTTP 15 tests pass, including the real pinned
ES256 verifier and fixed LOCAL-claims transaction. Latest Native/Flutter results
must be checked independently at the current PR head.

Still unfinished: source/draft creation, recipient selection, explicit outgoing
seal consent, durable uncertain-write recovery and final send connection from
the management-site composer. There is deliberately no placeholder generation
button or claim that sending is complete. Saved company-specific history entry
and real production deployment also remain separate work.
