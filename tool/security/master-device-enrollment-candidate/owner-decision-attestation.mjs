// Review-only cryptographic receipt check, not an owner verifier or approval API.
// request, databaseNowMs and pinnedIssuer MUST come from independent trusted
// storage. This module cannot establish human ownership, consume a receipt,
// approve a pending key, or activate a device. No private signer key is accepted.
import {createHash,createPublicKey,verify} from 'node:crypto';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const hash=/^[a-f0-9]{64}$/;
const scope='sko-master-independent-owner-decision-v1';
const fields=['version','issuerKeyId','decision','requestId','actor','requesterSession','deviceId','pendingId','challengeId','keySha256','reviewNonce','issuedMs','expiresMs','signature'];
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&
 [Object.prototype,null].includes(Object.getPrototypeOf(value))&&Reflect.ownKeys(value).length===keys.length&&
 keys.every(k=>{const d=Object.getOwnPropertyDescriptor(value,k);return d&&Object.hasOwn(d,'value')&&d.enumerable;});
function validReceipt(r){return r?.version===1&&typeof r.issuerKeyId==='string'&&/^[A-Za-z0-9_-]{1,80}$/.test(r.issuerKeyId)&&
 ['approved','denied'].includes(r.decision)&&['requestId','actor','requesterSession','deviceId','pendingId','challengeId'].every(k=>typeof r[k]==='string'&&uuid.test(r[k]))&&
 typeof r.keySha256==='string'&&hash.test(r.keySha256)&&typeof r.reviewNonce==='string'&&hash.test(r.reviewNonce)&&
 Number.isSafeInteger(r.issuedMs)&&r.issuedMs>=0&&Number.isSafeInteger(r.expiresMs)&&r.expiresMs>r.issuedMs&&r.expiresMs-r.issuedMs<=120000;}
export function ownerDecisionPayload(r){
 if(!validReceipt(r))throw Error('invalid owner decision receipt');
 return Buffer.from(JSON.stringify([scope,r.version,r.issuerKeyId,r.decision,r.requestId,r.actor,r.requesterSession,r.deviceId,r.pendingId,r.challengeId,r.keySha256,r.reviewNonce,r.issuedMs,r.expiresMs]),'utf8');
}
export function verifyOwnerDecisionAttestation({receipt,request,databaseNowMs,pinnedIssuer}){
 try{
  if(!exact(receipt,fields)||!validReceipt(receipt)||!Number.isSafeInteger(databaseNowMs)||databaseNowMs<0||
    request?.status!=='awaiting_independent_owner'||request.cancelled!==false||
    !Number.isSafeInteger(request.createdMs)||request.createdMs<0||!Number.isSafeInteger(request.expiresMs)||
    request.createdMs>receipt.issuedMs||receipt.issuedMs>databaseNowMs||receipt.expiresMs<=databaseNowMs||
    receipt.expiresMs>request.expiresMs||request.expiresMs-request.createdMs>120000||
    receipt.requestId!==request.id||receipt.actor!==request.actor||receipt.requesterSession!==request.requesterSession||
    receipt.deviceId!==request.deviceId||receipt.pendingId!==request.pendingId||receipt.challengeId!==request.challengeId||
    receipt.keySha256!==request.keySha256||receipt.reviewNonce!==request.reviewNonce||
    pinnedIssuer?.purpose!==scope||pinnedIssuer.keyId!==receipt.issuerKeyId||
    !exact(pinnedIssuer.publicKeyJwk,['kty','crv','x'])||pinnedIssuer.publicKeyJwk.kty!=='OKP'||pinnedIssuer.publicKeyJwk.crv!=='Ed25519'||
    typeof pinnedIssuer.publicKeyJwk.x!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(pinnedIssuer.publicKeyJwk.x)||
    typeof receipt.signature!=='string'||!/^[A-Za-z0-9_-]{86}$/.test(receipt.signature))return null;
  const key=createPublicKey({key:pinnedIssuer.publicKeyJwk,format:'jwk'});
  if(key.asymmetricKeyType!=='ed25519'||key.export({format:'jwk'}).x!==pinnedIssuer.publicKeyJwk.x)return null;
  const signature=Buffer.from(receipt.signature,'base64url');
  if(signature.length!==64||signature.toString('base64url')!==receipt.signature)return null;
  const payload=ownerDecisionPayload(receipt);
  if(!verify(null,payload,key,signature))return null;
  // Evidence only. A future locked DB operation must recheck live sessions,
  // pending/request/cancellation state, nonce and issuer trust before one claim.
  return Object.freeze({requestId:receipt.requestId,decision:receipt.decision,issuerKeyId:receipt.issuerKeyId,
   issuedMs:receipt.issuedMs,expiresMs:receipt.expiresMs,
   attestationSha256:createHash('sha256').update(payload).update(signature).digest('hex')});
 }catch{return null;}
}
