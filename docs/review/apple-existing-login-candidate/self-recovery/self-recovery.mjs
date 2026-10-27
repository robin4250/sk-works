// Review only: no route, grants, service credentials or deployed operator port.
// Recovery MUST be supplied by a trusted adapter that enforces request ownership
// and executes the existing audited root reconciliation in its own transaction.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const unavailable=()=>{throw Error('apple_recovery_unavailable');};
export async function requestSelfRecovery(input,ports){
 if(ports.enabled!==true||ports.trustedOperatorReviewed!==true||typeof input?.exactBearer!=='string'||!input.exactBearer||input.exactBearer.length>16384||typeof input.password!=='string'||!input.password||input.password.length>1024||!uuid.test(input.requestId??''))unavailable();
 const start=ports.now();if(!Number.isSafeInteger(start))unavailable();
 const expected=await ports.loadExactContext(input.exactBearer);
 if(!expected||!uuid.test(expected.actor_id??'')||!uuid.test(expected.session_id??'')||expected.account_allowed!==true||expected.primary_password_configured!==true)unavailable();
 // The adapter must not reveal another account's request, or accept identity,
 // actor, session, status, outcome, or command values from app input.
 const request=await ports.readOwnRequest({request_id:input.requestId,actor_id:expected.actor_id,session_id:expected.session_id});
 if(!request||request.request_id!==input.requestId||request.actor_id!==expected.actor_id||!['held','completed','cancelled'].includes(request.status))unavailable();
 const proof=await ports.verifyPrimaryPassword({exactBearer:input.exactBearer,password:input.password,expected});
 const now=ports.now();
 if(!Number.isSafeInteger(now)||now<start||now-start>120||!proof||proof.source!=='auth_primary_password'||proof.actor_id!==expected.actor_id||proof.original_session_id!==expected.session_id||proof.temporary_session_closed!==true||!Number.isSafeInteger(proof.verified_at)||proof.verified_at<start||proof.verified_at>now)unavailable();
 // Use the existing root routine, never unlink an identity or create a permit.
 // Its transaction rechecks current session, ownership, context, identity and
 // all rollout gates; any mismatch remains held for independent review.
 const command=await ports.getOrCreateRecoveryCommand({request_id:input.requestId,actor_id:expected.actor_id,session_id:expected.session_id});
 if(!command||!uuid.test(command.command_id??'')||command.request_id!==input.requestId||command.actor_id!==expected.actor_id||command.session_id!==expected.session_id)unavailable();
 const outcome=await ports.reconcileOwnHeld({command_id:command.command_id,request_id:input.requestId,actor_id:expected.actor_id,session_id:expected.session_id});
 if(!outcome||outcome.request_id!==input.requestId||outcome.reconciled!==true||!['completed','cancelled'].includes(outcome.status))return Object.freeze({status:'review_required'});
 return Object.freeze({status:outcome.status==='completed'?'linked':'restart_with_new_apple_credential'});
}
