const project='https://ztktgquxvcxcjxtluspu.supabase.co';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const deny=()=>Error('apple_rate_unavailable');
export function createAppleSharedRatePort({enabled=false,baseUrl,serviceKey,fetcher=fetch,timeoutMs=5000}={}) {
 if (!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>10000) throw deny();
 const ready=enabled===true&&baseUrl===project&&typeof serviceKey==='string'&&!!serviceKey;
 return Object.freeze({ready,async takeVerified(binding){
  const actor=binding?.user?.id,sid=binding?.claims?.session_id;
  if(!ready||!uuid.test(actor??'')||binding.claims.sub!==actor||!uuid.test(sid??''))throw deny();
  const controller=new AbortController();let timer;
  const headers={apikey:serviceKey,'Content-Type':'application/json'};
  if(!serviceKey.startsWith('sb_secret_'))headers.Authorization='Bearer '+serviceKey;
  const work=(async()=>{const response=await fetcher(project+'/rest/v1/rpc/take_apple_enrollment_attempt',{
    method:'POST',redirect:'error',signal:controller.signal,headers,body:JSON.stringify({p_actor_id:actor,p_session_id:sid})});
   if(response.status!==200||!response.body)throw deny();
   const size=response.headers.get('content-length');if(size!==null&&(!/^\d+$/.test(size)||Number(size)>4096))throw deny();
   const reader=response.body.getReader();let n=0;const parts=[];
   controller.signal.addEventListener('abort',()=>{void reader.cancel().catch(()=>{});},{once:true});
   try{for(;;){const {done,value}=await reader.read();if(done)break;n+=value.length;if(n>4096){void reader.cancel().catch(()=>{});throw deny();}parts.push(value);}}finally{reader.releaseLock();}
   const bytes=new Uint8Array(n);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}
   const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
   if(!value||value.version!==1||value.allowed!==true)throw deny();return true;
  })();
  try{return await Promise.race([work,new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(deny());},timeoutMs);})]);}
  finally{clearTimeout(timer);controller.abort();}
 }});
}
