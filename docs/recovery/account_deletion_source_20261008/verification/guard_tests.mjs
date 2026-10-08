import {test, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

// Import handlers only, never the Deno.serve entrypoints. Every service is a
// local mock. Any accidental fetch fails and also fails the final audit test.
let networkAttempts = 0;
globalThis.fetch = async () => {
  networkAttempts++;
  throw new Error('NETWORK_FORBIDDEN_IN_ARCHIVED_GUARD_TESTS');
};
const {createHandler, recentlyAuthenticated} = await import('../account-deletion/handler.mjs');
const {intakeConfiguration} = await import('../account-deletion/intake_configuration.mjs');
const {createWorkerHandler} = await import('../account-deletion-worker/account-deletion-worker/handler.mjs');
const {deletionPolicy, officialDocumentReviewBuckets} = await import('../account-deletion/policy.mjs');
const {deletionPolicy: workerPolicy, officialDocumentReviewBuckets: workerBuckets} =
  await import('../account-deletion-worker/account-deletion/policy.mjs');

const subject = '11111111-1111-4111-8111-111111111111';
const session = '22222222-2222-4222-8222-222222222222';
const jobId = '33333333-3333-4333-8333-333333333333';
const now = 1800000000;
const authenticated = () => ({
  user: {id: subject, is_anonymous: false, identities: []},
  claims: {sub: subject, role: 'authenticated', session_id: session,
    amr: [{method: 'password', timestamp: now - 10}]},
});
const request = (method, input, headers = {}) => new Request('https://offline.invalid/guard-test', {
  method, headers,
  ...(method === 'GET' || method === 'HEAD' ? {} :
    {body: typeof input === 'string' ? input : JSON.stringify(input)}),
});
const assertResponse = async (response, status, expected) => {
  assert.equal(response.status, status);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), expected);
};
function intake(overrides = {}) {
  const calls = {status: [], reserve: [], credential: []};
  const handler = createHandler({
    authenticate: async () => authenticated(),
    now: () => now,
    configuration: () => ({enabled: true, policy: deletionPolicy.version, days: deletionPolicy.processingDays}),
    status: async (...args) => {calls.status.push(args); return {status: 'pending'};},
    reserve: async (...args) => {calls.reserve.push(args); return {id: jobId, status: 'pending'};},
    prepareGoogleCredential: async (...args) => {calls.credential.push(args); return null;},
    ...overrides,
  });
  return {handler, calls};
}
function assertNoIntakeWrites(calls) {
  assert.deepEqual(calls.reserve, []);
  assert.deepEqual(calls.credential, []);
}

test('GET passes only authenticated current subject and session to status', async () => {
  const {handler, calls} = intake();
  const req = new Request('https://offline.invalid/guard-test?user=other&session=other');
  await assertResponse(await handler(req), 200, {request: {status: 'pending'}});
  assert.deepEqual(calls.status, [[subject, session]]);
  assertNoIntakeWrites(calls);
});

for (const [name, mutate] of [
  ['missing authentication', () => null],
  ['anonymous user', a => {a.user.is_anonymous = true; return a;}],
  ['subject mismatch', a => {a.claims.sub = jobId; return a;}],
  ['missing session', a => {delete a.claims.session_id; return a;}],
  ['non authenticated role', a => {a.claims.role = 'service_role'; return a;}],
]) {
  for (const method of ['GET', 'POST']) test(`${method} rejects ${name}`, async () => {
    const {handler, calls} = intake({authenticate: async () => mutate(authenticated())});
    await assertResponse(await handler(request(method, {confirm: true})), 401, {error: 'login_required'});
    assert.deepEqual(calls.status, []);
    assertNoIntakeWrites(calls);
  });
}
test('unsupported intake method never authenticates', async () => {
  let calls = 0;
  const {handler} = intake({authenticate: async () => {calls++; return authenticated();}});
  await assertResponse(await handler(request('DELETE', {})), 405, {error: 'method_not_allowed'});
  assert.equal(calls, 0);
});

for (const [name, input] of [
  ['missing confirmation', {}], ['false confirmation', {confirm: false}],
  ['string confirmation', {confirm: 'true'}], ['unknown key', {confirm: true, user: jobId}],
  ['null body', 'null'], ['malformed JSON', '{'],
  ['body over byte limit', JSON.stringify({confirm: true, padding: 'x'.repeat(16384)})],
  ['empty Google token', {confirm: true, google_refresh_token: ''}],
  ['non string Google token', {confirm: true, google_refresh_token: 123}],
  ['oversized Google token', {confirm: true, google_refresh_token: 'x'.repeat(8193)}],
]) test(`POST rejects ${name} before credential or reserve`, async () => {
  const {handler, calls} = intake();
  await assertResponse(await handler(request('POST', input)), 400, {error: 'confirmation_required'});
  assertNoIntakeWrites(calls);
});

