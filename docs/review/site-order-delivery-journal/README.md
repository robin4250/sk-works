# Shared journal ordering — source Draft

Preparation, consent and original/share intent journals use one local UI-isolate
serial queue. Every begin refuses a terminal marker for that old purpose,
including malformed/unknown marker data. This is not a database transaction,
cross-isolate lock or physical storage durability guarantee.

Archival writer, strict receipt parsing, pending read behavior and user-facing
terminal controls are not implemented in this checkpoint. Existing source
records remain intact. The proposed append-only archival design is under
independent review; recipient approval remains unobserved. No production, Auth,
DB, feature flag or real counterparty operation is changed.
