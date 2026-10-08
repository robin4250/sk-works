# Vehicle maintenance external mail basis — 2026-10-09 JST

Source audit at main a2a0ad26. No mailbox, credentials, token endpoint or sending endpoint was contacted. Source configuration does not establish that mail is operational.

## Existing sources

- Archived `account-deletion-worker/account-deletion/completion_gmail.mjs` pins both the MIME From and Gmail API user to `sko.support@gmail.com`; the transport exchanges an authorized OAuth refresh token, then sends base64url RFC message data through Gmail API. Its configuration adapter requires DELETION_GMAIL_CLIENT_ID, DELETION_GMAIL_CLIENT_SECRET and DELETION_GMAIL_REFRESH_TOKEN. Names only were inspected, not values.
- That adapter only accepts account-deletion/<uuid> idempotency keys and deletion-specific errors. It is a reference, not a directly usable vehicle-mail API. The containing deletion worker remains disabled.
- `supabase/functions/send-master-recovery-codes/index.ts` uses Resend with RESEND_API_KEY and MASTER_RECOVERY_FROM_EMAIL. The sender value is not determined from source and no successful delivery is inferred. Do not modify or reuse the protected Master recovery action as a generic notification endpoint.

## Feasible implementation

Create a server-only support-mail transport with separately named configuration and a vehicle-maintenance outbox. Reuse reviewed MIME encoding/input limits/mailbox binding from the archived Gmail adapter, preserving the archived deletion source unchanged. Authenticate the server worker and derive recipient/company/vehicle/body from authorized stored records; do not accept arbitrary client recipients or subjects. Never include Gmail refresh credentials or a service key in Flutter.

An administrator configures external recipient and enables maintenance mail for that vehicle. Persist a unique event per vehicle, rule and crossed interval, then an independent reservation per recipient/channel. Internal notices and external mail have their own delivery state. Meter decreases use the user's correction/manual-distance flow and must not generate negative-distance intervals. Treat Gmail acceptance as sent/accepted, not confirmed inbox delivery.

Gmail sending is not inherently idempotent. A timeout after submission can be ambiguous: reserve persistently before sending, store Gmail message ID on acceptance, and use an explicit uncertain state rather than automatically sending again. No response from the external garage is required by the user's one-way notification specification.

## Configuration and release boundary

The exact Gmail mailbox is evidenced by source; OAuth authorization, token validity, Gmail API enablement and real inbox delivery remain unverified. Establish operational configuration with the mailbox owner before enabling automatic mail. An external OAuth app left in Testing can issue seven-day refresh tokens for Gmail scopes, so unattended production readiness must consider the actual consent-app state. Do not silently switch sender/provider when authorization is missing.

Resend's SDK documentation requires verifying an owned sending domain. Therefore the existing Resend transport is not evidence that it can send From sko.support@gmail.com: SKO cannot verify Google's gmail.com DNS. This is an implementation inference from the domain-verification requirement. Gmail API is the source-aligned transport for the requested Gmail sender; a future SKO-owned verified domain would be a separate sender decision.

## Official sources checked

- https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send — sending method accepts the Gmail user address and gmail.send scope.
- https://developers.google.com/identity/protocols/oauth2 — refresh-token storage/expiry, including external consent-app Testing limits.
- https://github.com/resend/resend-node — own-domain verification prerequisite.

No mail was sent. No claim is made that existing support mail credentials are configured or that automatic vehicle mail is implemented.
