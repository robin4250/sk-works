# Preserve collector calendar evidence

Follow-up based on main `045169174188262f05b17c38495359e1059ea03b`, outside build15. No main, production Auth, role, Edge, key or collector gate is changed.

The existing client checks provenance, scope, master-session proof, event allowlists, size and immutable output. Those guards remain. `DateTime.tryParse` additionally normalizes invalid calendar/time components; it is insufficient to validate a forensic timestamp or key epoch. A February 31 value could pass as if it were a real observation date.

The candidate requires a real nonzero-year calendar date and complete timestamp with explicit zone, 00–23 hour, 00–59 minute/second, at most six fractional digits, and a valid numeric timezone offset. Valid PostgreSQL JSON timestamptz forms, leap days and offsets retain their original strings. It does not silently reinterpret or replace malformed evidence. It does not infer clock ordering, current clock accuracy or a confirmed attack from the event.

Regressions cover impossible key epochs, invalid components and missing zones in both timestamps, plus valid leap-day/microsecond/offset records. Existing session change, cancellation, one-use proof, provenance, secret-field denial and page tests are reused via remote CI only. Static diff validation passed; CI pending at publication. No local Flutter/Dart is executed.

## Remaining deployment boundary

The collector backend/Edge/trusted producer is still unprovisioned. The existing bounded role generator correctly returns zero artifacts for the observed non-superuser managed operator because creator ADMIN membership and unsupported catalog locks violate its strict contract. This patch neither relaxes that contract nor bypasses it. A reviewed managed provisioning/cleanup route and real producer/key/admission verification remain necessary before actual collection is available. No synthetic fixture is presented as a real security event.
