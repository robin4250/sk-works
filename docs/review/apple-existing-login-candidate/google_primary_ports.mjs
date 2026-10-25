// Trusted server adapters. Still OFF unless reviewed challenge adapters are supplied.
const origin='https://ztktgquxvcxcjxtluspu.supabase.co';
async function boundedJSON(response){
 if(!response.ok||!response.body)throw Error('google_primary_verification_unavailable');
 const reader=response.body.getReader();let size=0;const chunks=[];
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;
  if(size>65536){await reader.cancel();throw Error('google_primary_verification_unavailable');}chunks.push(value);}}
 finally{reader.releaseLock();}
 const all=new Uint8Array(size);let at=0;for(const c of chunks){all.set(c,at);at+=c.byteLength;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all));
}
export function createGooglePrimaryPorts({enabled=false,baseUrl,publicKey,audiences=[],authorizedPresenters=[],
 loadChallenge,consumeChallenge,fetcher=fetch,now=()=>Math.floor(Date.now()/1000)}){
 const ready=enabled===true&&baseUrl===origin&&typeof publicKey==='string'&&publicKey.length>0&&
  typeof loadChallenge==='function'&&typeof consumeChallenge==='function';
 let keys=[],expiry=0;
 const get=async(url,headers)=>boundedJSON(await fetcher(url,{method:'GET',headers,redirect:'error',signal:AbortSignal.timeout(10000)}));
 return Object.freeze({enabled:ready,audiences,authorizedPresenters,now,
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
    if(!Array.isArray(value?.keys)||!value.keys.length||value.keys.length>10)throw Error('google_primary_verification_unavailable');
    keys=value.keys;expiry=now()+300;
   }
   return keys.find(k=>k.kid===kid);
  },
 });
}
