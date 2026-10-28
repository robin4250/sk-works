// Disposable SQL fixture checks. No independent owner channel or active key.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {requestIndependentOwnerApproval} from './key-migration-owner-request.mjs';
import {cancelIndependentOwnerApprovalRequest,inspectIndependentOwnerApprovalRequest} from './key-migration-owner-request-lifecycle.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export async function checkOwnerApprovalRequest({pool,args,pendingId,concurrency=false}) {
 const request={...args,pendingId};
 const before=(await pool.query('select count(*) as count from private.master_devices')).rows[0].count;
 const first=await requestIndependentOwnerApproval(request);
 assert.equal(first.status,'awaiting_independent_owner');
 const lifecycle={pool:args.pool,actor:args.actor,session:args.session,requestId:first.id};
 assert.deepEqual(await inspectIndependentOwnerApprovalRequest(lifecycle),first);
 for(const changed of [{actor:id(97)},{session:id(96)},{requestId:id(99)}]){
  await assert.rejects(inspectIndependentOwnerApprovalRequest({...lifecycle,...changed}));
  await assert.rejects(cancelIndependentOwnerApprovalRequest({...lifecycle,...changed}));
 }
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
  // The failed statement aborts the transaction, so inspect the second private
  // table under a separate transaction rather than accepting a 25P02 error.
  }finally{await c.query('rollback');c.release();}
  const next=await pool.connect();try{await next.query('begin');await next.query('set local role '+role);
   await assert.rejects(next.query('select * from master_device_enrollment_candidate.owner_approval_request_cancellations'),e=>e.code==='42501');
  }finally{await next.query('rollback');next.release();}
 }
 // Expire only this synthetic possession proof; no new approval request can
 // renew its lifetime, even though the previous pending proof was consumed.
 await pool.query(`update master_device_enrollment_candidate.key_possession_challenges
  set created_ms=floor(extract(epoch from clock_timestamp())*1000)-120000,
   expires_ms=floor(extract(epoch from clock_timestamp())*1000)-60000 where id=$1`,[args.challengeId]);
 await pool.query(`update master_device_enrollment_candidate.owner_approval_requests set expires_ms=
  (select expires_ms from master_device_enrollment_candidate.key_possession_challenges where id=$1) where id=$2`,[args.challengeId,first.id]);
 await assert.rejects(requestIndependentOwnerApproval(request));
 assert.equal((await inspectIndependentOwnerApprovalRequest(lifecycle)).status,'expired');
 // Withdraw even an expired request to a now-locked device. This is a refusal,
 // never device unlock, key revocation, or a substitute for independent approval.
 await pool.query('update private.master_devices set is_locked=true where id=$1',[args.deviceId]);
 const cancelled=await cancelIndependentOwnerApprovalRequest(lifecycle);
 assert.equal(cancelled.status,'cancelled');
 assert.deepEqual(await cancelIndependentOwnerApprovalRequest(lifecycle),cancelled);
 if(concurrency){const results=await Promise.all([cancelIndependentOwnerApprovalRequest(lifecycle),inspectIndependentOwnerApprovalRequest(lifecycle)]);for(const result of results)assert.deepEqual(result,cancelled);}
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.owner_approval_request_cancellations')).rows[0].count),1);
 assert.deepEqual(await inspectIndependentOwnerApprovalRequest(lifecycle),cancelled);
 await pool.query('update private.master_devices set is_locked=false where id=$1',[args.deviceId]);
 // Even restoring a synthetic proof's time cannot resurrect a cancelled request.
 await pool.query(`update master_device_enrollment_candidate.key_possession_challenges
  set created_ms=floor(extract(epoch from clock_timestamp())*1000),expires_ms=floor(extract(epoch from clock_timestamp())*1000)+60000 where id=$1`,[args.challengeId]);
 await pool.query(`update master_device_enrollment_candidate.owner_approval_requests set expires_ms=
  (select expires_ms from master_device_enrollment_candidate.key_possession_challenges where id=$1) where id=$2`,[args.challengeId,first.id]);
 await assert.rejects(requestIndependentOwnerApproval(request));
 assert.equal((await pool.query('select status from master_device_enrollment_candidate.pending_key_migrations where id=$1',[pendingId])).rows[0].status,'pending');
 assert.equal((await pool.query('select count(*) as count from private.master_devices')).rows[0].count,before);
 console.log('Owner review request: exact proof, retry/status/cancel, foreign/locked/expired rejection, client ACL and no key activation passed. Synthetic auth only.');
}
