# SKO LINE bridge setup

SKO currently uses a one-way `LINE -> SKO` bridge for the October 2026 rollout.

## Current production behavior

- Verifies `x-line-signature` with `LINE_CHANNEL_SECRET`.
- Accepts new text messages from LINE group webhook events.
- Stores raw webhook events in service-only `line_webhook_events`.
- Routes ordinary LINE text messages only when a matching `line_group_bindings.status = 'active'` row exists.
- Stores routed chat messages in `chat_messages` with `origin = 'line'`.
- Uses external event/message IDs to avoid duplicates.
- Ignores unbound/pending/disabled groups.
- Does not send SKO replies back to LINE, preventing reply loops.

The deployed Supabase `line-webhook` function is intentionally `verify_jwt = false` because LINE is the caller. Authenticity is enforced by the LINE HMAC signature instead of a Supabase user JWT.

## Explicit secure binding flow

Do not bind a LINE group by browsing globally pending IDs or by guessing the only pending row.

An SKO company owner/admin performs the binding from the Chat screen:

1. Create/select the SKO communication group.
2. Tap **LINE連携する**.
3. SKO creates a one-time 8-character claim code valid for 15 minutes.
4. Send exactly this form into the LINE group that should be connected:

```text
SKO連携 XXXXXXXX
```

5. The verified LINE webhook receives that message together with the real LINE group ID.
6. The service-role-only claim RPC atomically:
   - verifies the one-time code;
   - verifies the claim is still pending and within its validity window;
   - confirms the SKO communication group still belongs to the intended company;
   - refuses a LINE group already active for another company/group;
   - sets `company_id`, `communication_group_id`, and `status = 'active'`;
   - writes an activation record to `line_binding_audit`.
7. Refresh the SKO Chat screen and confirm **LINE連携中**.

This proof-of-control flow prevents arbitrary authenticated users from seeing or claiming other tenants' pending LINE group IDs.

## Disable a binding

Only an SKO company owner/admin can disable an active binding through the app. The disable RPC changes the binding to `status = 'disabled'` and records the action in `line_binding_audit`.

A disabled binding no longer routes normal LINE messages into SKO.

## Relevant production tables

### `line_group_bindings`

- `line_group_id`
- `company_id` nullable while pending
- `communication_group_id` nullable while pending
- `display_name`
- `status`: `pending | active | disabled`
- `discovered_at`
- `updated_at`

### `line_binding_claims`

Stores short-lived owner/admin claim requests.

### `line_binding_audit`

Stores activation/disable audit records.

### `chat_messages`

This is the current chat table. Do not use the obsolete prototype name `communication_messages`.

## Production function permissions

- `begin_line_group_claim(uuid)`
  - authenticated only
  - function itself requires company `owner` or `admin`
- `complete_line_group_claim_for_line(text, text)`
  - service-role only
  - called by the verified LINE webhook
- `disable_line_group_binding(uuid)`
  - authenticated only
  - function itself requires company `owner` or `admin`

The anonymous role must not have execute permission on these RPCs.

## Webhook deployment

Required secret:

- `LINE_CHANNEL_SECRET`

Supabase supplies its own function environment values such as `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.

Deploy:

```bash
supabase functions deploy line-webhook --no-verify-jwt
```

The repository webhook source must stay aligned with the deployed function before further LINE bridge changes are made.

## Pilot test

1. Add the LINE bot to the target LINE group.
2. Create/select an SKO communication group.
3. Start LINE linking from the SKO Chat screen.
4. Send the generated `SKO連携 XXXXXXXX` line into the target LINE group.
5. Confirm the SKO group shows **LINE連携中**.
6. Send an ordinary text message in LINE.
7. Confirm a new `chat_messages` row appears with:
   - matching company/group IDs;
   - `origin = 'line'`;
   - body and external identifiers.
8. Confirm the message appears in the same SKO chat through Realtime.
9. Redeliver the same webhook and confirm deduplication prevents a duplicate chat row.
10. Disable the binding from SKO and confirm subsequent ordinary LINE messages are no longer routed.

## LINE attendance preview rule

LINE-derived attendance remains candidate/preview data until worker/site identities are confirmed. Current safe flow:

- receive LINE text;
- parse date/site/worker candidates;
- exact-match registered worker/site names;
- parse status details such as 定時 / 残業 / 早出 / 夜勤 / 鉄骨;
- display results in the read-only **本日のLINE出勤候補** screen.

Do not silently finalize attendance or invoice records from parsed LINE content.

## Historical LINE export preview

Use the local parser for exported LINE history before any import/write flow:

```bash
dart run tool/line_history_preview.dart path/to/line-chat.txt
```

The preview does not write to Supabase.

## Security rules

- Never expose the service-role key in Flutter.
- Never bypass LINE signature verification.
- Never expose globally pending LINE group IDs to normal users.
- Never auto-claim the only pending group.
- Keep raw `line_webhook_events` service-role only.
- Keep attendance parsing preview-only until master-data identities are confirmed.
