// Review-only boundary, not a KMS integration or proof of independent custody.
// Store callbacks must be independently trusted and durably commit before return.
// No private key is accepted here. Callback configuration is server-owned only.
import {createPublicKey} from 'node:crypto';
import {receiptBytes,validateWitnessReceipt} from './recovery-witness-model.mjs';

// Callback return values and caller input are untrusted records. Read descriptors
// once; invoking accessors would let a checked binding differ from the saved one.
function snapshot(record,names) {
  if(!record||typeof record!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(record)))throw Error('invalid record');
  const descriptors=Object.getOwnPropertyDescriptors(record);
  if(Reflect.ownKeys(descriptors).length!==names.length)throw Error('invalid record');
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const descriptor=descriptors[name];
    if(!descriptor||!Object.hasOwn(descriptor,'value'))throw Error('invalid record');
    return [name,descriptor.value];
  })));
}
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
export function createExternalSignerWitnessCandidate({store,signReceipt,key,now=Date.now,timeoutMs=5000}) {
  if(!store||typeof store.consumeCommitted!=='function'||typeof store.readCommitted!=='function'||
      typeof signReceipt!=='function'||typeof now!=='function'||!Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>30000||
      !key||key.kty!=='OKP'||key.crv!=='Ed25519'||'d' in key||typeof key.x!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(key.x)) throw Error('invalid witness signer configuration');
  let pin;
  try{pin=Object.freeze(createPublicKey({key:{kty:key.kty,crv:key.crv,x:key.x},format:'jwk'}).export({format:'jwk'}));}
  catch{throw Error('invalid witness signer configuration');}
  const consumeCommitted=store.consumeCommitted.bind(store),readCommitted=store.readCommitted.bind(store);
  const operation=async(method,input)=>{
    const fail=()=>new Error('witness outcome unknown; reconcile before retry');
    try{input=snapshot(input,['scope','nonce','proposalHash','challenge']);}catch{throw fail();}
    if(!input||typeof input.scope!=='string'||!input.scope||input.scope.length>200||
        !hex(input.nonce)||!hex(input.proposalHash)||!hex(input.challenge))throw fail();
    const scope=input.scope,nonce=input.nonce,proposalHash=input.proposalHash,challenge=input.challenge;
    let timer;
    const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>reject(fail()),timeoutMs);});
    const bounded=p=>Promise.race([p,deadline]);
    try{
      // Exactly one call: timeout may occur after a durable remote commit.
      const row=snapshot(await bounded(method(Object.freeze({scope,nonce,proposalHash}))),['committed','scope','nonce','proposalHash','sequence']);
      if(!row||row.committed!==true||row.scope!==scope||row.nonce!==nonce||row.proposalHash!==proposalHash||
          !Number.isSafeInteger(row.sequence)||row.sequence<1)throw fail();
      const issued=now();if(!Number.isSafeInteger(issued))throw fail();
      const payload=Object.freeze({v:1,scope,challenge,nonce,proposal_hash:proposalHash,sequence:row.sequence,issued});
      // A hardware/remote signer implementation belongs behind this callback.
      // Never give it arbitrary caller payloads, private keys or auth credentials.
      const raw=await bounded(signReceipt(Buffer.from(receiptBytes(payload))));
      if(!(raw instanceof Uint8Array)||raw.byteLength!==64)throw fail();
      const receipt={payload,signature:Buffer.from(raw).toString('hex')};
      validateWitnessReceipt(receipt,{scope,nonce,proposalHash,challenge,key:pin,now:now(),minSequence:payload.sequence});
      return receipt;
    }catch{throw fail();}finally{clearTimeout(timer);}
  };
  return Object.freeze({consume:args=>operation(consumeCommitted,args),lookup:args=>operation(readCommitted,args)});
}
