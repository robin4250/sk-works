# TestFlight LINE distribution lock review

Baseline: `04d90559c8929c71b0b91f743066795b28007067`. Production project: `ztktgquxvcxcjxtluspu`.

The existing release gate is implemented, but saved `general_enabled=true` allows registered general users. This proposal is **not deployed**. The review-only SQL is outside `supabase/migrations` and is not an automatic release action.

The proposal changes only `private.line_actor_release_allowed(uuid)` to enabled-master-only for TestFlight. It preserves the entire saved general-release settings row, master feature settings, original function owner/ACL/configuration, messages, bindings, historical imports and attachments. A master remains subject to existing company/group and account restrictions. Service webhook reception remains unchanged; this does not disable incoming LINE ingestion or delete records. Master changes to the saved general-release switch are retained but cannot reopen general access while the distribution lock is installed. The UI capability RPC uses the enforced effective access, not the saved switch value.

Before any deployment, review the current definition and captured backup, verify the expected body hash `f8ad4338c53cf972a415c9189b4053ae`, then promote an explicitly approved version to a CLI-generated migration. Changed definitions fail closed without replacement. The review-only script is intentionally not an automatic repeatable deployment command. Reopening general access requires a separate reviewed change and fresh distribution approval; do not blindly restore an old helper over newer authentication work.

## Verification

The existing exact SQL fixture runs normal release, drift rollback, and the new `--testflight-lock` branch. The new branch applies the proposal while the saved setting is true, checks the settings row and helper ACL/owner/configuration are unchanged, and exercises existing negative cases for employee/admin/manager/viewer/other-company/disabled-master roles. It tests direct SELECT RLS on LINE messages/bindings, workspace/list and claim/binding/import/shared-chat functions, queued outbound preparation/claim recheck, master existing-group access, account restrictions, ordinary SKO messages, webhook fixture reception, and original-history digest. A later saved switch change back to true must still leave general access denied.

Local PGlite tests: normal baseline PASS, original drift rollback PASS, TestFlight lock PASS. PostgreSQL 17 is scheduled in the dedicated workflow; its actual run result must be checked before integration. The fixture uses the repository's existing minimal dependency models and release SQL, not a full production schema or real identities.

**Not verified:** actual PostgREST HTTP/JWT transport, all current later LINE RPC variants, Flutter mounted-screen transitions, Realtime delivery, in-flight external sends, Storage signed URLs or expiry/revocation. SQL-role checks are not described as HTTP tests. No production DDL/config/data writes, actual LINE sends, signed URL creation or personal-data reads were performed. Existing production general access remains unchanged and the distribution blocker remains until a reviewed deployment and staging transport tests are completed.
