// Trusted server core. No HTTP endpoint, credentials or key discovery.
// The database port binds claim() to the authenticated caller's original JWT;
// complete()/fail() are server-only. Never accept a caller-supplied claim object.
import {exact,publicJwk,hash,signBytes,verified} from '../src/security-audit.mjs';
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(x);
const fields='action,company_id,deployment_id,expected_policy_revision,expected_trust_revision,expires_at,issued_at,key_id,key_version,kind,nonce,reason,subject,v';
const canonical=p=>({v:1,kind:p.kind,key_id:p.key_id,key_version:p.key_version,deployment_id:p.deployment_id,subject:p.subject,company_id:p.company_id,action:p.action,reason:p.reason,expected_policy_revision:p.expected_policy_revision,expected_trust_revision:p.expected_trust_revision,nonce:p.nonce,issued_at:p.issued_at,expires_at:p.expires_at});
function validPayload(p,now){return exact(p,fields)&&p.v===1&&p.kind==='management'&&
 ['enable','disable','rotate','quarantine','release'].includes(p.action)&&['operator_review','false_positive','overload'].includes(p.reason)&&
 [p.key_id,p.deployment_id].every(x=>typeof x==='string'&&/^[a-zA-Z0-9_-]{1,64}$/.test(x))&&
 [p.subject,p.company_id,p.nonce].every(uuid)&&[p.key_version,p.expected_policy_revision,p.expected_trust_revision].every(x=>Number.isSafeInteger(x)&&x>0)&&
 Number.isSafeInteger(p.issued_at)&&Number.isSafeInteger(p.expires_at)&&p.issued_at<=now+30000&&p.issued_at>=now-60000&&p.expires_at>now&&p.expires_at>p.issued_at&&p.expires_at-p.issued_at<=60000;}
export function createManagementIssuer({enabled=false,database,resolveSigningKey,now=()=>Date.now()}={}){
 if(typeof enabled!=='boolean')throw Error('Issuer configuration rejected');
 if(enabled&&(!database||!['claim','complete','fail'].every(x=>typeof database[x]==='function')||typeof resolveSigningKey!=='function'))throw Error('Issuer ports unavailable');
 return Object.freeze({async issue({proof}={}){
  if(!enabled)return {state:'disabled'};
  if(typeof proof!=='string'||!/^[a-f0-9]{64}$/.test(proof))throw Error('Dedicated management proof required');
  const c=await database.claim(proof);
  if(!c||typeof c!=='object'||!uuid(c.command_id))throw Error('Issuer claim unavailable');
  if(['pending','held'].includes(c.state))return {state:c.state,command_id:c.command_id};
  if(c.state==='signed'){
   const p=c.receipt?.payload;
   if(c.operation!=='master.security_decoy.manage'||!uuid(c.actor_id)||!uuid(c.session_id)||!uuid(c.company_id)||p?.subject!==c.actor_id||p?.company_id!==c.company_id||!exact(c.receipt,'payload,signature')||!validPayload(p,now())||typeof c.receipt.signature!=='string'||!/^[a-f0-9]{128}$/.test(c.receipt.signature)||await hash(JSON.stringify(canonical(p)))!==c.payload_hash||!await verified(publicJwk(c.manager_jwk),'sko-decoy-management-v1',JSON.stringify(canonical(p)),c.receipt.signature))throw Error('Saved issuer receipt rejected');
   // The authenticated DB lookup already rechecked current SID/actor/company,
   // Master/config/credential and expiry. No new signing operation on retry.
   return {state:'signed',command_id:c.command_id,receipt:c.receipt};
  }
  if(c.state!=='claimed'||c.operation!=='master.security_decoy.manage'||!uuid(c.actor_id)||!uuid(c.session_id)||!uuid(c.company_id)||!uuid(c.lease_id)||!validPayload(c.payload,now())||c.payload.subject!==c.actor_id||c.payload.company_id!==c.company_id||JSON.stringify(canonical(c.payload))!==c.payload_body||await hash(c.payload_body)!==c.payload_hash)throw Error('Issuer claim binding rejected');
  const fail=async reason=>{try{await database.fail({command_id:c.command_id,lease_id:c.lease_id,failure:reason})}catch{}};
  let resolved;
  try{resolved=await resolveSigningKey({deploymentId:c.payload.deployment_id,keyId:c.payload.key_id,keyVersion:c.payload.key_version})}catch{await fail('key_unavailable');return {state:'pending',command_id:c.command_id};}
  let signature;
  try{
   const key=resolved?.key,jwk=publicJwk(c.manager_jwk);
   if(!key||key.extractable!==false||key.algorithm?.name!=='Ed25519'||key.usages?.join(',')!=='sign'||JSON.stringify(publicJwk(resolved.publicJwk))!==JSON.stringify(jwk)||!validPayload(c.payload,now()))throw Error('Signing key unavailable');
   signature=await signBytes(key,'sko-decoy-management-v1',c.payload_body);
   if(!await verified(jwk,'sko-decoy-management-v1',c.payload_body,signature))throw Error('Signing key differs');
  }catch{await fail('signing_failed');return {state:'pending',command_id:c.command_id};}
  let receipt;
  try{receipt=await database.complete({command_id:c.command_id,lease_id:c.lease_id,payload_hash:c.payload_hash,signature})}catch{
   // Completion could have committed. Do not reopen the lease or expose an
   // unacknowledged envelope. The same proof retrieves the durable receipt.
   return {state:'pending',command_id:c.command_id};
  }
  if(!exact(receipt,'payload,signature')||JSON.stringify(canonical(receipt.payload))!==c.payload_body||receipt.signature!==signature||!validPayload(receipt.payload,now()))return {state:'pending',command_id:c.command_id};
  return {state:'signed',command_id:c.command_id,receipt};
 }});
}
