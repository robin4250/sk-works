# Manager expense removal client candidate

Not deployable, not for the next iPhone Release. This candidate does not apply SQL, change payroll or send actual notifications. Backend PR 1719 is frozen at 77dc84436b09ba6fcb17f6bf9018ffed652de9c3 and remains isolated/OFF: shared payroll/document-reader integration and legacy-client rollout are unresolved.

The existing management screen uses the new workspace only when available. Only exact version, booleans and the current SID enable deletion. Missing RPCs fall back to old viewing/review workspaces with deletion unavailable; malformed or unauthorized responses do not fall back. Applicant withdrawal and manager deletion remain separate concepts.

Deletion captures an immutable command and reason in a separate actor/company journal before dispatch. Unknown or mismatched responses retain the journal. Reopening under a valid new SID queries the old result only; no retry mutation is offered. Null is unknown, not success. A confirmed consumed-original result explicitly requires a separate financial correction. No original approval, receipt, snapshot or financial amount is rewritten by the display model.

The exact deletion notification type opens a read-only page. Both status enrichment and the target page query the saved, original-applicant-authorized deletion receipt. Unavailable, foreign or malformed targets stay masked. Neither viewing nor refreshing calls a mutation RPC.

Initial client CI at aeb2c105 failed analysis (two missing block braces, two relative imports, two unnecessary non-null assertions), before tests. Subsequent fixes and added dialog/model/route tests require their own completed CI evidence. Backend synthetic Native checks are not proof of real Auth, Storage, push delivery, phone operation or end-to-end accounting deletion.

At b670015bc27c02caa40adfb090366575c8c13952, dedicated client job 124680628078 completed analysis and test steps successfully; later Auth-epoch, readback and exact-result changes need their own runtime evidence. SharedPreferences reload/readback is checked before dispatch but is not proof of process-crash or device durability. Personal-history metadata and its applicant controls require a separate follow-up that preserves the OCR893 source; no payroll document reader is changed.
