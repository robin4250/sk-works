import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, webcrypto } from 'node:crypto';
import { createLineWebhookHandler, MAX_WEBHOOK_BYTES } from './handler.mjs';

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
      assert.ok(init.signal instanceof AbortSignal);
      assert.equal(init.redirect, 'error');
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
 assert.ok(init.signal instanceof AbortSignal);assert.equal(init.redirect,'error');
 if(url.startsWith('https://api.line.me/'))return json({groupId:'line-group',groupName:'Actual LINE name'});
 const path=url.split('/rest/v1/')[1];if(path==='rpc/observe_line_joined_group')observations.push(JSON.parse(init.body));return json(true);
 }});
 assert.equal((await handler(request([{...event,type:'join',message:undefined}]))).status,200);assert.equal(observations[0].p_display_name,'Actual LINE name');assert.equal(observations[0].p_joined,true);
 assert.equal((await handler(request([{...event,type:'leave',message:undefined}]))).status,200);assert.equal(observations[1].p_joined,false);
 assert.equal((await handler(request([{...event,type:'join',source:{type:'room',roomId:'room'}}]))).status,200);assert.equal(observations.length,2);
 assert.equal((await handler(request([event],'bad'))).status,401);assert.equal(observations.length,2);
});

function streamedRequest(chunks, { length = '1', signature = 'invalid', onCancel = () => {} } = {}) {
  let index = 0;
  const body = new ReadableStream({
    pull(controller) { if (index === chunks.length) controller.close(); else controller.enqueue(chunks[index++]); },
    cancel: onCancel,
  });
  const headers = { 'x-line-signature': signature };
  if (length !== '') headers['content-length'] = length;
  return new Request('https://fixture.invalid/webhook', { method: 'POST', body, duplex: 'half', headers });
}
test('actual stream bytes cap overrides absent or deceptive content length and cancels', async () => {
  for (const length of ['1', '', String(MAX_WEBHOOK_BYTES + 100)]) {
    const f = fixture(); let cancelled = false;
    const req = streamedRequest([new Uint8Array(MAX_WEBHOOK_BYTES), new Uint8Array(1), new Uint8Array(1)],
      { length, onCancel: () => { cancelled = true; } });
    assert.equal((await f.handler(req)).status, 413);
    assert.equal(cancelled, true);
    assert.equal(f.calls.length, 0);
  }
});
test('signed exact limit succeeds and split Japanese UTF-8 preserves raw signature', async () => {
  const prefix = '{"events":[],"padding":"', suffix = '"}';
  const bytes = new TextEncoder().encode(prefix + ' '.repeat(MAX_WEBHOOK_BYTES - prefix.length - suffix.length) + suffix);
  const f = fixture();
  assert.equal((await f.handler(streamedRequest([bytes], {
    signature: createHmac('sha256', secret).update(bytes).digest('base64'),
  }))).status, 200);
  const raw = new TextEncoder().encode(JSON.stringify({ events: [event] }));
  const signature = createHmac('sha256', secret).update(raw).digest('base64');
  const split = raw.findIndex(value => value > 127) + 1;
  assert.equal((await f.handler(streamedRequest([raw.slice(0, split), raw.slice(split)], { signature }))).status, 200);
  assert.equal([...f.chats.values()][0].body, event.message.text);
});
test('method, changed bytes, invalid UTF-8 and read errors never persist', async () => {
  const f = fixture();
  assert.equal((await f.handler(new Request('https://fixture.invalid/webhook'))).status, 405);
  const bytes = Uint8Array.of(255);
  assert.equal((await f.handler(streamedRequest([bytes], {
    signature: createHmac('sha256', secret).update(bytes).digest('base64'),
  }))).status, 400);
  const stream = new ReadableStream({ pull(controller) { controller.error(new Error('PRIVATE-body')); } });
  assert.equal((await f.handler(new Request('https://fixture.invalid/webhook', {
    method: 'POST', body: stream, duplex: 'half',
  }))).status, 400);
  assert.equal(f.calls.length, 0);
});
test('every LINE and database request is bounded and refuses redirects', async () => {
  const paths = [];
  const handler = createLineWebhookHandler({
    env: name => ({ LINE_CHANNEL_SECRET: secret, LINE_CHANNEL_ACCESS_TOKEN: 'fixture-token',
      SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-key' })[name],
    logger: { error() {} }, fetch: async (url, init) => {
      assert.ok(init.signal instanceof AbortSignal); assert.equal(init.redirect, 'error');
      paths.push(url);
      if (url.endsWith('/summary')) return json({ groupId: 'line-group', groupName: '実名' });
      if (url.includes('/member/')) return json({ displayName: '本人' });
      if (url.includes('line_group_bindings?')) return json([{ company_id: 'c', communication_group_id: 'g' }]);
      return json(true);
    },
  });
  assert.equal((await handler(request())).status, 200);
  assert.ok(paths.some(path => path.includes('/member/')));
  assert.ok(paths.some(path => path.includes('/summary')));
  assert.ok(paths.some(path => path.includes('chat_messages?')));
});

test('overlimit rejection does not wait for a stalled stream cancellation', async () => {
  const f = fixture(); let cancelled = false;
  const response = await f.handler(streamedRequest([new Uint8Array(MAX_WEBHOOK_BYTES + 1)], {
    onCancel: () => { cancelled = true; return new Promise(() => {}); },
  }));
  assert.equal(response.status, 413); assert.equal(cancelled, true); assert.equal(f.calls.length, 0);
});
test('signature is not recomputed over modified JSON or normalized text', async () => {
  const f = fixture(), raw = JSON.stringify({ events: [event] });
  const signature = createHmac('sha256', secret).update(raw).digest('base64');
  const changed = new TextEncoder().encode(raw.replace('作業完了', '作業変更'));
  assert.equal((await f.handler(streamedRequest([changed], { signature }))).status, 401);
  assert.equal(f.calls.length, 0);
});
