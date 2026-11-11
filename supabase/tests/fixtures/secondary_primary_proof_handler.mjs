// Isolated Edge contract candidate. Not deployed or used by the app.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply=(body,status)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
function sessionClaim(bearer,actor){
 const parts=bearer.split('.');if(parts.length!==3)throw Error('invalid session');
 const payload=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(parts[1].replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0))));
 // The exact bearer has already been accepted by server Auth getUser. Do not
 // use these decoded claims before that verification, or from another token.
 if(payload.sub!==actor||!uuid.test(payload.session_id??''))throw Error('invalid session');
 return payload.session_id;
}
async function boundedJson(req){
 const reader=req.body?.getReader();if(!reader)throw Error('invalid request');
 const chunks=[];let size=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>2048)throw Error('invalid request');chunks.push(value);}}finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
 const body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==1||typeof body.password!=='string'||body.password.length<1)throw Error('invalid request');
 return body.password;
}
export function createSecondaryPrimaryProofCandidate({getAuthUser,checkOriginSession,beginActivity,finishActivity,passwordGrant,logoutTemporary,mintTicket,log=()=>{}}){
 return async req=>{
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const authorization=req.headers.get('authorization')??'';
  if(!authorization.startsWith('Bearer ')||authorization.length>8192)return reply({error:'authentication_required'},401);
  const bearer=authorization.slice(7);let temporaryToken=null,cleanupAttempted=false,activity=null,actor=null,stage='caller',status=null;
  try{
   const user=await getAuthUser(bearer,{signal:AbortSignal.timeout(10000)});
   if(!uuid.test(user?.id??''))return reply({error:'authentication_required'},401);
   actor=user.id;const session=sessionClaim(bearer,actor);
   if(await checkOriginSession(actor,session)!==true)return reply({error:'session_unavailable'},403);
   let password;try{password=await boundedJson(req);}catch{return reply({error:'invalid_request'},400);}
   const identity=typeof user.phone==='string'&&user.phone.length>0?{phone:user.phone}:typeof user.email==='string'&&user.email.length>0?{email:user.email}:null;
   if(!identity)return reply({error:'identity_unavailable'},409);
   activity=await beginActivity(actor,session);
   stage='primary';const response=await passwordGrant({...identity,password},{signal:AbortSignal.timeout(10000)});status=response.status;
   if(!response.ok){
    log('secondary primary proof unavailable',stage,status);
    if([400,401,403].includes(response.status)){await finishActivity(actor,activity);activity=null;return reply({error:'primary_verification_failed'},403);}
    return reply({error:'primary_proof_unavailable'},503);
   }
   // Error bodies are never read. A successful payload is used only in memory.
   const result=await response.json();
   if(typeof result?.access_token==='string'&&result.access_token)temporaryToken=result.access_token;
   if(!temporaryToken||result.user?.id!==actor)throw Error('verification unconfirmed');
   stage='temporary_cleanup';cleanupAttempted=true;
   if(await logoutTemporary(temporaryToken,{scope:'local',signal:AbortSignal.timeout(10000)})!==true)throw Error('temporary cleanup unconfirmed');
   temporaryToken=null;
   stage='origin';if(await checkOriginSession(actor,session)!==true)throw Error('origin session changed');
   stage='issuer';const ticket=await mintTicket(actor,session,{scope:'secondary-password-change'});
   if(typeof ticket!=='string'||!/^[0-9a-f]{64}$/.test(ticket))throw Error('issuer unavailable');
   await finishActivity(actor,activity);activity=null;
   return reply({ticket,expires_in:300,scope:'secondary-password-change'},200);
  }catch{
   log('secondary primary proof unavailable',stage,status);
   return reply({error:'primary_proof_unavailable'},503);
  }finally{
   if(temporaryToken&&!cleanupAttempted){try{if(await logoutTemporary(temporaryToken,{scope:'local',signal:AbortSignal.timeout(10000)})!==true)log('secondary temporary cleanup unconfirmed');}catch{log('secondary temporary cleanup unconfirmed');}}
   // An unconfirmed remote failure stays pending for reconciliation. Never
   // claim the existing app session was revoked or a remote user was deleted.
  }
 };
}

export function primaryAuthCandidateTransport({base,publicKey,fetcher=fetch}){
 const call=(path,token,init={})=>fetcher(base+'/auth/v1/'+path,{...init,redirect:'error',headers:{apikey:publicKey,Authorization:'Bearer '+token,'Content-Type':'application/json'}});
 return {
  getAuthUser:async(bearer,options)=>{const r=await call('user',bearer,{method:'GET',signal:options.signal});if(!r.ok)return null;return await r.json();},
  passwordGrant:(credentials,options)=>call('token?grant_type=password',publicKey,{method:'POST',body:JSON.stringify(credentials),signal:options.signal}),
  logoutTemporary:async(token,options)=>{if(options.scope!=='local')throw Error('temporary-only logout required');const r=await call('logout?scope=local',token,{method:'POST',signal:options.signal});return r.ok;},
 };
}
