// Trusted server adapters. Still OFF unless reviewed challenge adapters are supplied.
const origin='https://ztktgquxvcxcjxtluspu.supabase.co';
async function boundedJSON(response,signal){
 if(!response.ok||!response.body)throw Error('google_primary_verification_unavailable');
 const length=response.headers.get('content-length');
 if(length!==null&&(!/^[0-9]+$/.test(length)||Number(length)>65536)){void response.body.cancel().catch(()=>{});throw Error('google_primary_verification_unavailable');}
 const reader=response.body.getReader();let size=0;const chunks=[];
 const cancel=()=>{void reader.cancel().catch(()=>{});};
 signal.addEventListener('abort',cancel,{once:true});
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;
  if(size>65536){await reader.cancel();throw Error('google_primary_verification_unavailable');}chunks.push(value);}}
 finally{signal.removeEventListener('abort',cancel);reader.releaseLock();}
 const all=new Uint8Array(size);let at=0;for(const c of chunks){all.set(c,at);at+=c.byteLength;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all));
}
export function createGooglePrimaryPorts({enabled=false,baseUrl,publicKey,audiences=[],authorizedPresenters=[],
 loadChallenge,consumeChallenge,fetcher=fetch,now=()=>Math.floor(Date.now()/1000),timeoutMs=10000}){
 if(!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>10000)throw Error('google_primary_verification_unavailable');
 if(!Array.isArray(audiences)||!Array.isArray(authorizedPresenters))throw Error('google_primary_verification_unavailable');
 const ready=enabled===true&&baseUrl===origin&&typeof publicKey==='string'&&publicKey.length>0&&
  typeof loadChallenge==='function'&&typeof consumeChallenge==='function';
 let keys=[],expiry=0;
 const get=async(url,headers)=>{
  const controller=new AbortController();let timer;
  const work=(async()=>boundedJSON(await fetcher(url,{method:'GET',headers,redirect:'error',signal:controller.signal}),controller.signal))();
  try{return await Promise.race([work,new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(Error('google_primary_verification_unavailable'));},timeoutMs);})]);}
  finally{clearTimeout(timer);controller.abort();}
 };
 return Object.freeze({enabled:ready,audiences:Object.freeze([...audiences]),authorizedPresenters:Object.freeze([...authorizedPresenters]),now,
  loadChallenge,consumeChallenge,
  authenticateExactBearer:async token=>{
   if(!ready)throw Error('google_primary_verification_unavailable');
   const user=await get(origin+'/auth/v1/user',{apikey:publicKey,Authorization:'Bearer '+token});
   // Decode ONLY after GoTrue has accepted the exact JWT. Signature validation is not delegated to the client.
   const parts=token.split('.');if(parts.length!==3)throw Error('google_primary_verification_unavailable');
   const raw=Uint8Array.from(atob(parts[1].replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));
   const claims=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));
   return {user,claims};
  },
  resolveGoogleKey:async kid=>{
   if(!ready)throw Error('google_primary_verification_unavailable');
   if(now()>=expiry){const value=await get('https://www.googleapis.com/oauth2/v3/certs',{});
    if(!Array.isArray(value?.keys)||!value.keys.length||value.keys.length>10||value.keys.some(k=>!k||k.kty!=='RSA'||k.alg!=='RS256'||k.use!=='sig'||!/^[A-Za-z0-9_-]{1,128}$/.test(k.kid??'')||!k.n||!k.e||['d','p','q','dp','dq','qi','oth'].some(x=>Object.hasOwn(k,x)))||new Set(value.keys.map(k=>k.kid)).size!==value.keys.length)throw Error('google_primary_verification_unavailable');
    keys=value.keys;expiry=now()+300;
   }
   return keys.find(k=>k.kid===kid);
  },
 });
}