for (const [name, amr] of [
  ['missing AMR', undefined], ['refresh only', [{method: 'token_refresh', timestamp: now}]],
  ['older than ten minutes', [{method: 'password', timestamp: now - 601}]],
  ['future timestamp', [{method: 'password', timestamp: now + 1}]],
  ['non integer timestamp', [{method: 'password', timestamp: now - 0.5}]],
]) test(`POST requires recent authentication: ${name}`, async () => {
  const auth = authenticated(); auth.claims.amr = amr;
  const {handler, calls} = intake({authenticate: async () => auth});
  await assertResponse(await handler(request('POST', {confirm: true})), 403, {error: 'reauthentication_required'});
  assertNoIntakeWrites(calls);
});
test('reauthentication accepts supported methods at exact ten minute boundary', () => {
  for (const method of ['password', 'oauth', 'otp', 'totp', 'sso/saml', 'magiclink']) {
    assert.equal(recentlyAuthenticated({amr: [{method, timestamp: now - 600}]}, now), true);
  }
  assert.equal(recentlyAuthenticated({amr: [{method: 'token_refresh', timestamp: now}]}, now), false);
});
test('user metadata and last sign in cannot substitute for AMR', async () => {
  const auth = authenticated(); delete auth.claims.amr;
  auth.user.user_metadata = {amr: [{method: 'password', timestamp: now}]};
  auth.user.last_sign_in_at = new Date(now * 1000).toISOString();
  const {handler, calls} = intake({authenticate: async () => auth});
  await assertResponse(await handler(request('POST', {confirm: true})), 403, {error: 'reauthentication_required'});
  assertNoIntakeWrites(calls);
});
test('actual archived intake release flag stays disabled even with env true', async () => {
  const config = intakeConfiguration(() => 'true');
  assert.equal(config.enabled, false);
  assert.equal(config.policy, deletionPolicy.version);
  assert.equal(config.days, deletionPolicy.processingDays);
  const auth = authenticated(); auth.user.identities = [{provider: 'google'}];
  const {handler, calls} = intake({authenticate: async () => auth, configuration: () => config});
  await assertResponse(await handler(request('POST', {confirm: true, google_refresh_token: 'synthetic-token'})), 503, {error: 'unavailable'});
  assertNoIntakeWrites(calls);
});
for (const [name, config] of [
  ['disabled', {enabled: false, policy: 'synthetic', days: 30}],
  ['missing policy', {enabled: true, policy: '', days: 30}],
  ['zero days', {enabled: true, policy: 'synthetic', days: 0}],
  ['more than ninety days', {enabled: true, policy: 'synthetic', days: 91}],
  ['fractional days', {enabled: true, policy: 'synthetic', days: 1.5}],
]) test(`invalid mocked configuration ${name} has no intake side effects`, async () => {
  const {handler, calls} = intake({configuration: () => config});
  await assertResponse(await handler(request('POST', {confirm: true})), 503, {error: 'unavailable'});
  assertNoIntakeWrites(calls);
});
test('reserve failure returns safe 503 without backend details', async () => {
  const {handler} = intake({reserve: async () => {throw Error('synthetic-private-detail');}});
  await assertResponse(await handler(request('POST', {confirm: true})), 503, {error: 'unavailable'});
});
test('status failure returns safe 503 without backend details', async () => {
  const {handler} = intake({status: async () => {throw Error('synthetic-private-detail');}});
  await assertResponse(await handler(request('GET')), 503, {error: 'unavailable'});
});
test('mock intake returns 202 pending, never manufactures completed status', async () => {
  const {handler, calls} = intake();
  await assertResponse(await handler(request('POST', {confirm: true})), 202, {id: jobId, status: 'pending'});
  assert.deepEqual(calls.reserve, [[subject, session, deletionPolicy.version, deletionPolicy.processingDays]]);
  assert.deepEqual(calls.credential, [[authenticated().user, session, undefined]]);
});
test('exact 16384 byte valid JSON body is accepted through mocked intake', async () => {
  const json = JSON.stringify({confirm: true});
  const input = json + ' '.repeat(16384 - Buffer.byteLength(json));
  const {handler, calls} = intake();
  await assertResponse(await handler(request('POST', input)), 202, {id: jobId, status: 'pending'});
  assert.equal(calls.reserve.length, 1);
});
test('chunked otherwise valid JSON over 16384 bytes is cancelled before writes', async () => {
  const json = JSON.stringify({confirm: true});
  const first = new TextEncoder().encode(json + ' '.repeat(16384 - Buffer.byteLength(json)));
  let cancelled = false;
  const stream = new ReadableStream({start(controller) {
    controller.enqueue(first); controller.enqueue(new Uint8Array([32]));
    // Remain open so cancellation is observable rather than already closed.
  }, cancel() {cancelled = true;}});
  const req = new Request('https://offline.invalid/guard-test', {method: 'POST', body: stream, duplex: 'half'});
  const {handler, calls} = intake();
  await assertResponse(await handler(req), 400, {error: 'confirmation_required'});
  assert.equal(cancelled, true);
  assertNoIntakeWrites(calls);
});
test('Google token maximum boundary passes only to injected preparation', async () => {
  const token = 'x'.repeat(8192);
  const auth = authenticated(); auth.user.identities = [{provider: 'google'}];
  const credential = {synthetic: true};
  const {handler, calls} = intake({authenticate: async () => auth,
    prepareGoogleCredential: async (user, sessionId, supplied) => {
      assert.deepEqual(user, auth.user); assert.equal(sessionId, session); assert.equal(supplied, token);
      return credential;
    }});
  await assertResponse(await handler(request('POST', {confirm: true, google_refresh_token: token})), 202, {id: jobId, status: 'pending'});
  assert.deepEqual(calls.reserve, [[subject, session, deletionPolicy.version, deletionPolicy.processingDays, credential]]);
});
test('Google identity without preparation adapter cannot reserve', async () => {
  const auth = authenticated(); auth.user.identities = [{provider: 'google'}];
  const {handler, calls} = intake({authenticate: async () => auth, prepareGoogleCredential: undefined});
  await assertResponse(await handler(request('POST', {confirm: true})), 503, {error: 'unavailable'});
  assertNoIntakeWrites(calls);
});

