import test from 'node:test';
import assert from 'node:assert/strict';
import {deliverPlatformFixtureWindow} from './platform_batch_delivery.mjs';

const base = {
  projectRef: 'abcdefghijklmnopqrst', source: 'edge_logs',
  from: '2026-10-16T10:00:00.000Z', to: '2026-10-16T10:05:00.000Z',
  hmacKey: Buffer.alloc(32, 7), keyEpoch: 1,
  managementToken: 'fixture-management-credential-only',
};
const row = {
  id: 'fixture-event-identity', timestamp: '2026-10-16T10:01:00.123456Z',
  status: 403, target: '/rest/v1/fixture-sensitive-target?token=private-query',
  ip: '192.0.2.8', headers: {authorization: 'private-header'},
  body: 'private-body', event_message: 'private-event',
};
const response = (rows = [row]) => async () => new Response(JSON.stringify({result: rows}));
const safe = value => assert.doesNotMatch(JSON.stringify(value),
  /fixture-management|fixture-event-identity|192\.0\.2|private-query|private-header|private-body|private-event|fixture-sensitive-target/);
function fixtureStore() {
  const saved = new Map();
  let calls = 0;
  return {
    saved,
    get calls() { return calls; },
    async ingest(name, params) {
      calls++;
      assert.equal(name, 'service_ingest_platform_monitor');
      assert.deepEqual(Object.keys(params), ['p_batch']);
      safe(params);
      const batch = params.p_batch;
      assert.ok(Object.isFrozen(batch) && Object.isFrozen(batch.events));
      for (const event of batch.events) {
        assert.ok(Object.isFrozen(event));
        assert.equal(event.source_key, null);
        assert.equal(event.source_tracking, 'unavailable');
      }
      const key = [batch.source,batch.window_from,batch.window_to,batch.key_epoch].join('|');
      const encoded = JSON.stringify(batch);
      // Fake atomic RPC storage, not a replacement for the existing PG17 tests.
      if (saved.has(key) && saved.get(key) !== encoded) throw Error('fixture conflict private-body');
      saved.set(key, encoded);
      return batch.events.length;
    },
  };
}

test('existing adapter sanitizes before one service RPC; receipt excludes secrets and event IDs', async () => {
  const store = fixtureStore();
  const out = await deliverPlatformFixtureWindow({...base, fetchFixture: response(), ingestFixture: store.ingest});
  assert.equal(store.calls, 1);
  assert.deepEqual(out, {source:base.source,window_from:base.from,window_to:base.to,key_epoch:1,coverage:'bounded_query',event_count:1});
  safe(out); assert.ok(Object.isFrozen(out));
});
test('explicit repeated and concurrent delivery reuse existing idempotent batch without duplicate fixture rows', async () => {
  const store = fixtureStore();
  const options = {...base,fetchFixture:response(),ingestFixture:store.ingest};
  await Promise.all([deliverPlatformFixtureWindow(options),deliverPlatformFixtureWindow(options)]);
  await deliverPlatformFixtureWindow(options);
  assert.equal(store.calls,3); assert.equal(store.saved.size,1);
});
test('conflicting replay preserves saved fixture evidence and never retries', async () => {
  const store = fixtureStore();
  await deliverPlatformFixtureWindow({...base,fetchFixture:response(),ingestFixture:store.ingest});
  const before = [...store.saved];
  await assert.rejects(deliverPlatformFixtureWindow({...base,fetchFixture:response([{...row,status:200}]),ingestFixture:store.ingest}),/^Error: Platform fixture delivery unavailable$/);
  assert.deepEqual([...store.saved],before); assert.equal(store.calls,2);
});
test('invalid collection/window/duplicate never reaches ingestion or changes fixture records', async () => {
  const store = fixtureStore();
  for (const options of [
    {source:'untrusted'}, {to:base.from}, {fetchFixture:response([row,row])},
    {fetchFixture:response([{...row,timestamp:base.to}])},
    {fetchFixture:async()=>{throw Error('private-header');}},
  ]) {
    await assert.rejects(deliverPlatformFixtureWindow({...base,fetchFixture:response(),ingestFixture:store.ingest,...options}),/^Error: Platform fixture delivery unavailable$/);
  }
  assert.equal(store.calls,0); assert.equal(store.saved.size,0);
});
test('failed receipt or lost response is generic; no retry or automatic rollback of accepted evidence', async () => {
  const store = fixtureStore();
  let deliveries=0;
  await assert.rejects(deliverPlatformFixtureWindow({...base,fetchFixture:response(),ingestFixture:async(name,params)=>{
    deliveries++; await store.ingest(name,params); throw Error('private-body credential');
  }}),/^Error: Platform fixture delivery unavailable$/);
  assert.equal(deliveries,1); assert.equal(store.saved.size,1);
  await deliverPlatformFixtureWindow({...base,fetchFixture:response(),ingestFixture:store.ingest});
  assert.equal(store.saved.size,1);
  for (const receipt of [null, true, '1', 2, -1]) {
    let calls=0;
    await assert.rejects(deliverPlatformFixtureWindow({...base,fetchFixture:response(),ingestFixture:async()=>{calls++;return receipt;}}),/^Error: Platform fixture delivery unavailable$/);
    assert.equal(calls,1);
  }
});
test('empty coverage and capacity-limited batches stay explicit without inventing source tracking', async () => {
  const store = fixtureStore();
  const empty=await deliverPlatformFixtureWindow({...base,fetchFixture:response([]),ingestFixture:store.ingest});
  assert.equal(empty.event_count,0); assert.equal(empty.coverage,'bounded_query');
  const full=await deliverPlatformFixtureWindow({...base,keyEpoch:2,fetchFixture:response(Array.from({length:1000},(_,i)=>({...row,id:'fixture-'+i}))),ingestFixture:store.ingest});
  assert.equal(full.event_count,1000);assert.equal(full.coverage,'capacity_limited');
});
test('missing explicit transports never falls back to global network', async () => {
  let calls=0;
  const previous=globalThis.fetch;
  globalThis.fetch=async()=>{calls++;throw Error('unexpected network');};
  try {
    await assert.rejects(deliverPlatformFixtureWindow(base),/^Error: Platform fixture delivery unavailable$/);
    await assert.rejects(deliverPlatformFixtureWindow({...base,fetchFixture:response()}),/^Error: Platform fixture delivery unavailable$/);
    assert.equal(calls,0);
  } finally { globalThis.fetch=previous; }
});
