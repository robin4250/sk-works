# Existing invoice app path to authoritative transport (OFF)

Parent: 6bf6d38e5dfafd89a1b2321ba45e00c60b64383e (the frozen transport
foundation). The existing PDF page's candidate branch now constructs the recovery
factory and passes it to the existing approval panel. The release constant stays
false and the legacy `_approve` method remains byte-identical. Future ON has no
old-RPC or legacy approval fallback when endpoint/configuration/preview fails.

The fixed build-time Supabase HTTPS origin and fixed function path are used;
there is no caller-supplied endpoint or returned asset URL fetch. Actor plus
validated SID, not the access token string, bind the recovery instance. Each
request captures one bearer, owns/closes its HTTP client, caps responses at 1 MiB
and uses a 20-second total deadline. Terminal auth/background invalidation
clears preview/operation memory and closes current requests. Unknown outcomes
retain the original operation for read-only reconciliation; restart/cross-login
persistence remains unavailable.

The new server `/open` accepts only notification ID and displayed invoice ID /
timestamp revision. It calls existing private ticket_from_notification and live
session/readiness gates, then uniquely resolves the existing issuer acceptance,
company-local link and current integer document revision from stored rows. Zero,
multiple, reverse-direction/company or inconsistent mappings fail closed. Ticket
creation and mapping/preview/hash occur in one transaction; failure rolls back.
The existing private preview_confirmation generates the expected preview. Its
canonical JSONB hash is calculated by PostgreSQL, never echoed from client data.
A server UUID and authoritative workspace/preview/operation are returned together.

The factory crosschecks all server response scopes with existing strict trade
confirmation models. The panel reuses TradeConfirmationPdf.ownPreview and its
registered version/hash/PNG validation, disables OS print/share, and requires
completed raster stream and decoded image frames before preview acknowledgement,
plus separate financial and own-seal consent. Pending/error raster never enables
acknowledgement; all image/renderer awaits recheck current auth/lifecycle and
dispose stale pages. A controlled pending-capability test proves invalidation
prevents any retained PDF from reaching the raster API. The
controller independently checks both choices; transport sends their values,
not unconditional true. Missing preview, source change or auth history cancels
all consent. The original document/rendering/calculation code is not changed.

The dedicated real fixture uses a direct native HttpOverrides client with a
pinned test CA (not Flutter TestHttpOverrides and not a bad-certificate bypass).
The dedicated real fixture is wired to exercise GoTrue through a trusted local
TLS proxy, the real Supabase SDK, this factory and existing panel, authoritative
open and renderer, explicit choices, actual SQL approval, dropped committed HTTP
response and fresh result read. It also checks default certificate trust rejects
the self-signed endpoint and logout invalidates displayed results. The device PDF
raster callback is synthetic and held until explicit completion in the test; PDF generation and seal-version checks use the
existing renderer. Application source/proposal mappings and seeded notification
rows remain explicit disposable fixture boundaries. No public delivery occurs.

At initial publication, Node 14 and generated canonical-source syntax checks pass;
Flutter analyze and the actual SDK/GoTrue/TLS/PG chain await dedicated CI. No main
merge, public grants, deployment, production data changes, activation or iPhone
verification are performed.
