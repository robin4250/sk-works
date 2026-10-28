// Disposable SQL fixture checks. No independent owner channel or active key.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {requestIndependentOwnerApproval} from './key-migration-owner-request.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export async function checkOwnerApprovalRequest({pool,args,pendingId,concurrency=false}) {
 const request={...args,pendingId};
 const before=(await pool.query('select count(*) as count from private.master_devices')).rows[0].count;
 const first=await requestIndependentOwnerApproval(request);
 assert.equal(first.status,'awaiting_independent_owner');
 assert.match(first.keySha256,/^[a-f0-9]{64}$/);
 assert.deepEqual(await requestIndependentOwnerApproval(request),first,'unknown response reconciliation must reuse original request');
 if(concurrency){const results=await Promise.all([requestIndependentOwnerApproval(request),requestIndependentOwnerApproval(request)]);for(const result of results)assert.deepEqual(result,first);}
 const otherKey=generateKeyPairSync('ec',{namedCurve:'prime256v1'}).publicKey.export({type:'spki',format:'pem'}).toString();
 await assert.rejects(requestIndependentOwnerApproval({...request,publicKeyPem:otherKey}));
 for(const changed of [{pendingId:id(98)},{challengeId:id(99)},{actor:id(97)},{session:id(96)}])await assert.rejects(requestIndependentOwnerApproval({...request,...changed}));
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.owner_approval_requests')).rows[0].count),1);
 assert.equal((await pool.query('select status from master_device_enrollment_candidate.pending_key_migrations where id=$1',[pendingId])).rows[0].status,'pending');
 assert.equal((await pool.query('select count(*) as count from private.master_devices')).rows[0].count,before,'request must not register or activate a device');
 await pool.query('update private.master_devices set is_locked=true where id=$1',[args.deviceId]);
 await assert.rejects(requestIndependentOwnerApproval(request));
 await pool.query('update private.master_devices set is_locked=false where id=$1',[args.deviceId]);
 for(const role of ['anon','authenticated']){
  const c=await pool.connect();try{await c.query('begin');await c.query('set local role '+role);
   await assert.rejects(c.query('select * from master_device_enrollment_candidate.owner_approval_requests'),e=>e.code==='42501');
  }finally{await c.query('rollback');c.release();}
 }
 // Expire only this synthetic possession proof; no new approval request can
 // renew its lifetime, even though the previous pending proof was consumed.
 await pool.query(`update master_device_enrollment_candidate.key_possession_challenges
  set created_ms=floor(extract(epoch from clock_timestamp())*1000)-120000,
   expires_ms=floor(extract(epoch from clock_timestamp())*1000)-60000 where id=$1`,[args.challengeId]);
 await assert.rejects(requestIndependentOwnerApproval(request));
 console.log('Owner review request: exact original proof, idempotent retry, foreign/locked/expired rejection, client ACL and no key activation passed. Synthetic auth only.');
}
