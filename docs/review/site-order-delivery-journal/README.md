# Append-only sender-delivery archival — source Draft

Preparation, consent, execution and archival use one local UI-isolate serial
queue. After a fresh exact server `recipient_stored` observation, archival appends
one strict IDs/digests-only `sender_delivery_recorded` marker. The record keeps
`recipient_approval_state: not_checked`; it never resolves recipient approval,
notifications, or the entire order.

Original prepare/consent/execution strings are never changed or deleted. Pending
reads exclude them only when the complete marker and retained mandatory prepare
and consent records match. Existing optional original/share intents must also
match. Missing/corrupt markers resurrect or block pending entries; missing or
contradictory source records remain unknown. All old-purpose begins reject any
marker. A new request can start only when every retained prepare record for the
site has a valid matching archival marker.

The marker includes actor/company/site, full reference/SID/body digest, job,
render hash, recipient, original receipt/PDF digest/length and package. Its local
SHA-256 detects accidental metadata corruption; it is not a server signature or
authorization capability. Every archival attempt obtains fresh server status,
checks the captured scope before/after storage, and rejects a foreign marker.
Only the marker is written; a failed acknowledgement never triggers an order
retry. Retained history opens immutable server review again.

SharedPreferences is not a database transaction, cross-isolate lock or physical
fsync guarantee. Simulated process/store failures are not real power-loss proof.
No business document, original PDF, signature, database state or notification is
removed. No production/Auth/DB/feature flag/real counterparty action is changed.

The writer, parser, pending behavior, history and explicit UI are now source
connected. New crash/serial/Native-artifact SDK regressions and latest CI still
require verification before this Draft is reviewable as a completed candidate.
