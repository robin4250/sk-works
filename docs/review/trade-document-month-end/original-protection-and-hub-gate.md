# Original rendering and managed-operation boundary

Not deployed; no master feature is enabled by this change.

The schema-1 and absent-form-fields adopted renderer is preserved from exact
main `67d1a1960e5f59662457ee23c34d2cbacc9e12aa`. Only its class name and a source
comment differ. The schema-2 front is separately frozen. The explicit saved
form schema selects a renderer; current company settings, current date, signed
status and the application release do not silently upgrade a historical form.
The new-header defaults require the authorized schema-2 capability and a new,
unlocked attachment. Missing backend capability retains the original pathway.

The focused workflow renders four historical adopted payloads through both
the exact old source and the version dispatcher and requires identical text and
pixels for all eight pages. The previous initial-value PDF proof covers both
schema-2 fronts, complete terms, no invented rate, and complete invoice pages.
An existing stored original PDF is never rewritten by this change. The parent
invoice's pagination and any immutable stored bundle remain separate concerns;
this does not claim that every historical financial bundle can be re-created
byte-for-byte from a newly generated PDF.

`StandaloneTradeDocumentOperationGate` is optional only for existing legacy
callers. The new hub must supply an actor/session/company/revision-bound gate.
Its `requireCurrent` protects synchronous callbacks; `refresh` rechecks the
capability before and after asynchronous rendering, edit confirmation, preview,
printing and sharing; its Listenable revokes the open page and child editor.
Company, registered trade company and document kind must match. Revocation
clears draft/preview bytes and cannot be reversed by a late success. The print
callback also rechecks the gate. Already delivered native bytes cannot be
recalled; subsequent callbacks/operations are blocked.

This hook does not implement a server master, manager registration authority,
or a shared canonical artifact/outbox. Existing owner/admin registration reads
are unchanged. A dedicated authorized manager context is a separate dependency;
an absent RPC or unknown capability must not fall back to an owner/admin loader.
Current legacy invoice/payment auto-generation settings are unchanged. Archive
viewing and stored originals are not disabled by an operation-only master.

Local source equality, whitespace and workflow parsing checks passed. Flutter
widget/native-print fakes and actual PDF pixel equality require the dedicated
CI result; this workspace has no local Flutter SDK. No real authentication,
production SQL, sharing, iPhone build or install was performed here.
