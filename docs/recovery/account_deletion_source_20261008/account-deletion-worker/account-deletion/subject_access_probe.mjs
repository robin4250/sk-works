// Trusted server context only: the same unexpired session and a file whose
// authenticated download/signing were confirmed before the restriction.
// Empty POSTs cannot send mail or create employees if a guard regresses.
export function createSubjectAccessProbe({origin,apiKey,readContext,fetchImpl=fetch,now=Date.now}) {
 const base=new URL(origin);
 if(base.protocol!=='https:'||base.username||base.password||base.pathname!=='/'||base.search||base.hash||typeof readContext!=='function'||!apiKey)throw Error('subject_probe_not_configured');
 return async ({userId,jobId,restrictedAt})=>{
  try{
   const c=await readContext({userId,jobId,restrictedAt});
   if(c?.userId!==userId||c.jobId!==jobId||typeof c.accessToken!=='string'||
    c.authVerified!==true||c.downloadVerified!==true||c.signingVerified!==true||
    !Number.isFinite(Date.parse(c.verifiedAt))||Date.parse(c.verifiedAt)>=Date.parse(restrictedAt)||
    !Number.isFinite(Date.parse(restrictedAt))||Date.parse(restrictedAt)>now())return null;
   // Signature/authentication was verified by the trusted context producer.
   // Decoding here only prevents using a different/expired session as proof.
   const part=c.accessToken.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');
   const claims=JSON.parse(atob(part.padEnd(Math.ceil(part.length/4)*4,'=')));
   if(claims.sub!==userId||claims.role!=='authenticated'||!Number.isFinite(claims.exp)||claims.exp*1000<=now()+30000)return null;
   if(!/^[a-z0-9-]+$/.test(c.bucket)||typeof c.path!=='string'||c.path.length>1024||/[\\\x00-\x1f]/.test(c.path)||c.path.split('/').some(s=>!s||s==='.'||s==='..'))return null;
   const headers={apikey:apiKey,Authorization:'Bearer '+c.accessToken,'Content-Type':'application/json'};
   const request=async(path,body)=>{
    const r=await fetchImpl(base.origin+path,{method:body===undefined?'GET':'POST',headers,body:body===undefined?undefined:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(10000)});
    let data=null;try{data=await r.json();}catch{}return {status:r.status,data};
   };
   const db=await request('/rest/v1/user_profiles?select=user_id&user_id=eq.'+encodeURIComponent(userId));
   if(db.status!==403||db.data?.code!=='42501'||db.data.message!=='account_access_restricted')return null;
   // The Edge handlers call Auth before their DB access guard. A confirmed
   // Auth ban therefore becomes a handler 401, not its account-guard 403.
   // Generic 401/expired JWT/outages must never count as a confirmed ban.
   const auth=await request('/auth/v1/user');
   const banned=auth.status===403&&auth.data?.error_code==='user_banned';
   if(!banned && !(auth.status===200&&auth.data?.id===userId))return null;
   for(const [name,message,loginError] of [['support-contact','account_access_restricted','login_required'],['create-employee-invite','アカウントの利用を停止しています。','authentication required']]){
    const r=await request('/functions/v1/'+name,{});
    if(!(r.status===403&&r.data?.error===message) &&
     !(banned&&r.status===401&&r.data?.error===loginError))return null;
   }
   const path=encodeURIComponent(c.bucket)+'/'+c.path.split('/').map(encodeURIComponent).join('/');
   const read=await request('/storage/v1/object/authenticated/'+path);
   const sign=await request('/storage/v1/object/sign/'+path,{expiresIn:60});
   // The pre-freeze positive control distinguishes an existing accessible
   // object from a random nonexistent path. DB inspection separately checks
   // the restrictive ALL policy and the transaction/server-activity barriers.
   for(const r of [read,sign])if(![400,403,404].includes(r.status)||
    !['403','404'].includes(String(r.data?.statusCode))||
    !['Object not found','new row violates row-level security policy','Unauthorized'].includes(r.data?.message))return null;
   return {userId,jobId,restrictedAt,edgeRequestsBlocked:true,concurrentWritesBlocked:true,newSignedUrlsBlocked:true};
  }catch{return null;}
 };
}
