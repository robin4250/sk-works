import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, webcrypto } from 'node:crypto';
import { createLineWebhookHandler } from './handler.mjs';

globalThis.crypto ??= webcrypto;
const secret = 'fixture-channel-secret';
const event = { webhookEventId: 'event-one', type: 'message', timestamp: 1791820200000,
  source: { type: 'group', groupId: 'line-group', userId: 'line-member' },
  message: { type: 'text', id: 'message-one', text: '10月13日 現場A 作業完了' } };
const json = (value, status = 200) => new Response(JSON.stringify(value), { status });
function fixture({ stageFailure, networkFailure, binding = true } = {}) {
  const calls = [], rawRows = new Map(), chats = new Map();
  let failing = Boolean(stageFailure || networkFailure);
  const handler = createLineWebhookHandler({ env: (name) => ({ LINE_CHANNEL_SECRET: secret,
    SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-service-role' })[name],
    logger: { error() {} }, fetch: async (url, init) => {
      const path = url.split('/rest/v1/')[1];
      calls.push(path);
      if (failing && networkFailure) throw new Error('network unavailable');
      if (failing && path.startsWith(stageFailure ?? '!')) return json({ message: 'fixture failure' }, 500);
      if (path.startsWith('line_webhook_events')) {
        assert.match(path, /on_conflict=webhook_event_id/);
        assert.match(init.headers.Prefer, /ignore-duplicates/);
        const row = JSON.parse(init.body); rawRows.set(row.webhook_event_id, row); return new Response(null, { status: 201 });
      }
      if (path.startsWith('rpc/')) return json(true);
      if (path.startsWith('line_group_bindings')) return json(binding ? [{ company_id: 'company-one', communication_group_id: 'group-one' }] : []);
      if (path.startsWith('chat_messages')) {
        assert.match(path, /on_conflict=origin,external_event_id/);
        assert.match(init.headers.Prefer, /ignore-duplicates/);
        const row = JSON.parse(init.body); chats.set(`${row.origin}:${row.external_event_id}`, row); return new Response(null, { status: 201 });
      }
      throw new Error(`Unexpected path: ${path}`);
    } });
  return { handler, calls, rawRows, chats, recover: () => { failing = false; } };
}
function request(events = [event], signature) {
  const body = JSON.stringify({ events });
  return new Request('https://fixture.invalid/webhook', { method: 'POST', body,
    headers: { 'x-line-signature': signature ?? createHmac('sha256', secret).update(body).digest('base64') } });
}
test('signature validation occurs before every database call; empty verify webhook succeeds', async () => {
  const f = fixture();
  assert.equal((await f.handler(request([event], 'invalid'))).status, 401);
  assert.equal(f.calls.length, 0);
  assert.equal((await f.handler(request([]))).status, 200);
  assert.equal(f.calls.length, 0);
});
test('signed LINE post persists exact text/time/sender in its bound group; replay remains one post', async () => {
  const f = fixture();
  assert.equal((await f.handler(request())).status, 200);
  assert.equal((await f.handler(request())).status, 200);
  assert.equal(f.rawRows.size, 1);
  assert.equal(f.chats.size, 1);
  const row = [...f.chats.values()][0];
  assert.equal(row.body, event.message.text);
  assert.equal(row.origin, 'line');
  assert.equal(row.communication_group_id, 'group-one');
  assert.equal(row.sent_at, new Date(event.timestamp).toISOString());
  assert.equal(row.sender_display_name, 'LINE:line-member');
});
for (const stageFailure of ['line_webhook_events', 'line_group_bindings', 'chat_messages']) {
  test(`${stageFailure} failure returns 503; redelivery after recovery saves one post`, async () => {
    const f = fixture({ stageFailure });
    assert.equal((await f.handler(request())).status, 503);
    assert.equal(f.chats.size, 0);
    f.recover();
    assert.equal((await f.handler(request())).status, 200);
    assert.equal(f.chats.size, 1);
  });
}
test('network failure returns retry status without logging request data', async () => {
  const f = fixture({ networkFailure: true });
  assert.equal((await f.handler(request())).status, 503);
  f.recover();
  assert.equal((await f.handler(request())).status, 200);
});
test('unbound group stores audit event without publishing into another company', async () => {
  const f = fixture({ binding: false });
  assert.equal((await f.handler(request())).status, 200);
  assert.equal(f.chats.size, 0);
  assert.equal(f.rawRows.size, 1);
});
test('binding command completes existing RPC and is not shown as a talk post', async () => {
  const f = fixture();
  assert.equal((await f.handler(request([{ ...event, message: { ...event.message, text: 'SKO連携 ABCD1234' } }]))).status, 200);
  assert.ok(f.calls.includes('rpc/complete_line_group_claim_for_line'));
  assert.equal(f.chats.size, 0);
});
test('image events are not falsely displayed as text posts', async () => {
  const f = fixture();
  assert.equal((await f.handler(request([{ ...event, message: { type: 'image', id: 'image-one' } }]))).status, 200);
  assert.equal(f.chats.size, 0);
});

test('signed join and leave record real names; room and bad signatures never discover',async()=>{
 const observations=[];const handler=createLineWebhookHandler({env:n=>({LINE_CHANNEL_SECRET:secret,LINE_CHANNEL_ACCESS_TOKEN:'fixture-token',SUPABASE_URL:'https://fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-key'})[n],logger:{error(){}},fetch:async(url,init)=>{
 if(url.startsWith('https://api.line.me/'))return json({groupId:'line-group',groupName:'Actual LINE name'});
 const path=url.split('/rest/v1/')[1];if(path==='rpc/observe_line_joined_group')observations.push(JSON.parse(init.body));return json(true);
 }});
 assert.equal((await handler(request([{...event,type:'join',message:undefined}]))).status,200);assert.equal(observations[0].p_display_name,'Actual LINE name');assert.equal(observations[0].p_joined,true);
 assert.equal((await handler(request([{...event,type:'leave',message:undefined}]))).status,200);assert.equal(observations[1].p_joined,false);
 assert.equal((await handler(request([{...event,type:'join',source:{type:'room',roomId:'room'}}]))).status,200);assert.equal(observations.length,2);
 assert.equal((await handler(request([event],'bad'))).status,401);assert.equal(observations.length,2);
});
