# SKO LINE bridge pilot setup

This is the first, one-way `LINE -> SKO` bridge for the October 2026 rollout.

## Current scope

- Verifies `x-line-signature` with `LINE_CHANNEL_SECRET` before processing.
- Accepts new **text messages** from LINE **group** webhook events.
- Looks up an explicit `line_group_bindings` record.
- Stores the message in `communication_messages` with `origin = 'line'`.
- Keeps LINE message IDs for deduplication and the sender user ID for traceability.
- When `LINE_CHANNEL_ACCESS_TOKEN` is configured, looks up the group member profile and stores the sender display name when LINE returns one.
- Profile lookup is best-effort and capped at 1.5 seconds so a slow profile API cannot hold message ingestion open indefinitely.
- A failed or timed-out profile request does not block message ingestion.
- LINE may redeliver a webhook; external message ID uniqueness keeps retries from creating duplicate chat rows.
- Ignores unbound groups and non-text events.
- Does not send SKO replies back to LINE yet, preventing reply loops in the pilot.

## Prerequisites

1. Deploy the chat migration from the site-chat PR first.
2. Deploy `20260918114500_add_line_bridge_foundation.sql`.
3. Create a LINE Official Account / Messaging API channel and allow the bot to be added to groups.
4. Set the required Supabase Edge Function secret:
   - `LINE_CHANNEL_SECRET`
5. Optional but recommended for readable sender names in SKO chat:
   - `LINE_CHANNEL_ACCESS_TOKEN`
   - The bridge uses LINE's group-member profile endpoint only when this token is present.
   - If the token is missing, invalid, times out, or LINE cannot return a profile, the message is still stored and the UI falls back to `LINE` as the sender label.
6. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to Supabase Edge Functions by the project environment.
7. Deploy the function:

```bash
supabase functions deploy line-webhook --no-verify-jwt
```

`--no-verify-jwt` is required because LINE, not a signed-in SKO user, calls this endpoint. Request authenticity is instead enforced by LINE's HMAC signature.

## Webhook URL

Configure the LINE Messaging API webhook URL to the deployed Supabase Edge Function URL for `line-webhook` and enable webhooks in the LINE console.

## Bind one LINE group to one SKO group

The first release intentionally keeps binding writes out of the normal member UI. Create the binding with an administrator/service-role operation after you know the LINE group ID:

```sql
insert into public.line_group_bindings (
  company_id,
  communication_group_id,
  line_group_id,
  display_name
) values (
  '<company uuid>',
  '<SKO communication group uuid>',
  '<LINE group id>',
  '既存LINE連絡グループ'
);
```

A LINE group can bind to only one SKO communication group, and one SKO communication group can bind to only one LINE group in this pilot.

## Pilot test

1. Add the LINE bot to the existing group.
2. Send a normal text message in LINE.
3. Confirm the Edge Function returns HTTP 200.
4. Confirm a row appears in `communication_messages` with `origin = 'line'`.
5. If `LINE_CHANNEL_ACCESS_TOKEN` is configured, confirm `external_sender_name` is populated when LINE returns the member profile.
6. Open the same SKO communication group and confirm the message appears through Realtime.
7. Confirm the sender is shown by display name when enrichment succeeded, otherwise the UI safely falls back to `LINE`.
8. Send the same webhook payload again and confirm the external message ID uniqueness prevents a duplicate record.
9. Confirm a deliberately unavailable/slow profile lookup still allows the message to be stored after the best-effort enrichment times out.

## Historical LINE export preview

Before adding any database import path, use the local preview tool to validate an exported LINE text file safely:

```bash
dart run tool/line_history_preview.dart path/to/line-chat.txt
```

The preview tool:

- Parses common Japanese LINE date headers and tab-separated message rows.
- Preserves multiline message bodies.
- Ignores non-message/header/system lines that do not match the message shape.
- Prints only a local summary and the first 20 parsed messages.
- Does **not** upload, insert, update, or delete SKO/Supabase data.

This is intentionally the first historical-import step for the October rollout. Validate the actual exported attendance/work-group format with this parser before adding a write/import command.

## Security notes

- Never expose the service-role key in the Flutter app.
- Never expose the LINE channel access token in the Flutter app or commit it to the repository.
- Never accept a webhook without verifying `x-line-signature` against the exact raw request body.
- Normal authenticated SKO users cannot create `origin = 'line'` messages through the existing chat RLS policy.
- `line_group_bindings` is readable only within the same company; writes are service-role/admin-only until a dedicated admin binding UI and role policy are added.

## Next steps

- Validate one real exported LINE attendance/work-group text file with the non-destructive preview parser.
- Optional admin binding UI with explicit role checks.
- Image/content ingestion into private Supabase Storage.
- Historical LINE exported-chat import for attendance/invoice migration after preview validation.
- Optional `SKO -> LINE` replies with loop prevention and permissions after the one-way pilot is stable.
