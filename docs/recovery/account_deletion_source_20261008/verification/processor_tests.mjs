import {test, after} from 'node:test';
import assert from 'node:assert/strict';

// Pure orchestration with synthetic jobs and in-memory ports only. Never import
// index.ts or persistent adapters. An accidental network request fails the audit.
let networkAttempts = 0;
globalThis.fetch = async () => {
  networkAttempts++;
  throw new Error('NETWORK_FORBIDDEN_IN_ARCHIVED_PROCESSOR_TESTS');
};
const {processDeletion, deletionSteps} = await import('../account-deletion-worker/account-deletion/processor.mjs');
const id = '33333333-3333-4333-8333-333333333333';
const userId = '11111111-1111-4111-8111-111111111111';
const planDigest = 'a'.repeat(64);
const makeJob = () => ({id, userId, policyVersion: 'offline-review-1', reviewedPlanDigest: planDigest, completedSteps: []});
const operations = ['claim', 'checkEligibility', 'renew', 'checkpoint', 'complete', 'fail', ...deletionSteps];
function fixture(job = makeJob(), overrides = {}) {
  const calls = [];
  const ports = {};
  for (const name of operations) ports[name] = async (...args) => {
    calls.push({name, args});
    if (Object.hasOwn(overrides, name)) return await overrides[name](...args);
    return name === 'claim' ? job : true;
  };
  return {job, ports, calls};
}
const names = f => f.calls.map(c => c.name);
const expectFailure = (result, step) => assert.deepEqual(result, {status: 'failed', step});
function expectedSequence(prefix = 0) {
  return ['claim', 'checkEligibility', ...deletionSteps.slice(prefix).flatMap(s => ['renew', s, 'checkpoint']), 'complete'];
}
function assertFailedAt(f, step) {
  const attempted = f.calls.filter(c => deletionSteps.includes(c.name)).map(c => c.name);
  const index = deletionSteps.indexOf(step);
  assert.deepEqual(attempted, index < 0 ? [] : deletionSteps.slice(0, index + 1));
  assert.equal(f.calls.filter(c => c.name === 'fail').length, 1);
  assert.deepEqual(f.calls.at(-1).args, [f.job, step]);
  assert.equal(names(f).includes('complete'), false);
}

