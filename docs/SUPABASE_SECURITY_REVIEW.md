# Supabase pre-device security review

Reviewed against the live SK WORKS Supabase project before iPhone device testing.

## Verified

- Project status is ACTIVE_HEALTHY.
- A modern publishable key is enabled.
- All repository migrations through the worker-document storage migration are applied.
- SECURITY DEFINER functions in the public schema are not executable by anon or PUBLIC.
- App-facing SECURITY DEFINER RPCs are intentionally executable by authenticated users and contain user/company/permission checks.
- `user_secondary_credentials` has RLS enabled and no direct anon/authenticated table privileges.
- `line_webhook_events` has RLS enabled and no direct anon/authenticated table privileges.
- Secondary password verification locks after five failed attempts.
- Daily-report correction defaults to two approvals.
- A requester cannot approve their own correction request.
- Payroll read access is limited to the linked worker or an explicitly authorized payroll manager.
- Attendance evidence, chat attachments, communication albums, profile photos, qualification certificates, and worker documents are all stored in non-public buckets.
- Profile-photo storage is writable only under the current user's folder and readable only by the user or members of the same company.
- Attendance, qualification, and worker-document storage is guarded by the current user's company membership.
- Chat attachments and communication albums are guarded by communication-group access.

The Supabase Advisor warning about authenticated users executing SECURITY DEFINER functions is therefore not automatically treated as a vulnerability: these RPCs are the intended application API. Each must keep its internal auth/company/permission checks.

## Repeatable audit

Run `tool/supabase_security_assertions.sql` against the production database after future schema changes. It fails if the critical pre-device invariants above regress, including accidental publication or deletion of sensitive Storage buckets.

## Advisor notes

Two RLS-enabled tables intentionally have no policies:
- `public.line_webhook_events`
- `public.user_secondary_credentials`

They are deliberately closed to normal clients and accessed only through privileged server/RPC paths.

## Phone / SMS

Supabase Phone Auth must be enabled and an SMS provider configured in the hosted project's Auth Providers settings before a real phone can receive a code. The connected management tools used during this review do not expose an Auth-provider configuration write API, so this remains a dashboard-side verification step.

The app side supports phone+password signup, SMS verification, resend, rate-limit-friendly error messaging, Japanese mobile number normalization, and verified phone-ID changes.
