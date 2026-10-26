// OFF enrollment core. Trusted SQL/Auth ports are required; no public endpoint,
// proof store, credential discovery, provider change or session adoption.
import {verifyAppleCredential,sha256Hex} from './existing_apple_login.mjs';
export class AppleEnrollmentDenied extends Error{constructor(){super('apple_native_enrollment_unavailable');}}
const deny=()=>{throw new AppleEnrollmentDenied();};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sub=/^[A-Za-z0-9._-]{1,255}$/;
function context(value){
 if(!value||!uuid.test(value.actor_id??'')||!uuid.test(value.session_id??'')||value.account_allowed!==true||value.primary_password_configured!==true||
 !/^[a-f0-9]{64}$/.test(value.primary_credential_version??'')||
 !Array.isArray(value.memberships)||!value.memberships.length||value.memberships.length>32||
 value.memberships.some(m=>!m||!uuid.test(m.company_id??'')||typeof m.role!=='string'||!/^[a-z_]{1,32}$/.test(m.role))||
 new Set(value.memberships.map(m=>m.company_id)).size!==value.memberships.length||
 !Array.isArray(value.google_identities)||!value.google_identities.length||value.google_identities.length>8||
 value.google_identities.some(i=>!i||!uuid.test(i.id??'')||!sub.test(i.provider_id??''))||
 !Array.isArray(value.apple_subjects)||value.apple_subjects.some(s=>!sub.test(s)))deny();
 return Object.freeze({actor_id:value.actor_id,session_id:value.session_id,
  primary_credential_version:value.primary_credential_version,
  memberships:Object.freeze(value.memberships.map(m=>Object.freeze({company_id:m.company_id,role:m.role})).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)))),
  google_identities:Object.freeze(value.google_identities.map(i=>Object.freeze({id:i.id,provider_id:i.provider_id})).sort((a,b)=>a.id.localeCompare(b.id))),
  apple_subjects:Object.freeze([...value.apple_subjects].sort())});
}
function same(a,b){return JSON.stringify({...a,apple_subjects:[]})===JSON.stringify({...b,apple_subjects:[]});}
function originalAppleOnly(before,after,subject){
 const expected=[...new Set([...before.apple_subjects,subject])].sort();
 return JSON.stringify(expected)===JSON.stringify(after.apple_subjects);
}
export async function enrollNativeApple(input,ports){
 if(ports.enabled!==true||ports.nativeOnlyReviewed!==true||typeof input?.exactBearer!=='string'||!input.exactBearer||input.exactBearer.length>16384||
 typeof input.password!=='string'||!input.password||input.password.length>1024)deny();
 const started=ports.now();if(!Number.isSafeInteger(started))deny();
 const before=context(await ports.loadExactContext(input.exactBearer));
 const credential=await verifyAppleCredential({idToken:input.idToken,rawNonce:input.rawNonce,audiences:ports.audiences,now:started,resolveKey:ports.resolveKey});
 // Already-linked users follow their existing registered-login/review path;
 // this initial-enrollment core never replaces or silently re-enrolls them.
 if(before.apple_subjects.length)deny();
 const evidence=await ports.verifyPrimaryPassword({exactBearer:input.exactBearer,password:input.password,expected:before});
 const checkedAt=ports.now();
 if(!evidence||evidence.source!=='auth_primary_password'||evidence.actor_id!==before.actor_id||evidence.original_session_id!==before.session_id||
 evidence.temporary_session_closed!==true||!Number.isSafeInteger(evidence.verified_at)||evidence.verified_at<started||evidence.verified_at>checkedAt||checkedAt-started>120)deny();
 const afterPassword=context(await ports.loadExactContext(input.exactBearer));
 if(!same(before,afterPassword)||JSON.stringify(before.apple_subjects)!==JSON.stringify(afterPassword.apple_subjects))deny();
 const snapshotHash=await sha256Hex(JSON.stringify(before));
 // The adapter must atomically recheck live SID/deletion/account, exact Google
 // and company snapshot, native-only rollout and unconsumed token hash. It
 // reserves a verified subject for THIS UID, never by email or client-selected UID.
 const reservation=await ports.reserveSubject({actor_id:before.actor_id,session_id:before.session_id,
  subject:credential.subject,token_sha256:credential.tokenHash,snapshot_sha256:snapshotHash,verified_at:evidence.verified_at});
 if(!reservation||!uuid.test(reservation.request_id??'')||reservation.actor_id!==before.actor_id||reservation.session_id!==before.session_id||
 reservation.subject!==credential.subject||reservation.token_sha256!==credential.tokenHash||reservation.status!=='reserved')deny();
 let temporaryAccess=null;let accepted=false;
 try{
  const result=await ports.linkNativeIdentity({exactBearer:input.exactBearer,idToken:input.idToken,rawNonce:input.rawNonce});
  if(!result||typeof result.access_token!=='string'||!result.access_token||result.token_type!=='bearer')deny();
  const verified=await ports.authenticateIssuedSession(result.access_token);
  if(!verified||verified.actor_id!==before.actor_id||!uuid.test(verified.session_id??'')||verified.session_id===before.session_id||
    !Array.isArray(verified.apple_subjects)||!verified.apple_subjects.includes(credential.subject))deny();
  temporaryAccess=result.access_token;
  // Native linking issues a new session. Keep the original Google session and
  // Face ID state intact; never return or adopt that temporary new credential.
  if(await ports.revokeLocal(temporaryAccess)!==true)deny();temporaryAccess=null;
  const after=context(await ports.loadExactContext(input.exactBearer));
  if(!same(before,after)||!originalAppleOnly(before,after,credential.subject))deny();
  const completion=await ports.completeSubject({request_id:reservation.request_id,actor_id:before.actor_id,session_id:before.session_id,
   subject:credential.subject,token_sha256:credential.tokenHash,before_snapshot_sha256:snapshotHash});
  if(completion?.linked!==true||completion.request_id!==reservation.request_id||completion.actor_id!==before.actor_id)deny();
  accepted=true;
  return Object.freeze({linked:true,user_id:before.actor_id});
 }finally{
  if(temporaryAccess){try{await ports.revokeLocal(temporaryAccess);}catch{/* no credential output */}}
  if(!accepted){
   // Unknown Auth results may already have committed a link. Never unlink or
   // delete an identity to pretend rollback; retain the reservation for review.
   try{await ports.holdSubject(reservation.request_id);}catch{/* remain unavailable */}
  }
 }
}
