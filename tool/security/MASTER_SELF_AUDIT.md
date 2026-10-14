# Native self audit

The master settings entry “本人の実監査ログ” reads two server sources separately.

* `server_master_operation_audit`: allowlisted, completed master-device/recovery operations where both actor and target are the authenticated master.
* `supabase_auth_database_audit`: allowlisted Auth actions whose server payload actor ID equals the authenticated master. This is **not** the full external Auth log stream and does not include unattributable requests or every failed authentication.

Both RPCs call the existing enabled-account, master-admin and exactly-one-company guard. No caller-supplied actor/company is accepted. The scope is the current master's own account history; company membership is an access prerequisite, not a claim that past authentication occurred within the current company. No other user's rows are returned. Each source returns only action and UTC timestamp, latest 100; metadata, details, emails, IPs, device names and raw IDs are excluded. Nothing is written, deleted, imported, notified or automatically blocked. Synthetic incident records are untouched and keep their original provenance.

An empty Auth list does not prove safety, absence of authentication, or disabled database logging. On 2026-10-14, read-only inspection found zero `auth.audit_log_entries`, while the external `auth_audit_logs` stream contained records. Managed Auth settings were not modified.

If database storage is disabled, an authorized dashboard operator can open **Authentication → Audit Logs → Write audit logs to the database** and turn it on. Reference: https://supabase.com/docs/guides/auth/audit-logs . Only subsequently stored, attributable events can appear here; old external events are not silently imported. Do not place a Management API token in the app or change `auth` schemas to toggle managed configuration.

JSON save/share includes source explanations, fixed retrieval cutoff, UTC and JST timestamps, and attribution/coverage limits. Export opens a fresh MasterProtectedPage challenge, locks the actor, and re-reads both sources at the original cutoff before handing the same snapshot to the OS. Cutoff is server-created by default, accepts only finite times within the last seven days, and excludes later events added by reauthentication. OS handoff cannot be recalled. Viewing stays inside `MasterProtectedPage` and sticky `SecurityActorBoundary`; switching actors removes the route's content. The operation source does not claim recovery-code failures are persisted: an existing routine that inserts and then raises may roll back that insert, and this change deliberately does not rewrite live authentication logic.

Validation: `node tool/security/master_self_audit_sql_check.mjs <PGlite module>` checks actual SQL role boundaries, self scope, redaction, source labels, exclusion and limits. CI also runs the same SQL against disposable PostgreSQL 17 via the existing loopback-only adapter. Flutter tests validate strict parsing and honest empty/error rendering.