test('eight reviewed steps run in order with lease and checkpoint around every adapter', async () => {
  const f = fixture();
  assert.deepEqual(deletionSteps, ['restrictAccess', 'preserveRequiredRecords', 'revokeExternalIdentity', 'erasePersonalContent', 'erasePersonalFiles', 'eraseAuthAccount', 'verifyErasure', 'notifyCompletion']);
  assert.equal(Object.isFrozen(deletionSteps), true);
  assert.deepEqual(await processDeletion(id, f.ports), {status: 'completed'});
  assert.deepEqual(names(f), expectedSequence());
  for (const c of f.calls) {
    if (c.name === 'claim') assert.deepEqual(c.args, [id]);
    else assert.equal(c.args[0], f.job);
    if (deletionSteps.includes(c.name)) assert.equal(c.args[1], `${id}:${c.name}`);
  }
});
for (const invalidId of ['', 'other-user', '33333333-3333-4333-8333-33333333333Z']) test(`invalid request id ${JSON.stringify(invalidId)} rejects before claim`, async () => {
  const f = fixture();
  await assert.rejects(processDeletion(invalidId, f.ports), {message: 'invalid_job'});
  assert.deepEqual(f.calls, []);
});
for (const missing of operations) test(`missing required port ${missing} rejects before claim`, async () => {
  const f = fixture();
  delete f.ports[missing];
  await assert.rejects(processDeletion(id, f.ports), {message: 'incomplete_processor'});
  assert.deepEqual(f.calls, []);
});
for (const noJob of [null, undefined, false]) test(`claim ${String(noJob)} returns busy without writes`, async () => {
  const f = fixture(makeJob(), {claim: async () => noJob});
  assert.deepEqual(await processDeletion(id, f.ports), {status: 'busy_or_unavailable'});
  assert.deepEqual(names(f), ['claim']);
});
test('claim exception propagates without beginning lifecycle or recording a fake job failure', async () => {
  const f = fixture(makeJob(), {claim: async () => {throw Error('offline_claim_failure');}});
  await assert.rejects(processDeletion(id, f.ports), {message: 'offline_claim_failure'});
  assert.deepEqual(names(f), ['claim']);
});
const invalidPlans = [
  ['mismatched job id', j => {j.id = userId;}],
  ['invalid target user', j => {j.userId = 'not-a-uuid';}],
  ['missing target user', j => {delete j.userId;}],
  ['missing policy', j => {delete j.policyVersion;}],
  ['empty policy', j => {j.policyVersion = '';}],
  ['nonstring policy', j => {j.policyVersion = 1;}],
  ['missing digest', j => {delete j.reviewedPlanDigest;}],
  ['short digest', j => {j.reviewedPlanDigest = 'a'.repeat(63);}],
  ['uppercase digest', j => {j.reviewedPlanDigest = 'A'.repeat(64);}],
  ['nonhex digest', j => {j.reviewedPlanDigest = 'g'.repeat(64);}],
  ['nonarray completed prefix', j => {j.completedSteps = 'restrictAccess';}],
  ['missing completed prefix', j => {delete j.completedSteps;}],
  ['skipped step', j => {j.completedSteps = [deletionSteps[1]];}],
  ['reordered prefix', j => {j.completedSteps = [deletionSteps[1], deletionSteps[0]];}],
  ['duplicated step', j => {j.completedSteps = [deletionSteps[0], deletionSteps[0]];}],
  ['unknown step', j => {j.completedSteps = ['deleteEverything'];}],
  ['overlong prefix', j => {j.completedSteps = [...deletionSteps, deletionSteps[0]];}],
];
for (const [label, mutate] of invalidPlans) test(`invalid plan: ${label} never evaluates eligibility or runs adapters`, async () => {
  const j = makeJob(); mutate(j); const f = fixture(j);
  expectFailure(await processDeletion(id, f.ports), 'eligibility');
  assert.deepEqual(names(f), ['claim', 'fail']);
  assert.deepEqual(f.calls.at(-1).args, [j, 'eligibility']);
});
for (const value of [false, undefined, 'true', 1]) test(`eligibility requires exact true (${String(value)})`, async () => {
  const f = fixture(makeJob(), {checkEligibility: async () => value});
  expectFailure(await processDeletion(id, f.ports), 'eligibility');
  assert.deepEqual(names(f), ['claim', 'checkEligibility', 'fail']);
});
test('eligibility exception records only eligibility, without leaking exception contents', async () => {
  const f = fixture(makeJob(), {checkEligibility: async () => {throw Error('SYNTHETIC_PRIVATE_PROVIDER_RESPONSE');}});
  expectFailure(await processDeletion(id, f.ports), 'eligibility');
  assert.deepEqual(f.calls.at(-1).args, [f.job, 'eligibility']);
});
for (let prefix = 0; prefix <= deletionSteps.length; prefix++) test(`retry prefix length ${prefix} checks eligibility and skips every completed adapter`, async () => {
  const j = makeJob(); j.completedSteps = deletionSteps.slice(0, prefix); const f = fixture(j);
  assert.deepEqual(await processDeletion(id, f.ports), {status: 'completed'});
  assert.deepEqual(names(f), expectedSequence(prefix));
});
test('retry with completed prefix cannot bypass changed eligibility', async () => {
  const j = makeJob(); j.completedSteps = deletionSteps.slice(0, 5);
  const f = fixture(j, {checkEligibility: async () => false});
  expectFailure(await processDeletion(id, f.ports), 'eligibility');
  assert.deepEqual(names(f), ['claim', 'checkEligibility', 'fail']);
});
for (const step of deletionSteps) {
  for (const [label, behavior] of [
    ['false', async () => false], ['undefined', async () => undefined],
    ['truthy nonboolean', async () => 'true'], ['exception', async () => {throw Error('offline_adapter_failure');}],
  ]) test(`${step} ${label} fails current step and runs no later adapter`, async () => {
    const f = fixture(makeJob(), {[step]: behavior});
    expectFailure(await processDeletion(id, f.ports), step);
    assertFailedAt(f, step);
    const completed = f.calls.filter(c => c.name === 'checkpoint').map(c => c.args[1]);
    assert.deepEqual(completed, deletionSteps.slice(0, deletionSteps.indexOf(step)));
  });
  for (const phase of ['renew', 'checkpoint']) {
    test(`${step} ${phase} false loses lease without failure or later effects`, async () => {
      const index = deletionSteps.indexOf(step); let count = 0;
      const f = fixture(makeJob(), {[phase]: async () => ++count !== index + 1});
      assert.deepEqual(await processDeletion(id, f.ports), {status: 'lease_lost'});
      assert.equal(names(f).includes('fail'), false);
      assert.equal(names(f).includes('complete'), false);
      assert.deepEqual(f.calls.filter(c => deletionSteps.includes(c.name)).map(c => c.name), deletionSteps.slice(0, index + (phase === 'renew' ? 0 : 1)));
      assert.equal(f.calls.at(-1).name, phase);
    });
    test(`${step} ${phase} rejection fails current step and stops`, async () => {
      const index = deletionSteps.indexOf(step); let count = 0;
      const f = fixture(makeJob(), {[phase]: async () => {if (++count === index + 1) throw Error('offline_lease_failure'); return true;}});
      expectFailure(await processDeletion(id, f.ports), step);
      assert.deepEqual(f.calls.at(-1).args, [f.job, step]);
      assert.equal(names(f).includes('complete'), false);
      assert.deepEqual(f.calls.filter(c => deletionSteps.includes(c.name)).map(c => c.name), deletionSteps.slice(0, index + (phase === 'renew' ? 0 : 1)));
    });
  }
}
test('checkpoint loss retries external operation with the same idempotency key, skipping persisted prefix', async () => {
  const target = deletionSteps[3]; const j = makeJob();
  const first = fixture(j, {checkpoint: async (_job, step) => {
    if (step === target) return false;
    j.completedSteps.push(step); return true;
  }});
  assert.deepEqual(await processDeletion(id, first.ports), {status: 'lease_lost'});
  assert.deepEqual(j.completedSteps, deletionSteps.slice(0, 3));
  const second = fixture(j);
  assert.deepEqual(await processDeletion(id, second.ports), {status: 'completed'});
  assert.deepEqual(names(second), expectedSequence(3));
  const key1 = first.calls.find(c => c.name === target).args[1];
  const key2 = second.calls.find(c => c.name === target).args[1];
  assert.equal(key1, key2);
  assert.equal(key2, `${id}:${target}`);
});
for (const value of [false, undefined, 'true']) test(`complete ${String(value)} returns lease lost, never successful completion`, async () => {
  const f = fixture(makeJob(), {complete: async () => value});
  assert.deepEqual(await processDeletion(id, f.ports), {status: 'lease_lost'});
  assert.deepEqual(names(f), expectedSequence());
});
test('complete rejection records current final step and returns failed', async () => {
  const f = fixture(makeJob(), {complete: async () => {throw Error('offline_complete_failure');}});
  expectFailure(await processDeletion(id, f.ports), deletionSteps.at(-1));
  assert.deepEqual(f.calls.at(-1).args, [f.job, deletionSteps.at(-1)]);
});
test('failure recording rejection is suppressed without changing failed result', async () => {
  const f = fixture(makeJob(), {erasePersonalContent: async () => false, fail: async () => {throw Error('offline_failure_record_error');}});
  expectFailure(await processDeletion(id, f.ports), 'erasePersonalContent');
  assertFailedAt(f, 'erasePersonalContent');
});
after(() => assert.equal(networkAttempts, 0, 'No network attempt is permitted'));
