// Candidate: trusted Apple key source, fixed origin, hard deadline and bounded cache.
const url = 'https://appleid.apple.com/auth/keys';
const denied = () => Error('apple_key_unavailable');
const valid = k => k && k.kty === 'RSA' && k.alg === 'RS256' && k.use === 'sig' &&
  typeof k.kid === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(k.kid) &&
  typeof k.n === 'string' && /^[A-Za-z0-9_-]{300,1000}$/.test(k.n) &&
  typeof k.e === 'string' && /^[A-Za-z0-9_-]{1,12}$/.test(k.e) &&
  !['d','p','q','dp','dq','qi','oth'].some(x => Object.hasOwn(k, x));
export function createAppleKeyResolver({fetcher=fetch, now=()=>Date.now(), timeoutMs=5000, ttlMs=300000}={}) {
  if (!Number.isInteger(timeoutMs) || timeoutMs<1 || timeoutMs>10000 || !Number.isInteger(ttlMs) || ttlMs<1 || ttlMs>300000) throw denied();
  let keys=[], expiry=0, pending=null;
  async function refresh() {
    const controller=new AbortController(); let timer;
    const work=(async()=>{
      const response=await fetcher(url,{method:'GET',redirect:'error',signal:controller.signal});
      if(!response.ok || !response.body) throw denied();
      const length=response.headers.get('content-length');
      if(length!==null && (!/^\d+$/.test(length) || Number(length)>65536)) throw denied();
      const reader=response.body.getReader(); let size=0; const chunks=[];
      controller.signal.addEventListener('abort',()=>{void reader.cancel().catch(()=>{});},{once:true});
      try { for (;;) {const {done,value}=await reader.read();if(done) break;size+=value.byteLength;if(size>65536)throw denied();chunks.push(value);} }
      finally {reader.releaseLock();}
      const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
      const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
      if(!Array.isArray(value?.keys) || !value.keys.length || value.keys.length>10 || value.keys.some(k=>!valid(k)) || new Set(value.keys.map(k=>k.kid)).size!==value.keys.length)throw denied();
      if(controller.signal.aborted) throw denied();
      keys=value.keys.map(k=>Object.freeze({...k}));expiry=now()+ttlMs;
    })();
    try {await Promise.race([work,new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(denied());},timeoutMs);})]);}
    finally {clearTimeout(timer);controller.abort();}
  }
  return async kid=>{
    if(typeof kid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(kid))throw denied();
    if(now()>=expiry){if(!pending)pending=refresh().finally(()=>{pending=null;});await pending;}
    const key=keys.find(k=>k.kid===kid);if(!key)throw denied();return key;
  };
}
