# SKO LINE bridge pilot setup

This is the first, one-way `LINE -> SKO` bridge for the October 2026 rollout.

## Current scope

- Verifies `x-line-signature` with `LINE_CHANNEL_SECRET` before processing.
- Accepts new **text messages** from LINE **group** webhook events.
- Looks up an explicit `line_group_bindings` record.
- Stores the message in `communication_messages` with `origin = 'line'`.
- Keeps LINE message IDs for deduplication and the sender user ID for later profile enrichment.
- Ignores unbound groups and non-text events.
- Does not send SKO replies back to LINE yet, preventing reply loops in the pilot.

## Prerequisites

1. Deploy the chat migration from the site-chat PR first.
2. Deploy `20260918114500_add_line_bridge_foundation.sql`.
3. Create a LINE Official Account / Messaging API channel and allow the bot to be added to groups.
4. Set the Supabase Edge Function secret:
   - `LINE_CHANNEL_SECRET`
5. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to Supabase Edge Functions by the project environment.
6. Deploy the function:

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
5. Open the same SKO communication group and confirm the message appears through Realtime.
6. Send the same webhook payload again and confirm the external message ID uniqueness prevents a duplicate record.

## Security notes

- Never expose the service-role key in the Flutter app.
- Never accept a webhook without verifying `x-line-signature` against the exact raw request body.
- Normal authenticated SKO users cannot create `origin = 'line'` messages through the existing chat RLS policy.
- `line_group_bindings` is readable only within the same company; writes are service-role/admin-only until a dedicated admin binding UI and role policy are added.

## Next steps

- Optional admin binding UI with explicit role checks.
- LINE member profile lookup using a channel access token so sender display names can be enriched.
- Image/content ingestion into private Supabase Storage.
- Historical LINE exported-chat import for attendance/invoice migration.
- Optional `SKO -> LINE` replies with loop prevention and permissions after the one-way pilot is stable.
