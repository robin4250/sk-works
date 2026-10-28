// Internal, request-scoped review candidate only. No public HTTP endpoint.
// Accepts an already reserved request; PW-successor reservation is NOT wired.
import {createNativeAppleAuthPorts} from './native_apple_auth_port.mjs';
import {createSuccessorDBPorts} from './native_apple_successor_db_port.mjs';
import {handoffNativeAppleSuccessor} from './native_apple_successor_handoff.mjs';
import {verifyAppleCredential} from './existing_apple_login.mjs';
const denied=()=>Error('apple_successor_handoff_unavailable');
export function createNativeAppleSuccessorBroker(config={},dependencies={}){
 let attempted=false;
 return async input=>{
  if(attempted)throw denied();attempted=true;
  if(config.enabled!==true||config.nativeOnlyReviewed!==true||config.successorReviewed!==true||
     config.databaseReviewed!==true||config.deliveryReviewed!==true||
     !Array.isArray(config.audiences)||config.audiences.length!==1||config.audiences[0]!=='com.skworks.skWorks'||
     typeof dependencies.resolveKey!=='function'||typeof dependencies.deliverVerifiedSuccessor!=='function')throw denied();
  try{
   const now=dependencies.now??(()=>Math.floor(Date.now()/1000));
   const auth=createNativeAppleAuthPorts({enabled:true,nativeOnlyReviewed:true,successorReviewed:true,
    baseUrl:config.baseUrl,publicKey:config.publicKey,fetcher:dependencies.fetcher,now,timeoutMs:config.authTimeoutMs??10000});
   // Independently verifies the original bearer at the HTTP Auth boundary.
   await auth.bindOriginal(input?.exactBearer);
   const db=createSuccessorDBPorts({enabled:true,reviewed:true,pool:dependencies.pool,
    authenticateExactBearer:auth.authenticateExactBearer,now:()=>now()*1000});
   return await handoffNativeAppleSuccessor(input,{
    enabled:true,successorReviewed:true,audiences:[...config.audiences],now,resolveKey:dependencies.resolveKey,
    claimReservedForBearer:db.claimReservedForBearer,completeWithSuccessor:db.completeWithSuccessor,
    holdSubject:db.holdSubject,linkNativeIdentitySuccessor:auth.linkNativeIdentitySuccessor,
    authenticateIssuedSession:auth.authenticateIssuedSession,
    deliverVerifiedSuccessor:dependencies.deliverVerifiedSuccessor,
   });
  }catch{throw denied();}
 };
}

// Internal OFF composition. No public endpoint, application session adoption or
// durable credential delivery. A failed password-successor flow may require the
// owner to sign in again; never restore/revoke sessions to pretend rollback.
export function createNativeApplePasswordSuccessorBroker(config={},dependencies={}){
 let attempted=false;
 return async input=>{
  if(attempted)throw denied();attempted=true;
  if(config.enabled!==true||config.nativeOnlyReviewed!==true||config.successorReviewed!==true||
    config.passwordSuccessorReviewed!==true||config.databaseReviewed!==true||config.deliveryReviewed!==true||
    typeof input?.password!=='string'||!input.password||input.password.length>1024||
    !Array.isArray(config.audiences)||config.audiences.length!==1||config.audiences[0]!=='com.skworks.skWorks'||
    typeof dependencies.resolveKey!=='function'||typeof dependencies.deliverVerifiedSuccessor!=='function')throw denied();
  try{
   const now=dependencies.now??(()=>Math.floor(Date.now()/1000));
   const started=now();
   const credential=await verifyAppleCredential({idToken:input?.idToken,rawNonce:input?.rawNonce,audiences:config.audiences,now:started,resolveKey:dependencies.resolveKey});
   const fresh=()=>{const at=now();if(!Number.isSafeInteger(at)||at<started||at-started>120||at>=credential.expiresAt||credential.issuedAt<at-300)throw denied();};
   const auth=createNativeAppleAuthPorts({enabled:true,nativeOnlyReviewed:true,successorReviewed:true,passwordSuccessorReviewed:true,
    baseUrl:config.baseUrl,publicKey:config.publicKey,fetcher:dependencies.fetcher,now,timeoutMs:config.authTimeoutMs??10000});
   await auth.bindOriginal(input?.exactBearer);
   const db=createSuccessorDBPorts({enabled:true,reviewed:true,passwordSuccessorReviewed:true,pool:dependencies.pool,
    authenticateExactBearer:auth.authenticateExactBearer,now:()=>now()*1000});
   // Commit the original snapshot before a password login can obsolete its SID.
   const intent=await db.beginPasswordSuccessorForBearer({exactBearer:input.exactBearer,subject:credential.subject,token_sha256:credential.tokenHash});
   fresh();
   const password=await auth.authenticatePrimaryPasswordSuccessor({exactBearer:input.exactBearer,password:input.password});
   fresh();
   const reservation=await db.reservePasswordSuccessorForBearer({intent_id:intent.intent_id,exactBearer:password.access_token});
   if(reservation.subject!==credential.subject||reservation.token_sha256!==credential.tokenHash)throw denied();
   // Existing broker independently revalidates the Apple token and new bearer,
   // commits its durable link claim, then completes and delivers once.
   return await createNativeAppleSuccessorBroker(config,dependencies)({requestId:reservation.request_id,
    exactBearer:password.access_token,idToken:input.idToken,rawNonce:input.rawNonce});
  }catch{throw denied();}
 };
}
