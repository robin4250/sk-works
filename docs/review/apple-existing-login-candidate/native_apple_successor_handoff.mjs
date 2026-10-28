// Internal review-only composition. No public endpoint, credential persistence,
// client session adoption or PW successor reservation is implemented here.
import {verifyAppleCredential} from './existing_apple_login.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const denied=()=>Error('apple_successor_handoff_unavailable');
export async function handoffNativeAppleSuccessor(input,ports){
 if(ports.enabled!==true||ports.successorReviewed!==true||typeof ports.deliverVerifiedSuccessor!=='function'||
    !uuid.test(input?.requestId??'')||typeof input.exactBearer!=='string'||!input.exactBearer||input.exactBearer.length>16384)throw denied();
 // This trusted port authenticates the bearer, atomically claims one external-link attempt for its own reserved
 // request and returns the original actor/SID and immutable snapshot evidence.
 const r=await ports.claimReservedForBearer({request_id:input.requestId,exactBearer:input.exactBearer});
 if(!r||r.status!=='reserved'||r.request_id!==input.requestId||!uuid.test(r.actor_id??'')||!uuid.test(r.session_id??'')||
    !/^[a-f0-9]{64}$/.test(r.snapshot_sha256??''))throw denied();
 const credential=await verifyAppleCredential({idToken:input.idToken,rawNonce:input.rawNonce,audiences:ports.audiences,now:ports.now(),resolveKey:ports.resolveKey});
 if(credential.subject!==r.subject||credential.tokenHash!==r.token_sha256)throw denied();
 let completed=false;
 try{
  // The Auth port itself obtains and independently verifies this result; a
  // caller cannot substitute an unrelated refresh token beside a valid JWT.
  const result=await ports.linkNativeIdentitySuccessor({exactBearer:input.exactBearer,idToken:input.idToken,rawNonce:input.rawNonce});
  if(!result||result.token_type!=='bearer'||typeof result.refresh_token!=='string'||!result.refresh_token||result.refresh_token.length>16384||
     typeof result.access_token!=='string'||!result.access_token||result.access_token.length>16384)throw denied();
  const issued=await ports.authenticateIssuedSession(result.access_token);
  if(issued?.actor_id!==r.actor_id||!uuid.test(issued.session_id??'')||issued.session_id===r.session_id||
     !Array.isArray(issued.apple_subjects)||issued.apple_subjects.length!==1||issued.apple_subjects[0]!==r.subject)throw denied();
  // Adapter invokes the existing internal SQL completion in a trusted DB role.
  // SQL rechecks UID, company/profile/Google snapshot, subject, live new SID,
  // freshness, token hash and single use atomically. It has no client grant.
  const receipt=await ports.completeWithSuccessor({request_id:r.request_id,actor_id:r.actor_id,original_session_id:r.session_id,
   successor_session_id:issued.session_id,subject:r.subject,token_sha256:r.token_sha256,snapshot_sha256:r.snapshot_sha256});
  if(receipt?.linked!==true||receipt.request_id!==r.request_id||receipt.actor_id!==r.actor_id||receipt.session_id!==issued.session_id)throw denied();
  completed=true;
  // No credentials in the normal result, errors, audit, or DB. A reviewed,
  // request-bound HTTPS sink must provide explicit acknowledgement once only.
  // Lost delivery is an unknown outcome, never grounds to revoke/unlink/redo.
  if(await ports.deliverVerifiedSuccessor(Object.freeze({request_id:r.request_id,user_id:r.actor_id,session_id:issued.session_id,
    access_token:result.access_token,refresh_token:result.refresh_token,token_type:'bearer'}))!==true)throw denied();
  return Object.freeze({linked:true,user_id:r.actor_id,session_id:issued.session_id});
 }catch{
  if(!completed){try{await ports.holdSubject(r.request_id);}catch{/* retain unknown outcome */}}
  throw denied();
 }
}
