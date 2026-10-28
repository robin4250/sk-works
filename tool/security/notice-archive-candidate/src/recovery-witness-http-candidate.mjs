// Review-only HTTP boundary. Not hosted, not independent custody or recovery.
// authority must durably commit consume before signing; this handler cannot
// establish that property, key custody, rate limiting or rollback resistance.
import {createHash, createPublicKey, timingSafeEqual} from 'node:crypto';
import {validateWitnessReceipt} from './recovery-witness-model.mjs';

const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const digest=x=>createHash('sha256').update(x).digest();
export function createWitnessHttpCandidate({endpoint,bearer,scopes,key,authority,now=Date.now,timeoutMs=5000}) {
  const url=new URL(endpoint);
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||
      typeof bearer!=='string'||bearer.length<16||bearer.length>4096||/[\r\n]/.test(bearer)||
      !Array.isArray(scopes)||!scopes.length||scopes.some(s=>typeof s!=='string'||!s||s.length>200)||
      !authority||typeof authority.consume!=='function'||typeof authority.lookup!=='function'||
      !Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>30000||
      !key||key.kty!=='OKP'||key.crv!=='Ed25519'||'d' in key) throw Error('invalid witness configuration');
  const pin=createPublicKey({key:{kty:key.kty,crv:key.crv,x:key.x},format:'jwk'}).export({format:'jwk'});
  const allowed=new Set(scopes),credential=digest(`Bearer ${bearer}`),target=url.href;
  const reply=(status,value)=>Response.json(value,{status,headers:{'cache-control':'no-store','x-content-type-options':'nosniff'}});
  return async request=>{
    if(request.method!=='POST'||request.url!==target) return reply(404,{error:'unavailable'});
    const authorization=request.headers.get('authorization');
    if(typeof authorization!=='string'||authorization.length>4103||
        !timingSafeEqual(digest(authorization),credential)) return reply(401,{error:'unavailable'});
    let reader,timer;
    const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('deadline')),timeoutMs);});
    const bounded=p=>Promise.race([p,deadline]);
    try {
      if(request.headers.get('content-type')?.split(';')[0].trim()!=='application/json'||!request.body) return reply(400,{error:'invalid request'});
      const declared=request.headers.get('content-length');
      if(declared!==null&&(!/^\d+$/.test(declared)||Number(declared)>2048)) return reply(400,{error:'invalid request'});
      reader=request.body.getReader();
      const bytes=new Uint8Array(2048);let length=0;
      while(true){const {done,value}=await bounded(reader.read());if(done)break;
        if(!(value instanceof Uint8Array)||value.length>bytes.length-length)return reply(400,{error:'invalid request'});
        bytes.set(value,length);length+=value.length;
      }
      const input=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes.subarray(0,length)));
      const fields=['operation','scope','nonce','proposalHash','challenge'];
      if(!input||Array.isArray(input)||Object.keys(input).length!==fields.length||Object.keys(input).some(k=>!fields.includes(k))||
          !['consume','lookup'].includes(input.operation)||!allowed.has(input.scope)||
          !hex(input.nonce)||!hex(input.proposalHash)||!hex(input.challenge)) return reply(400,{error:'invalid request'});
      const issued=now();if(!Number.isSafeInteger(issued))throw Error('clock unavailable');
      // Never retry a consuming call, including when the response deadline wins.
      const args=Object.freeze({scope:input.scope,nonce:input.nonce,proposalHash:input.proposalHash,challenge:input.challenge,now:issued});
      const receipt=await bounded(authority[input.operation](args));
      const payload=receipt?.payload;
      if(!receipt||Object.keys(receipt).sort().join(',')!=='payload,signature'||!payload||
          Object.keys(payload).sort().join(',')!=='challenge,issued,nonce,proposal_hash,scope,sequence,v')throw Error('invalid receipt');
      validateWitnessReceipt(receipt,{...args,key:pin,now:now(),minSequence:1});
      return reply(200,receipt);
    } catch { return reply(503,{error:'witness outcome unknown; reconcile before retry'}); }
    finally {
      clearTimeout(timer);
      if(reader){try{Promise.resolve(reader.cancel()).catch(()=>{});}catch{}
        try{reader.releaseLock();}catch{}}
    }
  };
}
