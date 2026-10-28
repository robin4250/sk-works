// Internal/default-OFF bridge. No endpoint, pool acquisition, client grants or
// production configuration is provided here. SQL retains its live-session and
// company/permission/master-gate checks; getUser alone does not prove liveness.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const deny=()=>Error('scanner authentication unavailable');

export async function verifyScannerRegistrationBearer({enabled=false,projectOrigin,expectedIssuer,publicKey,
 bearer,fetchImpl=globalThis.fetch,timeoutMs=5000}) {
 if(!enabled)throw deny();
 let origin;
 try{origin=new URL(projectOrigin);}catch{throw deny();}
 if(origin.protocol!=='https:'||origin.username||origin.password||origin.search||origin.hash||
  !['','/'].includes(origin.pathname)||typeof expectedIssuer!=='string'||!expectedIssuer||expectedIssuer.length>2048||
  typeof publicKey!=='string'||!publicKey||/[\r\n]/.test(publicKey)||
  typeof bearer!=='string'||bearer.length>16384||!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(bearer)||
  typeof fetchImpl!=='function'||!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>10000)throw deny();
 const controller=new AbortController();let timer,reader,responseBody;
 try {
  const verification=(async()=>{
   const response=await fetchImpl(new URL('/auth/v1/user',origin),{method:'GET',redirect:'error',
    signal:controller.signal,headers:{apikey:publicKey,Authorization:`Bearer ${bearer}`}});
   responseBody=response.body;
   if(controller.signal.aborted){void response.body?.cancel().catch(()=>{});throw deny();}
   if(response.status!==200||response.redirected||!response.body||
    !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type')??''))throw deny();
   const length=response.headers.get('content-length');
   if(length!==null&&(!/^\d+$/.test(length)||Number(length)>32768))throw deny();
   reader=response.body.getReader();const chunks=[];let size=0;
   while(true){const part=await reader.read();if(controller.signal.aborted)throw deny();if(part.done)break;
    size+=part.value.byteLength;if(size>32768)throw deny();chunks.push(Buffer.from(part.value));}
   return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  })();
  const user=await Promise.race([verification,new Promise((_,reject)=>{
   timer=setTimeout(()=>{controller.abort();reject(deny());},timeoutMs);
  })]);
  const claims=JSON.parse(Buffer.from(bearer.split('.')[1],'base64url').toString('utf8'));
  const stamp=Math.floor(Date.now()/1000);
  if(!user||!uuid.test(user.id??'')||user.is_anonymous!==false||claims.sub!==user.id||
   !uuid.test(claims.session_id??'')||claims.role!=='authenticated'||claims.is_anonymous!==false||
   claims.iss!==expectedIssuer||!(claims.aud==='authenticated'||Array.isArray(claims.aud)&&
    claims.aud.length===1&&claims.aud[0]==='authenticated')||
   !Number.isSafeInteger(claims.exp)||claims.exp<=stamp||
   !Number.isSafeInteger(claims.iat)||claims.iat>stamp+30)throw deny();
  // Do not forward user_metadata, app roles or any caller-asserted principal.
  const principal=Object.freeze({actor:user.id,session:claims.session_id});
  const verifiedClaims=JSON.stringify({sub:principal.actor,session_id:principal.session,
   role:'authenticated',is_anonymous:false,aud:'authenticated',iss:expectedIssuer,exp:claims.exp,iat:claims.iat});
  const deadline=Math.min(claims.exp*1000,Date.now()+15000);let used=false;
  return async function initializeVerifiedSession(client) {
   if(used||Date.now()>=deadline||typeof client?.query!=='function')throw deny();
   used=true;
   try {
    // Adapters invoke this only after BEGIN. Transaction-local claims must not
    // survive COMMIT/ROLLBACK or be reused by a second pooled request.
    await client.query("select set_config('request.jwt.claims',$1,true)",[verifiedClaims]);
    const row=(await client.query('select auth.uid() as actor,private.require_reauthentication_session() as session')).rows[0];
    if(row?.actor!==principal.actor||row?.session!==principal.session||Date.now()>=deadline)throw deny();
    return principal;
   }catch{throw deny();}
  };
 }catch{throw deny();}
 finally{clearTimeout(timer);controller.abort();if(reader)void reader.cancel().catch(()=>{});else void responseBody?.cancel().catch(()=>{});}
}
