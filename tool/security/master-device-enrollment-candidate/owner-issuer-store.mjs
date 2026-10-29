// Internal, review-only control-plane persistence. No trust bootstrap, external
// checkpoint authentication/freshness, public route or device activation.
import {captureOwnerIssuerCheckpoint,captureOwnerIssuerProposal,validateOwnerIssuerCheckpoint,verifyOwnerIssuerContinuity} from './owner-issuer-continuity.mjs';

async function lockedPin(client,checkpoint,mode){
 const rows=await client.query(`select epoch,pin from master_device_enrollment_candidate.owner_issuer_heads
  where authority_id=$1 for ${mode==='update'?'update':'share'}`,[checkpoint.authorityId]);
 if(rows.rows.length!==1)throw Error('independently installed issuer unavailable');
 const pin=validateOwnerIssuerCheckpoint({enabled:true,trusted:rows.rows[0].pin,authorityCheckpoint:checkpoint});
 if(!pin||rows.rows[0].epoch!==pin.epoch)throw Error('issuer checkpoint differs');
 return pin;
}
// Call only inside the existing evidence transaction. This shared row lock is
// acquired before device/challenge/request locks, so rotation cannot swap the
// current issuer between receipt verification and the receipt commit.
export async function ownerIssuerPinWithinTransaction(client,authorityCheckpoint){
 const checkpoint=captureOwnerIssuerCheckpoint(authorityCheckpoint);
 const pin=await lockedPin(client,checkpoint,'share');
 return Object.freeze({purpose:pin.purpose,keyId:pin.keyId,publicKeyJwk:pin.publicKeyJwk});
}

export async function commitOwnerIssuerTransition({enabled=false,pool,authorityCheckpoint,proposal}){
 if(enabled!==true)throw Error('issuer persistence is disabled');
 // Capture all untrusted configuration bytes before asynchronous acquisition.
 const checkpoint=captureOwnerIssuerCheckpoint(authorityCheckpoint),signed=captureOwnerIssuerProposal(proposal);
 if(!pool||typeof pool.connect!=='function')throw Error('trusted control-plane pool required');
 const client=await pool.connect();
 try{
  await client.query('begin');await client.query("set local lock_timeout='2s'");await client.query("set local statement_timeout='5s'");
  const current=await lockedPin(client,checkpoint,'update');
  const now=await client.query('select floor(extract(epoch from clock_timestamp())*1000)::float8 as now');
  const verified=verifyOwnerIssuerContinuity({enabled:true,trusted:current,authorityCheckpoint:checkpoint,proposal:signed,databaseNowMs:now.rows[0]?.now});
  if(!verified)throw Error('issuer continuity refused');
  const e=verified.evidence;
  await client.query(`insert into master_device_enrollment_candidate.owner_issuer_transitions
   (authority_id,from_epoch,to_epoch,previous_sha256,head_sha256,authority_checkpoint,old_pin,new_pin,signed_payload,old_signature,new_signature)
   values($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb,$8::jsonb,$9::bytea,$10::bytea,$11::bytea)`,
   [checkpoint.authorityId,current.epoch,verified.next.epoch,current.headSha256,e.headSha256,JSON.stringify(checkpoint),JSON.stringify(current),JSON.stringify(verified.next),
    Buffer.from(e.payloadBase64,'base64'),Buffer.from(e.oldSignature,'base64url'),Buffer.from(e.newSignature,'base64url')]);
  const saved=await client.query(`update master_device_enrollment_candidate.owner_issuer_heads
   set epoch=$5,pin=$4::jsonb,updated_at=clock_timestamp()
   where authority_id=$1 and epoch=$2 and pin=$3::jsonb and $6::float8>floor(extract(epoch from clock_timestamp())*1000)
   returning authority_id`,[checkpoint.authorityId,current.epoch,JSON.stringify(current),JSON.stringify(verified.next),verified.next.epoch,signed.expiresMs]);
  if(saved.rows.length!==1)throw Error('issuer compare-and-swap refused');
  await client.query('commit');
  return Object.freeze({authorityId:checkpoint.authorityId,epoch:verified.next.epoch,headSha256:e.headSha256,status:'transition_committed'});
 }catch(error){try{await client.query('rollback');}catch{}throw error;}finally{client.release();}
}
