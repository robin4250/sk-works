# Residual session and asynchronous boundaries — 2026-10-29

This follow-up starts at main `d7c105d5a4d6e4636092a5fbe674a9c2cc28256b`.
Previously successful payroll, acceptance-date and signature checks are retained;
this composition addresses newly reproduced failures only.

## Scope

- Scanner registration: a retired `load` continuation must not reacquire an SDK
  session after disposal or supersession by a newer load.
- Invoice preview: reading and scrolling through a completed multipage raster
  must not consume the technical loading deadline. Every page still requires a
  decoded frame before acknowledgement; invalidation remains terminal.
- External Google login: membership results and OAuth admission must respect
  observed session history and the application's logout boundary.
- Master device management: asynchronous reads, confirmation and proof-bound
  writes must remain attached to their original login session.
- Archive readback: a synchronous callback that outlasts the monotonic deadline
  must not produce a successful signed observation or verification result.

Each source owns separate files. Source PRs contain the specific reproduction,
minimal change and focused validation. Integration evidence records exact heads,
trees and CI conclusions; the final SHA is never inferred from an older run.

## Unchanged operational limits

Individual document exemption remains OFF. Scanner and invoice activation gates
remain OFF and no public route or hosted endpoint is enabled. Existing payroll,
original documents, signatures, seals, database rows and RLS are not modified.

CI and code integration do not establish signed Release delivery, TestFlight or
iPhone installation and physical verification. Real source-owner registration,
independent custody, immutable retention, production role deployment, native
Keychain presence and power-loss durability require their separate evidence.
Google browser admission checks do not establish exclusive ownership of every
SDK refresh, deep-link callback or server-side session revocation.
