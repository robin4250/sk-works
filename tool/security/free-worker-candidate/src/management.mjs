import {uuid} from './protocol.mjs';
import {readPolicy,transitionPolicyWithinTransaction} from './broker.mjs';
import {securityState,exact,publicJwk,verified,prepareAudit,appendAuditWithinTransaction,verifyAuditChain} from './security-audit.mjs';
const actions=new Set(['enable','disable','rotate','quarantine','release']);
const reasons=new Set(['operator_review','false_positive','overload','recovery_lost_key']);
const fields='action,company_id,deployment_id,expected_policy_revision,expected_trust_revision,expires_at,issued_at,key_id,key_version,kind,nonce,reason,subject,v';
function payloadCopy(p){return {v:1,kind:p.kind,key_id:p.key_id,key_version:p.key_version,deployment_id:p.deployment_id,subject:p.subject,company_id:p.company_id,action:p.action,reason:p.reason,expected_policy_revision:p.expected_policy_revision,expected_trust_revision:p.expected_trust_revision,nonce:p.nonce,issued_at:p.issued_at,expires_at:p.expires_at,...(p.kind==='recovery'?{new_manager:{key_id:p.new_manager.key_id,version:p.new_manager.version,jwk:publicJwk(p.new_manager.jwk)}}:{})};}
export async function applyManagedCommand(storage,{envelope,now,auditKey}){
 // No public Worker route or RPC method calls this function. A separately verified issuer is required.
 if(!envelope||new TextEncoder().encode(JSON.stringify(envelope)).length>8192)throw Error('Management envelope bound');
 const state=securityState(storage),policy=readPolicy(storage),p=envelope?.payload;
 if(!state||!exact(envelope,'payload,signature')||!p||!['management','recovery'].includes(p.kind)||!exact(p,p.kind==='recovery'?fields.split(',').concat('new_manager').sort().join(','):fields)||p.v!==1||p.deployment_id!==state.deployment_id||p.subject!==state.owner_id||p.company_id!==state.company_id||!reasons.has(p.reason)||!Number.isSafeInteger(now)||now<state.clock||!Number.isSafeInteger(p.issued_at)||p.issued_at>now+30000||p.issued_at<now-300000||!Number.isSafeInteger(p.expires_at)||p.expires_at<=p.issued_at||p.expires_at<=now||p.expires_at-p.issued_at>300000||!Number.isSafeInteger(p.expected_policy_revision)||p.expected_policy_revision!==policy.revision||!Number.isSafeInteger(p.expected_trust_revision)||p.expected_trust_revision!==state.trust_revision||typeof p.nonce!=='string'||!uuid.test(p.nonce))throw Error('Management rejected');
 let publicKey;
 if(p.kind==='management'){
  if(!actions.has(p.action)||p.key_id!==state.manager_key_id||p.key_version!==state.manager_version||p.reason==='recovery_lost_key')throw Error('Management key/scope rejected');
  publicKey=JSON.parse(state.manager_jwk);
 }else{
  if(p.action!=='recover_manager'||p.reason!=='recovery_lost_key'||p.key_id!==state.recovery_key_id||p.key_version!==1||!exact(p.new_manager,'jwk,key_id,version')||typeof p.new_manager.key_id!=='string'||!/^[a-zA-Z0-9_-]{1,64}$/.test(p.new_manager.key_id)||p.new_manager.key_id===state.manager_key_id||!Number.isInteger(p.new_manager.version)||p.new_manager.version!==state.manager_version+1)throw Error('Recovery scope rejected');
  const next=publicJwk(p.new_manager.jwk);if([JSON.parse(state.manager_jwk).x,JSON.parse(state.recovery_jwk).x,JSON.parse(state.audit_jwk).x,JSON.parse(state.anchor_jwk).x].includes(next.x))throw Error('Recovery key independence rejected');
  publicKey=JSON.parse(state.recovery_jwk);
 }
 const payload=payloadCopy(p),body=JSON.stringify(payload);
 if(!await verified(publicKey,'sko-decoy-management-v1',body,envelope.signature))throw Error('Management signature rejected');
 await verifyAuditChain(storage);
 const after={revision:policy.revision+1,epoch:policy.epoch+1,generation:payload.action==='rotate'?policy.generation+1:policy.generation,enabled:payload.kind==='recovery'||payload.action==='disable'?0:payload.action==='enable'?1:policy.enabled,quarantined:payload.action==='quarantine'?1:payload.action==='release'?0:policy.quarantined};
 const row=await prepareAudit(state,{kind:payload.kind,action:payload.action,reason:payload.reason,actorId:payload.subject,at:now,before:{revision:policy.revision,epoch:policy.epoch,manager_version:state.manager_version},after:{...after,manager_version:payload.kind==='recovery'?payload.new_manager.version:state.manager_version}},auditKey);
 return storage.transactionSync(()=>{
  const current=securityState(storage),fresh=readPolicy(storage);
  if(current.trust_revision!==state.trust_revision||current.manager_key_id!==state.manager_key_id||current.manager_version!==state.manager_version||fresh.revision!==policy.revision||fresh.epoch!==policy.epoch||now<current.clock)throw Error('Management CAS rejected');
  if(storage.sql.exec('SELECT nonce FROM management_nonces WHERE nonce=?',payload.nonce).toArray().length)throw Error('Management replay rejected');
  if(storage.sql.exec('SELECT count(*) AS n FROM management_nonces').toArray()[0].n>=1000)throw Error('Management nonce capacity');
  storage.sql.exec('INSERT INTO management_nonces VALUES(?,?)',payload.nonce,payload.expires_at);
  // append before trust revision changes so a failed policy/audit write rolls back the whole command.
  appendAuditWithinTransaction(storage,state,row);
  transitionPolicyWithinTransaction(storage,{expectedRevision:policy.revision,action:payload.kind==='recovery'?'disable':payload.action,reason:payload.kind==='recovery'?'operator_review':payload.reason,now});
  if(payload.kind==='recovery')storage.sql.exec('UPDATE security_state SET manager_key_id=?,manager_version=?,manager_jwk=?,trust_revision=trust_revision+1 WHERE id=1',payload.new_manager.key_id,payload.new_manager.version,JSON.stringify(payload.new_manager.jwk));
  return {policy:readPolicy(storage),trust_revision:securityState(storage).trust_revision,audit_sequence:row.sequence};
 });
}
