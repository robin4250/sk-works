import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createInspectionEndpoint } from './document_inspection_endpoint.mjs';

const id = '00000000-0000-4000-8000-000000000001';
test('missing dependencies and invalid or anonymous sessions fail before storage', async () => {
  assert.throws(() => createInspectionEndpoint({}), /inspection_unavailable/);
  let reads = 0;
  const db = { async getAuthorizedPendingInspection() { reads++; return null; } };
  for (const session of [null, { active: false, anonymous: false, actorId: id }, { active: true, anonymous: true, actorId: id }, { active: true, actorId: id }]) {
    const endpoint = createInspectionEndpoint({ verifySession: async () => session, db, storage: {}, validateFile: async () => true });
    await assert.rejects(endpoint({ bearerToken: 'test', requestId: id }), /inspection_unavailable/);
  }
  assert.equal(reads, 0);
});
test('actor is taken only from verified session and malformed request fails closed', async () => {
  let actor;
  const db = { async getAuthorizedPendingInspection(input) { actor = input.actorId; return null; } };
  const endpoint = createInspectionEndpoint({ verifySession: async () => ({ active: true, anonymous: false, actorId: id }), db, storage: {}, validateFile: async () => true });
  await assert.rejects(endpoint({ bearerToken: 'test', requestId: 'bad' }), /inspection_unavailable/);
  await assert.rejects(endpoint({ bearerToken: 'test', requestId: id, actorId: 'attacker' }), /inspection_unavailable/);
  assert.equal(actor, id);
});
