// Internal review-only signed EVIDENCE ingestion, not independent owner approval.
// Trust pin and request-scoped pool must come from server configuration. No route,
// signer, active key or master_devices mutation exists here. Cancellation remains
// terminal and may follow recording: future activation MUST recheck it atomically.
import {verifyOwnerDecisionAttestation} from './owner-decision-attestation.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function scalarSnapshot(value){
 if(!value||typeof value!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(value)))throw Error('plain scalar evidence required');
 const result={};for(const k of Reflect.ownKeys(value)){
  const d=Object.getOwnPropertyDescriptor(value,k);
  if(typeof k!=='string'||!d?.enumerable||!Object.hasOwn(d,'value')||!['string','number','boolean'].includes(typeof d.value))throw Error('plain scalar evidence required');
  Object.defineProperty(result,k,{value:d.value,enumerable:true});
 }return Object.freeze(result);
}
export async function recordIndependentOwnerDecisionEvidence({pool,actor,session,requestId,receipt,pinnedIssuer}){
 // Snapshot untrusted input BEFORE the first asynchronous acquisition. Do not let
 // a later caller mutation choose the request, signer, decision or signature.
 const signed=scalarSnapshot(receipt);
 const pin=Object.freeze({purpose:pinnedIssuer?.purpose,keyId:pinnedIssuer?.keyId,publicKeyJwk:scalarSnapshot(pinnedIssuer?.publicKeyJwk)});
 if(!pool||typeof pool.connect!=='function'||![actor,session,requestId].every(x=>typeof x==='string'&&uuid.test(x)))throw Error('invalid evidence scope');
 const c=await pool.connect();
 try{
  await c.query('begin');await c.query("set local lock_timeout='1s'");await c.query("set local statement_timeout='5s'");
  const identity=await c.query('select auth.uid() as actor,private.require_reauthentication_session() as session,public.is_current_user_master_admin() as master');
  if(identity.rows.length!==1||identity.rows[0].actor!==actor||identity.rows[0].session!==session||identity.rows[0].master!==true)throw Error('eligible owner session required');
  const initial=await c.query(`select device_id,challenge_id,pending_id,key_sha256 from master_device_enrollment_candidate.owner_approval_requests
   where id=$1 and actor=$2 and requester_session=$3`,[requestId,actor,session]);
  if(initial.rows.length!==1)throw Error('original owner request unavailable');const r=initial.rows[0];
  // Same lock order as issuance and cancellation. Device lock/revocation and
  // cancellation cannot race past this transaction's observation.
  const device=await c.query(`select id from private.master_devices where id=$1 and master_user_id=$2 and not is_locked and revoked_at is null for share`,[r.device_id,actor]);
  if(device.rows.length!==1)throw Error('eligible owned device required');
  const source=await c.query(`select ch.expires_ms from master_device_enrollment_candidate.key_possession_challenges ch
   join master_device_enrollment_candidate.pending_key_migrations p on p.id=$2 and p.actor=ch.actor and p.device_id=ch.device_id and p.key_sha256=ch.key_sha256
   where ch.id=$1 and ch.actor=auth.uid() and ch.actor=$3 and ch.session_id=private.require_reauthentication_session() and ch.session_id=$4
    and ch.device_id=$5 and ch.key_sha256=$6 and ch.consumed_at is not null and p.status='pending' for update of ch,p`,[r.challenge_id,r.pending_id,actor,session,r.device_id,r.key_sha256]);
  if(source.rows.length!==1)throw Error('original pending key required');
  const locked=await c.query(`select id,actor,requester_session as "requesterSession",device_id as "deviceId",pending_id as "pendingId",
   challenge_id as "challengeId",key_sha256 as "keySha256",review_nonce as "reviewNonce",status,
   floor(extract(epoch from created_at)*1000)::float8 as "createdMs",expires_ms as "expiresMs"
   from master_device_enrollment_candidate.owner_approval_requests where id=$1 and actor=auth.uid() and actor=$2
    and requester_session=private.require_reauthentication_session() and requester_session=$3 and device_id=$4
    and challenge_id=$5 and pending_id=$6 and key_sha256=$7 and expires_ms=$8 and public.is_current_user_master_admin() for update`,
   [requestId,actor,session,r.device_id,r.challenge_id,r.pending_id,r.key_sha256,source.rows[0].expires_ms]);
  if(locked.rows.length!==1)throw Error('owner request changed');
  const state=await c.query(`select floor(extract(epoch from clock_timestamp())*1000)::float8 as now,
   exists(select 1 from master_device_enrollment_candidate.owner_approval_request_cancellations where request_id=$1) as cancelled`,[requestId]);
  if(state.rows.length!==1)throw Error('owner evidence state unavailable');
  const evidence=verifyOwnerDecisionAttestation({receipt:signed,request:{...locked.rows[0],cancelled:state.rows[0].cancelled},databaseNowMs:state.rows[0].now,pinnedIssuer:pin});
  if(!evidence)throw Error('signed owner evidence refused');
  const saved=await c.query(`insert into master_device_enrollment_candidate.owner_decision_evidence
   (request_id,issuer_key_id,decision,attestation_sha256,issued_ms,expires_ms)
   select $1,$2,$3,$4,$5::float8,$6::float8 where $6::float8>floor(extract(epoch from clock_timestamp())*1000)
    and auth.uid()=$7 and private.require_reauthentication_session()=$8 and public.is_current_user_master_admin()
   on conflict(request_id) do nothing returning request_id`,[requestId,evidence.issuerKeyId,evidence.decision,evidence.attestationSha256,evidence.issuedMs,evidence.expiresMs,actor,session]);
  // An unknown response is reconciled only to the same immutable receipt; another
  // signed decision cannot silently replace an earlier decision.
  const original=await c.query(`select attestation_sha256 from master_device_enrollment_candidate.owner_decision_evidence
   where request_id=$1 and issuer_key_id=$2 and decision=$3 and attestation_sha256=$4 and issued_ms=$5 and expires_ms=$6`,
   [requestId,evidence.issuerKeyId,evidence.decision,evidence.attestationSha256,evidence.issuedMs,evidence.expiresMs]);
  if(original.rows.length!==1)throw Error('original evidence unavailable');
  await c.query('commit');return Object.freeze({requestId,status:'evidence_recorded',attestationSha256:evidence.attestationSha256});
 }catch(error){try{await c.query('rollback');}catch{}throw error;}finally{c.release();}
}
