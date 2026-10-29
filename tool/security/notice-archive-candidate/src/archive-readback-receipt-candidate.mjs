// OFF/unhosted candidate: a signature over freshly restored opaque bytes is
// only a readback observation, never a retention/independence or purge permit.
import {createPublicKey,randomBytes,verify} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {snapshotArchiveByteDescriptorCandidate,verifyArchiveByteReadbackCandidate} from './archive-byte-store-candidate.mjs';

const fail=()=>Error('archive readback unavailable');
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(x);
function own(value,names){
 if(!value||typeof value!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(value)))throw fail();
 const ds=Object.getOwnPropertyDescriptors(value);
 if(Reflect.ownKeys(ds).length!==names.length||names.some(k=>!Object.hasOwn(ds,k)||!Object.hasOwn(ds[k],'value')))throw fail();
 return Object.freeze(Object.fromEntries(names.map(k=>[k,ds[k].value])));
}
function publicPin(key){
 const raw=own(key,['kty','crv','x']);
 if(raw.kty!=='OKP'||raw.crv!=='Ed25519'||typeof raw.x!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(raw.x))throw fail();
 try{return createPublicKey({key:raw,format:'jwk'});}catch{throw fail();}
}
function input(value){
 const v=own(value,['authority_id','challenge','descriptor']);
 if(!uuid(v.authority_id)||!hex(v.challenge))throw fail();
 return Object.freeze({...v,descriptor:snapshotArchiveByteDescriptorCandidate(v.descriptor)});
}
function payload(value){
 const p=own(value,['v','kind','authority_id','challenge','descriptor','observed_at','expires_at']);
 if(p.v!==1||p.kind!=='archive_bytes_observed'||!uuid(p.authority_id)||!hex(p.challenge)||!Number.isSafeInteger(p.observed_at)||!Number.isSafeInteger(p.expires_at)||p.observed_at<0||p.expires_at!==p.observed_at+30000)throw fail();
 return Object.freeze({...p,descriptor:snapshotArchiveByteDescriptorCandidate(p.descriptor)});
}
export function archiveReadbackReceiptBytesCandidate(value){
 const p=payload(value);
 return Buffer.from(`sko-archive-byte-readback-v1\n${JSON.stringify(p)}`);
}
function check(receipt,expected,pin,now){
 const r=own(receipt,['payload','signature']),p=payload(r.payload),i=input(expected);
 if(!Number.isSafeInteger(now)||now<p.observed_at||now>=p.expires_at||p.authority_id!==i.authority_id||p.challenge!==i.challenge||JSON.stringify(p.descriptor)!==JSON.stringify(i.descriptor)||typeof r.signature!=='string'||!/^[a-f0-9]{128}$/.test(r.signature))throw fail();
 if(!verify(null,archiveReadbackReceiptBytesCandidate(p),pin,Buffer.from(r.signature,'hex')))throw fail();
 return Object.freeze({payload:p,signature:r.signature});
}
function timeoutLimit(timeoutMs){if(!Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>30000)throw fail();}
async function bounded(operation,timeoutMs){
 let timer,active=true;const expires=performance.now()+timeoutMs;
 const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>{active=false;reject(fail());},timeoutMs);});
 const checkActive=()=>{if(!active||performance.now()>=expires){active=false;throw fail();}};
 // Timers cannot interrupt a synchronous callback. Check the absolute deadline
 // before invoking work and after it settles, including timer-starved microtasks.
 try{return await Promise.race([Promise.resolve().then(()=>{checkActive();return operation(checkActive);}).then(value=>{checkActive();return value;}),deadline]);}
 finally{active=false;clearTimeout(timer);}
}

// The restore implementation and external signer are trusted, server-owned
// configuration. No private key, path or caller-selected signature bytes enter
// this boundary. This factory does not create a listener or contact a service.
export function createArchiveReadbackAttestorCandidate({enabled=false,authorityId,store,signObservation,key,now=Date.now,timeoutMs=5000}={}){
 if(!enabled||!uuid(authorityId)||typeof store?.restore!=='function'||typeof signObservation!=='function'||typeof now!=='function')throw fail();
 timeoutLimit(timeoutMs);const pin=publicPin(key),restore=store.restore.bind(store);
 return Object.freeze({async observe(value){
  try{
   const i=input(value);if(i.authority_id!==authorityId)throw fail();
   return await bounded(async checkActive=>{
    const raw=await restore(i.descriptor);
    checkActive();
    if(!(raw instanceof Uint8Array)||raw.length!==i.descriptor.byte_length)throw fail();
    const bytes=Buffer.from(raw);
    verifyArchiveByteReadbackCandidate(i.descriptor,bytes);
    const observed=now();if(!Number.isSafeInteger(observed))throw fail();
    const p=payload({v:1,kind:'archive_bytes_observed',authority_id:authorityId,challenge:i.challenge,descriptor:i.descriptor,observed_at:observed,expires_at:observed+30000});
    // The signer receives a distinct buffer so mutation cannot alter the
    // attestor's canonical payload. Its response is independently verified.
    checkActive();
    const signature=await signObservation(Buffer.from(archiveReadbackReceiptBytesCandidate(p)));
    checkActive();
    if(!(signature instanceof Uint8Array)||signature.length!==64)throw fail();
    return check({payload:p,signature:Buffer.from(signature).toString('hex')},i,pin,now());
   },timeoutMs);
  }catch{throw fail();}
 }});
}

// A fresh challenge is generated inside each explicit read operation. Callback
// transport authentication/hosting and trusted expected descriptor custody are
// outside this unhosted candidate; no consume/release operation is performed.
export function createArchiveReadbackVerifierCandidate({enabled=false,authorityId,key,fetchObservation,now=Date.now,timeoutMs=5000}={}){
 if(!enabled||!uuid(authorityId)||typeof fetchObservation!=='function'||typeof now!=='function')throw fail();
 timeoutLimit(timeoutMs);const pin=publicPin(key);
 return Object.freeze({async verify(expected){
  try{
   const d=snapshotArchiveByteDescriptorCandidate(expected),challenge=randomBytes(32).toString('hex');
   const i=Object.freeze({authority_id:authorityId,challenge,descriptor:d});
   return await bounded(async checkActive=>{
    const response=await fetchObservation(i);checkActive();
    const receipt=check(response,i,pin,now());checkActive();
    return Object.freeze({status:'readback_verified_unattested',receipt});
   },timeoutMs);
  }catch{throw fail();}
 }});
}
