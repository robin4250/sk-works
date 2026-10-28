// Disposable SQL fixture checks. No independent owner channel or active key.
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync,sign,verify} from 'node:crypto';
import {ownerDecisionPayload} from './owner-decision-attestation.mjs';
import {recordIndependentOwnerDecisionEvidence} from './owner-decision-evidence.mjs';
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
 // Independently signed fixture evidence is stored against locked server state.
 // This signer is synthetic, NOT a deployed independent identity issuer.
 const issuer=generateKeyPairSync('ed25519');
 const stored=(await pool.query(`select actor,requester_session,device_id,pending_id,challenge_id,key_sha256,review_nonce,
  floor(extract(epoch from clock_timestamp())*1000)::float8 as now,expires_ms
  from master_device_enrollment_candidate.owner_approval_requests where id=$1`,[first.id])).rows[0];
 const unsigned={version:1,issuerKeyId:'synthetic-owner-issuer',decision:'approved',requestId:first.id,
  actor:stored.actor,requesterSession:stored.requester_session,deviceId:stored.device_id,pendingId:stored.pending_id,
  challengeId:stored.challenge_id,keySha256:stored.key_sha256,reviewNonce:stored.review_nonce,
  issuedMs:stored.now,expiresMs:Math.min(stored.expires_ms,stored.now+60000)};
 const signed=value=>({...value,signature:sign(null,ownerDecisionPayload(value),issuer.privateKey).toString('base64url')});
 const input={...lifecycle,receipt:signed(unsigned),pinnedIssuer:{purpose:'sko-master-independent-owner-decision-v1',keyId:unsigned.issuerKeyId,publicKeyJwk:issuer.publicKey.export({format:'jwk'})}};
 for(const patch of [{session:id(96)},{actor:id(97)},{receipt:signed({...unsigned,reviewNonce:'c'.repeat(64)})}])await assert.rejects(recordIndependentOwnerDecisionEvidence({...input,...patch}));
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.owner_decision_evidence')).rows[0].count),0);
 // A failed insert commits no receipt, even though the signature is valid.
 await pool.query(`create function master_device_enrollment_candidate.reject_evidence_fixture() returns trigger language plpgsql as $$ begin raise exception 'synthetic evidence failure';end $$;
  create trigger reject_evidence_fixture before insert on master_device_enrollment_candidate.owner_decision_evidence for each row execute function master_device_enrollment_candidate.reject_evidence_fixture()`);
 await assert.rejects(recordIndependentOwnerDecisionEvidence(input));
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.owner_decision_evidence')).rows[0].count),0);
 await pool.query('drop trigger reject_evidence_fixture on master_device_enrollment_candidate.owner_decision_evidence');
 // Mutating the caller's object during connection acquisition cannot replace the
 // signed decision that was synchronously snapshotted by the adapter.
 const mutable={...input.receipt};const racedPool={connect:async()=>{mutable.signature='x'.repeat(86);mutable.decision='denied';return input.pool.connect();}};
 const recorded=await recordIndependentOwnerDecisionEvidence({...input,pool:racedPool,receipt:mutable});
 assert.equal(recorded.status,'evidence_recorded');
 assert.deepEqual(await recordIndependentOwnerDecisionEvidence(input),recorded);
 if(concurrency){for(const result of await Promise.all([recordIndependentOwnerDecisionEvidence(input),recordIndependentOwnerDecisionEvidence(input)]))assert.deepEqual(result,recorded);}
 await assert.rejects(recordIndependentOwnerDecisionEvidence({...input,receipt:signed({...unsigned,decision:'denied'})}));
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.owner_decision_evidence')).rows[0].count),1);
 // A new connection can reconstruct the independently signed evidence without
 // the original request process or private signing key. This is historical
 // signature verification only, never authorization to activate a device.
 async function persistedEvidence(){
  const row=(await pool.query(`select attestation_sha256,attestation_payload,attestation_signature
   from master_device_enrollment_candidate.owner_decision_evidence where request_id=$1`,[first.id])).rows[0];
  const payload=Buffer.from(row.attestation_payload),signature=Buffer.from(row.attestation_signature);
  assert.deepEqual(payload,ownerDecisionPayload(unsigned));
  assert.deepEqual(signature,Buffer.from(input.receipt.signature,'base64url'));
  assert.equal(createHash('sha256').update(payload).update(signature).digest('hex'),row.attestation_sha256);
  assert.equal(verify(null,payload,issuer.publicKey,signature),true);
  const changed=Buffer.from(payload);changed[changed.length-2]^=1;
  assert.equal(verify(null,changed,issuer.publicKey,signature),false);
  return {payload:payload.toString('hex'),signature:signature.toString('hex'),digest:row.attestation_sha256};
 }
 const originalEvidence=await persistedEvidence();
 for(const [payload,signature] of [[Buffer.alloc(0),Buffer.alloc(64)],[Buffer.alloc(2049),Buffer.alloc(64)],[Buffer.alloc(1),Buffer.alloc(63)]]){
  await assert.rejects(pool.query(`insert into master_device_enrollment_candidate.owner_decision_evidence
   (request_id,issuer_key_id,decision,attestation_sha256,issued_ms,expires_ms,attestation_payload,attestation_signature)
   select request_id,issuer_key_id,decision,attestation_sha256,issued_ms,expires_ms,$1::bytea,$2::bytea
   from master_device_enrollment_candidate.owner_decision_evidence where request_id=$3`,[payload,signature,first.id]),e=>e.code==='23514');
 }
 for(const sql of [
  "update master_device_enrollment_candidate.owner_decision_evidence set attestation_payload=decode('00','hex')",
  "delete from master_device_enrollment_candidate.owner_decision_evidence",
  "truncate master_device_enrollment_candidate.owner_decision_evidence",
 ])await assert.rejects(pool.query(sql),e=>e.code==='55000');
 assert.deepEqual(await persistedEvidence(),originalEvidence,'rejected rewrites preserve the signed original');
 for(const role of ['anon','authenticated']){const c=await pool.connect();try{await c.query('begin');await c.query('set local role '+role);await assert.rejects(c.query('select * from master_device_enrollment_candidate.owner_decision_evidence'),e=>e.code==='42501');}finally{await c.query('rollback');c.release();}}
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
 await assert.rejects(recordIndependentOwnerDecisionEvidence(input),'recorded evidence cannot override cancellation');
 assert.deepEqual(await persistedEvidence(),originalEvidence,'expiry/withdrawal keep the historical original without authorizing its reuse');
 await pool.query('update private.master_devices set is_locked=false where id=$1',[args.deviceId]);
 // Even restoring a synthetic proof's time cannot resurrect a cancelled request.
 await pool.query(`update master_device_enrollment_candidate.key_possession_challenges
  set created_ms=floor(extract(epoch from clock_timestamp())*1000),expires_ms=floor(extract(epoch from clock_timestamp())*1000)+60000 where id=$1`,[args.challengeId]);
 await pool.query(`update master_device_enrollment_candidate.owner_approval_requests set expires_ms=
  (select expires_ms from master_device_enrollment_candidate.key_possession_challenges where id=$1) where id=$2`,[args.challengeId,first.id]);
 await assert.rejects(requestIndependentOwnerApproval(request));
 assert.equal((await pool.query('select status from master_device_enrollment_candidate.pending_key_migrations where id=$1',[pendingId])).rows[0].status,'pending');
 assert.equal((await pool.query('select count(*) as count from private.master_devices')).rows[0].count,before);
 console.log('Owner review request: exact proof, retry/status/cancel, signed-byte retention/reverification, bounded evidence, update/delete/truncate refusal, foreign/locked/expired rejection, client ACL and no key activation passed. Synthetic auth only.');
}
