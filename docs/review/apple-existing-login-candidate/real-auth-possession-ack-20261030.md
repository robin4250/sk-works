# Official Auth to successor possession ACK composition

This fixture extends the existing password-successor broker integration instead
of adding a public endpoint or another client session-writing mechanism. It loads
the unchanged private delivery-ACK SQL after the existing owner/enrollment modules
and reuses the exact Auth verifier and ACK port. The Auth server remains pinned
to official commit `4eee58f296d9698a1c2c0ae14d7a0b379c7622d3`.

The success case verifies OFF denial, refusal of the original bearer and a
signature-tampered successor token, status before possession, and an actual ACK
COMMIT whose response is deliberately discarded. A freshly authenticated status
lookup and idempotent ACK must recover one unchanged timestamp without another
Apple link or credential delivery. Changed company membership and expired Auth
session boundaries deny status even with the previously issued credential. The
original unchanged-identity/profile/company snapshot and final refresh checks
remain in place. The wrong-password case still performs no Apple link/delivery.

Local verification: Node syntax check and the existing six ACK port contract
tests succeeded. The official GoTrue/PostgreSQL composition requires its CI result;
it has not been executed locally and is not claimed successful by this document.

This is a disposable integration fixture. Apple credentials, company records,
loopback network mapping and the privileged database pool are synthetic. It does
not prove managed schema compatibility, least-privilege hosted deployment,
complete session timeout policy, production TLS/rate limiting, client adoption,
secure persistence, restart recovery, or an iPhone/Face ID interaction. Possession
is explicitly not application adoption and never permits enrollment replay.
Production Auth settings, grants, feature gates and business data are unchanged.
