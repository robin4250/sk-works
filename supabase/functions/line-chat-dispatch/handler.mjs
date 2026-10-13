const uuid=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
async function readInput(request){const reader=request.body?.getReader();if(!reader)throw Error();let size=0;const chunks=[];try{for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>200){void reader.cancel().catch(()=>{});throw Error();}chunks.push(value);}}finally{reader.releaseLock();}const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}
function key(env,map,legacy){try{const k=JSON.parse(env(map)||'{}').default;if(typeof k==='string'&&k)return k;}catch{}return env(legacy);}
export function createLineChatDispatchHandler({env,fetcher=fetch}){
 return async request=>{
  if(request.method!=='POST')return new Response('Method Not Allowed',{status:405});
  const authorization=request.headers.get('authorization');
  if(!authorization?.startsWith('Bearer '))return new Response('Authentication required',{status:401});
  const base=env('SUPABASE_URL'),publicKey=key(env,'SUPABASE_PUBLISHABLE_KEYS','SUPABASE_ANON_KEY'),serviceKey=key(env,'SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY'),token=env('LINE_CHANNEL_ACCESS_TOKEN');
  if(!base||!publicKey||!serviceKey||!token)return Response.json({state:'unavailable'},{status:503});
  let input;try{input=await readInput(request);}catch{return new Response('Invalid request',{status:400});}
  if(!input||Object.keys(input).length!==1||!uuid.test(input.message_id||''))return new Response('Invalid request',{status:400});
  const userHeaders={apikey:publicKey,Authorization:authorization,'Content-Type':'application/json'};
  const serviceHeaders={apikey:serviceKey,'Content-Type':'application/json',...(!serviceKey.startsWith('sb_secret_')?{Authorization:`Bearer ${serviceKey}`}:{})};
  const rpc=async(name,body,headers)=>{const r=await fetcher(`${base}/rest/v1/rpc/${name}`,{method:'POST',headers,body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok){const e=Error('Request unavailable');e.status=r.status;throw e;}return r.json();};
  try{
   const authResponse=await fetcher(`${base}/auth/v1/user`,{headers:userHeaders,redirect:'error',signal:AbortSignal.timeout(10000)});
   if(authResponse.status===401||authResponse.status===403)return new Response('Authentication required',{status:401});
   if(!authResponse.ok)throw Error();const actor=await authResponse.json();if(!uuid.test(actor.id||''))return new Response('Authentication required',{status:401});
   const ready=await rpc('prepare_line_chat_dispatch',{p_message_id:input.message_id},userHeaders);
   if(ready.state!=='ready')return Response.json({state:ready.state});
   if(!uuid.test(ready.ticket||''))throw Error();
   const claim=await rpc('claim_line_chat_dispatch',{p_ticket:ready.ticket,p_actor_id:actor.id},serviceHeaders);
   if(claim.state!=='claimed')return Response.json({state:claim.state});
   if(!uuid.test(claim.retry_key||'')||!uuid.test(claim.outbox_id||'')||!uuid.test(claim.lease_id||'')||typeof claim.to!=='string'||typeof claim.body!=='string'||claim.body.length>5000||typeof claim.sender_name!=='string'||claim.sender_name.length>20)throw Error();
   let state='unknown',code='temporary';
   try{
    const r=await fetcher('https://api.line.me/v2/bot/message/push',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','X-Line-Retry-Key':claim.retry_key},body:JSON.stringify({to:claim.to,messages:[{type:'text',text:claim.body,sender:{name:claim.sender_name}}]}),redirect:'error',signal:AbortSignal.timeout(10000)});
    if(r.status===200||(r.status===409&&r.headers.get('x-line-accepted-request-id'))){state='accepted';code=null;}
    else if(r.status===429){state='rejected';code='limit';}
    else if(r.status>=400&&r.status<500){state='rejected';code='request';}
    // Never read or expose LINE error bodies or token-bearing headers.
    try{await r.body?.cancel();}catch{}
   }catch{ /* Uncertain acceptance: the same retry key/payload must be retained. */ }
   await rpc('finish_line_chat_dispatch',{p_outbox_id:claim.outbox_id,p_lease_id:claim.lease_id,p_state:state},serviceHeaders);
   return Response.json({state,...(code?{code}:{})});
  }catch(error){return Response.json({state:'unavailable'},{status:error?.status===403?403:503});}
 };
}
