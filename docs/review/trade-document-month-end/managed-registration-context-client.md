# Dedicated managed registration context client candidate

Not deployed or enabled. Requires the separately reviewed hub/master server
candidate `standalone_trade_document_registration_context(uuid,boolean)` and a
current managed operation gate. No legacy owner/admin fallback is permitted.

The new hub chooses a repository bound to the gate's company and the exact
TradeDocumentFormSession. Only this new mode calls the dedicated RPC; existing
owner/admin membership, session, role and row-scope checks remain unchanged. The managed receipt must match captured
SDK actor and session ID, company, registered trade company, and document kind.
Unknown versions, fields, missing capabilities/RPCs, malformed registered seals,
and cross-company bank snapshots fail closed. The new mode requires the
registered stamp to be enabled and validates a supplied PNG's existing hash.

Bank backend availability is explicit. An available backend may legitimately
have no bank account; it does not create a zero/default account. A bank snapshot
requires a canonical partner ID and its existing strict scoped validator.
The server context must also preserve the legacy bank reader's version and
availability acknowledgement checks, since its inner receipt is not returned
to this client. No user-entered bank data selects the partner lookup.

The client does not inspect user metadata for authority or relax membership,
RLS, profile, seal, or manager permissions. It verifies the dedicated context's
receipt; real authorization remains in the separately scoped server function.
The dedicated tests use synthetic SDK/HTTP fixtures and do not claim real
authentication, a deployment, or a shared canonical artifact/outbox.

The master and manager context are separate from locally generated ephemeral
PDFs, existing financial-document auto-generation flags, and archive viewing.
Existing originals and saved signatures are retained. Main integration must
combine the exact client and server contracts and validate their shared path;
until then the new hub remains unavailable and the master remains OFF.


For legacy standalone registration, the same company-ID-filtered, captured
Bearer/RLS/abort-bound company row also selects phone and FAX. Only a missing
key in the old private profile helper may use that row's contact. An explicit
profile blank or null stays blank. Malformed/oversized contact values are
rejected, not truncated. This requires no production profile DDL and changes no
saved document. Financial attachment schema-2 persistence still requires its
separate backend candidate. Tests cover both direct legacy and bound-session
reads and prove there is still exactly one same-company read.
