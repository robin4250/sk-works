// Review-only, default-OFF transition verifier. The current pin/history MUST be
// independently authenticated server configuration, never app-owner evidence.
// No trust bootstrap, durable CAS, lost-key recovery, signing or device mutation.
import {createHash,createPublicKey,verify} from 'node:crypto';

const purpose='sko-master-independent-owner-decision-v1';
const domain='sko-master-owner-issuer-continuity-v1';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const digest=/^[0-9a-f]{64}$/;
const keyId=/^[A-Za-z0-9_-]{1,80}$/;
const transitionFields=['version','authorityId','fromEpoch','toEpoch','previousSha256','oldKeyId','newKeyId','newPublicKeyJwk','issuedMs','expiresMs','oldSignature','newSignature'];

function snapshot(value,fields){
 if(!value||typeof value!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(value))||Reflect.ownKeys(value).length!==fields.length)throw Error('plain exact object required');
 const copy={};
 for(const field of fields){const d=Object.getOwnPropertyDescriptor(value,field);if(!d||!d.enumerable||!Object.hasOwn(d,'value'))throw Error('plain data required');copy[field]=d.value;}
 return copy;
}
function publicKey(value){
 const key=snapshot(value,['kty','crv','x']);
 if(key.kty!=='OKP'||key.crv!=='Ed25519'||typeof key.x!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(key.x))throw Error('public Ed25519 key required');
 const parsed=createPublicKey({key,format:'jwk'});
 if(parsed.asymmetricKeyType!=='ed25519'||parsed.export({format:'jwk'}).x!==key.x)throw Error('canonical public key required');
 return Object.freeze(key);
}
function signature(value){
 if(typeof value!=='string'||!/^[A-Za-z0-9_-]{86}$/.test(value))throw Error('canonical signature required');
 const bytes=Buffer.from(value,'base64url');if(bytes.length!==64||bytes.toString('base64url')!==value)throw Error('canonical signature required');return bytes;
}
function transition(value){
 const p=snapshot(value,transitionFields);p.newPublicKeyJwk=publicKey(p.newPublicKeyJwk);
 if(p.version!==1||typeof p.authorityId!=='string'||!uuid.test(p.authorityId)||
  !Number.isSafeInteger(p.fromEpoch)||p.fromEpoch<1||p.fromEpoch>64||p.toEpoch!==p.fromEpoch+1||
  typeof p.previousSha256!=='string'||!digest.test(p.previousSha256)||
  ![p.oldKeyId,p.newKeyId].every(k=>typeof k==='string'&&keyId.test(k))||p.oldKeyId===p.newKeyId||
  !Number.isSafeInteger(p.issuedMs)||p.issuedMs<0||!Number.isSafeInteger(p.expiresMs)||
  p.expiresMs<=p.issuedMs||p.expiresMs-p.issuedMs>120000)throw Error('invalid issuer transition');
 return p;
}
function bytes(p){return Buffer.from(JSON.stringify([domain,p.version,p.authorityId,p.fromEpoch,p.toEpoch,p.previousSha256,p.oldKeyId,p.newKeyId,p.newPublicKeyJwk.kty,p.newPublicKeyJwk.crv,p.newPublicKeyJwk.x,p.issuedMs,p.expiresMs]));}

// Use only to obtain deterministic bytes for an EXTERNAL old/new signer. This
// function holds no key and is not an independent identity verification channel.
export function ownerIssuerContinuityPayload(proposal){return bytes(transition(proposal));}

export function verifyOwnerIssuerContinuity({enabled=false,trusted,authorityCheckpoint,proposal,databaseNowMs}){
 if(enabled!==true)return null;
 try{
  const pin=snapshot(trusted,['purpose','authorityId','epoch','keyId','publicKeyJwk','headSha256','retiredKeys']);
  // This separate checkpoint must be authenticated and fresh from the external
  // authority. A same-DB copy or caller-supplied assertion is not anti-rollback.
  const checkpoint=snapshot(authorityCheckpoint,['authorityId','epoch','headSha256']);
  pin.publicKeyJwk=publicKey(pin.publicKeyJwk);
  if(pin.purpose!==purpose||typeof pin.authorityId!=='string'||!uuid.test(pin.authorityId)||
   !Number.isSafeInteger(pin.epoch)||pin.epoch<1||pin.epoch>65||typeof pin.keyId!=='string'||!keyId.test(pin.keyId)||
   typeof pin.headSha256!=='string'||!digest.test(pin.headSha256)||!Array.isArray(pin.retiredKeys)||
   pin.retiredKeys.length!==pin.epoch-1||!Number.isSafeInteger(databaseNowMs)||databaseNowMs<0||
   checkpoint.authorityId!==pin.authorityId||checkpoint.epoch!==pin.epoch||checkpoint.headSha256!==pin.headSha256)throw Error('trusted pin and external checkpoint required');
  const ids=new Set([pin.keyId]),keys=new Set([pin.publicKeyJwk.x]);
  if(Object.getPrototypeOf(pin.retiredKeys)!==Array.prototype||Reflect.ownKeys(pin.retiredKeys).length!==pin.retiredKeys.length+1)throw Error('plain history required');
  const history=Array.from({length:pin.retiredKeys.length},(_,index)=>{
   const entry=Object.getOwnPropertyDescriptor(pin.retiredKeys,String(index));
   if(!entry||!entry.enumerable||!Object.hasOwn(entry,'value'))throw Error('plain history entry required');
   const value=entry.value;
   const item=snapshot(value,['epoch','keyId','publicKeyJwk']);item.publicKeyJwk=publicKey(item.publicKeyJwk);
   if(item.epoch!==index+1||typeof item.keyId!=='string'||!keyId.test(item.keyId)||ids.has(item.keyId)||keys.has(item.publicKeyJwk.x))throw Error('trusted history invalid');
   ids.add(item.keyId);keys.add(item.publicKeyJwk.x);return Object.freeze(item);
  });
  const p=transition(proposal),oldSignature=signature(p.oldSignature),newSignature=signature(p.newSignature);
  if(p.authorityId!==pin.authorityId||p.fromEpoch!==pin.epoch||p.previousSha256!==pin.headSha256||p.oldKeyId!==pin.keyId||
   ids.has(p.newKeyId)||keys.has(p.newPublicKeyJwk.x)||p.issuedMs>databaseNowMs||p.expiresMs<=databaseNowMs)throw Error('issuer scope changed');
  const payload=bytes(p);
  if(!verify(null,payload,createPublicKey({key:pin.publicKeyJwk,format:'jwk'}),oldSignature)||
   !verify(null,payload,createPublicKey({key:p.newPublicKeyJwk,format:'jwk'}),newSignature))throw Error('both issuer signatures required');
  const headSha256=createHash('sha256').update(payload).update(oldSignature).update(newSignature).digest('hex');
  const retired=Object.freeze({epoch:pin.epoch,keyId:pin.keyId,publicKeyJwk:pin.publicKeyJwk});
  return Object.freeze({
   next:Object.freeze({purpose,authorityId:pin.authorityId,epoch:p.toEpoch,keyId:p.newKeyId,publicKeyJwk:p.newPublicKeyJwk,
    headSha256,retiredKeys:Object.freeze([...history,retired])}),
   evidence:Object.freeze({payloadBase64:payload.toString('base64'),oldSignature:p.oldSignature,newSignature:p.newSignature,headSha256}),
  });
 }catch{return null;}
}
