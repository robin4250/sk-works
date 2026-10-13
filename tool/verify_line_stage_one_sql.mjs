import assert from 'node:assert/strict';
import { createHmac, webcrypto } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createLineWebhookHandler } from '../supabase/functions/line-webhook/handler.mjs';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
globalThis.crypto ??= webcrypto;
const db = new PGlite();
await db.exec(`create table line_webhook_events (webhook_event_id text unique, raw_event jsonb);
  create table chat_messages (origin text not null, external_event_id text, body text, sent_at timestamptz,
    communication_group_id text, unique(origin, external_event_id));
  create unique index chat_messages_line_external_event_uidx on chat_messages(external_event_id)
    where origin='line' and external_event_id is not null;`);
const env = (key) => ({ LINE_CHANNEL_SECRET: 'fixture-secret', SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-only' })[key];
let failChat = true;
const handler = createLineWebhookHandler({ env, logger: { error() {} }, fetch: async (url, init) => {
  const path = url.split('/rest/v1/')[1];
  const row = init.body ? JSON.parse(init.body) : null;
  try {
    if (path.startsWith('line_webhook_events')) {
      await db.query('insert into line_webhook_events values($1,$2::jsonb) on conflict(webhook_event_id) do nothing', [row.webhook_event_id, JSON.stringify(row.raw_event)]);
    } else if (path==='rpc/observe_line_joined_group') { return new Response(null,{status:200});
    } else if (path.startsWith('line_group_bindings')) {
      return Response.json([{ company_id: 'company-one', communication_group_id: 'group-one' }]);
    } else if (path.startsWith('chat_messages')) {
      if (failChat) return new Response('fixture transient error', { status: 500 });
      assert.equal(new URL(url).searchParams.get('on_conflict'), 'origin,external_event_id');
      await db.query('insert into chat_messages values($1,$2,$3,$4,$5) on conflict(origin,external_event_id) do nothing',
        [row.origin, row.external_event_id, row.body, row.sent_at, row.communication_group_id]);
    } else throw new Error('Unexpected request');
    return new Response(null, { status: 201 });
  } catch { return new Response('DB error', { status: 400 }); }
} });
const event = { webhookEventId: 'fixture-event', type: 'message', timestamp: 1791820800000,
  source: { type: 'group', groupId: 'fixture-group', userId: 'fixture-sender' }, message: { type: 'text', id: 'fixture-message', text: '保存する投稿' } };
const request = () => {
  const body = JSON.stringify({ events: [event] });
  return new Request('https://fixture.invalid', { method: 'POST', body,
    headers: { 'x-line-signature': createHmac('sha256', env('LINE_CHANNEL_SECRET')).update(body).digest('base64') } });
};
assert.equal((await handler(request())).status, 503);
assert.equal((await db.query('select count(*)::int n from line_webhook_events')).rows[0].n, 1);
assert.equal((await db.query('select count(*)::int n from chat_messages')).rows[0].n, 0);
failChat = false;
assert.equal((await handler(request())).status, 200);
assert.equal((await handler(request())).status, 200);
const saved = (await db.query('select * from chat_messages')).rows;
assert.equal(saved.length, 1);
assert.equal(saved[0].body, event.message.text);
assert.equal(saved[0].communication_group_id, 'group-one');
assert.equal(new Date(saved[0].sent_at).toISOString(), new Date(event.timestamp).toISOString());
assert.equal((await db.query('select count(*)::int n from line_webhook_events')).rows[0].n, 1);
await db.close();
console.log('LINE stage one: original text persisted, partial failure recovered, duplicate delivery stored exactly once.');