// This is a visibly synthetic mock secret, not a Supabase credential.
const mockKey = 'offline-test-key-not-a-credential';
function worker(overrides = {}) {
  const calls = {create: 0, jobs: []};
  const handler = createWorkerHandler({serviceKey: mockKey, enabled: () => true,
    createRun: () => {calls.create++; return async id => {calls.jobs.push(id); return {status: 'completed'};};},
    ...overrides});
  return {handler, calls};
}
const workerRequest = (method = 'POST', input = {jobId}, authorization = `Bearer ${mockKey}`) =>
  request(method, input, authorization === undefined ? {} : {authorization});
for (const [name, overrides, req, code, error] of [
  ['missing server key', {serviceKey: ''}, workerRequest(), 403, 'forbidden'],
  ['wrong key', {}, workerRequest('POST', {jobId}, 'Bearer wrong-synthetic-key'), 403, 'forbidden'],
  ['missing authorization', {}, request('POST', {jobId}), 403, 'forbidden'],
  ['non POST', {}, workerRequest('GET'), 405, 'method_not_allowed'],
  ['disabled', {enabled: () => false}, workerRequest(), 503, 'worker_disabled'],
  ['truthy non boolean enable flag', {enabled: () => 'true'}, workerRequest(), 503, 'worker_disabled'],
  ['bad JSON', {}, workerRequest('POST', '{'), 503, 'worker_unavailable'],
  ['oversized body', {}, workerRequest('POST', 'x'.repeat(101)), 400, 'invalid_request'],
  ['invalid job identifier', {}, workerRequest('POST', {jobId: 'not-a-uuid'}), 400, 'invalid_request'],
  ['missing job identifier', {}, workerRequest('POST', {}), 400, 'invalid_request'],
  ['unknown key', {}, workerRequest('POST', {jobId, user: subject}), 400, 'invalid_request'],
  ['null body', {}, workerRequest('POST', 'null'), 400, 'invalid_request'],
]) test(`worker rejects ${name} without creating a run`, async () => {
  const {handler, calls} = worker(overrides);
  await assertResponse(await handler(req), code, {error});
  assert.equal(calls.create, 0); assert.deepEqual(calls.jobs, []);
});
test('mock worker completed status returns 200 only for injected run', async () => {
  const {handler, calls} = worker();
  await assertResponse(await handler(workerRequest()), 200, {status: 'completed'});
  assert.equal(calls.create, 1); assert.deepEqual(calls.jobs, [jobId]);
});
test('mock worker failed status remains 409', async () => {
  const {handler} = worker({createRun: () => async () => ({status: 'failed'})});
  await assertResponse(await handler(workerRequest()), 409, {status: 'failed'});
});
test('mock run exception returns safe 503', async () => {
  const {handler} = worker({createRun: () => async () => {throw Error('synthetic-private-detail');}});
  await assertResponse(await handler(workerRequest()), 503, {error: 'worker_unavailable'});
});
test('worker deployment entrypoint release flag remains false (read only)', async () => {
  const source = await readFile(new URL('../account-deletion-worker/account-deletion-worker/index.ts', import.meta.url), 'utf8');
  assert.match(source, /const\s+lifecycleReleaseVerified\s*=\s*false\s*;/);
  assert.match(source, /enabled:\(\)=>lifecycleReleaseVerified&&env\('ACCOUNT_DELETION_WORKER_ENABLED'\)==='true'/);
});
test('both archived policies retain existing unfinalized record classification', () => {
  assert.deepEqual(workerPolicy, deletionPolicy);
  assert.deepEqual(workerBuckets, officialDocumentReviewBuckets);
  assert.equal(deletionPolicy.version, '2026-09-26-company-records-retained-v1');
  assert.equal(deletionPolicy.processingDays, 30);
  assert.equal(deletionPolicy.officialDocumentRetentionFinalized, false);
  assert.deepEqual(deletionPolicy.retainedCompanyRecords, ['payroll', 'invoices', 'signed_daily_reports']);
  assert.equal(Object.isFrozen(deletionPolicy), true);
  assert.equal(Object.isFrozen(deletionPolicy.retainedCompanyRecords), true);
  assert.equal(Object.isFrozen(officialDocumentReviewBuckets), true);
});
after(() => assert.equal(networkAttempts, 0, 'all guards must run with zero network requests'));
