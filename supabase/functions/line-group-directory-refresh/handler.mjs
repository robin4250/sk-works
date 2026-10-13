export function createDirectoryRefreshHandler({env,fetcher=fetch,now=()=>new Date()}) {
 return async request=>{
  if(request.method!=='POST')return new Response('Method Not Allowed',{status:405});
  const base=env('SUPABASE_URL'),publicKey=env('SUPABASE_ANON_KEY'),serviceKey=env('SUPABASE_SERVICE_ROLE_KEY'),token=env('LINE_CHANNEL_ACCESS_TOKEN');
  const authorization=request.headers.get('authorization');
  if(!authorization?.startsWith('Bearer '))return new Response('Authentication required',{status:401});
  if(!base||!publicKey||!serviceKey||!token)return new Response('Directory configuration unavailable',{status:503});
  const json=async(url,options)=>{const response=await fetcher(url,{...options,redirect:'error',signal:AbortSignal.timeout(10000)});if(!response.ok)throw Error('Request unavailable');return response.json();};
  try {
   const authResponse=await fetcher(`${base}/auth/v1/user`,{headers:{apikey:publicKey,Authorization:authorization},signal:AbortSignal.timeout(10000),redirect:'error'});
   if(authResponse.status===401 || authResponse.status===403)return new Response('Authentication required',{status:401});
   if(!authResponse.ok)throw Error('Authentication unavailable');
   const auth=await authResponse.json();if(!auth?.id)return new Response('Authentication required',{status:401});
   const master=await json(`${base}/rest/v1/rpc/is_current_user_master_admin`,{method:'POST',headers:{apikey:publicKey,Authorization:authorization,'Content-Type':'application/json'},body:'{}'});
   if(master!==true)return new Response('Master permission required',{status:403});
   await json(`${base}/rest/v1/rpc/line_joined_group_workspace`,{method:'POST',headers:{apikey:publicKey,Authorization:authorization,'Content-Type':'application/json'},body:'{}'});
   const input=await request.json().catch(()=>({}));
   const after=input?.after??null;if(after!==null&&(typeof after!=='string'||! /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(after)))return new Response('Invalid cursor',{status:400});
   const headers={apikey:serviceKey,Authorization:`Bearer ${serviceKey}`,'Content-Type':'application/json'};
   const ids=await json(`${base}/rest/v1/rpc/line_known_group_ids`,{method:'POST',headers,body:JSON.stringify({p_after:after})});
   if(!Array.isArray(ids)||ids.length>10)throw Error('Directory unavailable');
   let checked=0,unavailable=0;
   for(const row of ids) {
    const id=row?.line_group_id;
    if(typeof id!=='string')continue;
    try {
     const at=now().toISOString();
     const response=await fetcher(`https://api.line.me/v2/bot/group/${encodeURIComponent(id)}/summary`,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(1500),redirect:'error'});
     // LINE documents 404 when the bot is not a member; authorization/temporary
     // errors cannot be converted into a fabricated departure.
     if(!response.ok && response.status!==404) {unavailable++;continue;}
     const summary=response.ok ? await response.json() : null;
     if(summary && (summary.groupId!==id || typeof summary.groupName!=='string')) {unavailable++;continue;}
     const saved=await fetcher(`${base}/rest/v1/rpc/observe_line_joined_group`,{method:'POST',headers,body:JSON.stringify({p_line_group_id:id,p_display_name:summary?.groupName??null,p_joined:response.ok,p_observed_at:at,p_event_id:`summary:${at}:${id}`}),signal:AbortSignal.timeout(10000),redirect:'error'});
     if(!saved.ok){unavailable++;continue;}checked++;
    } catch {unavailable++;}
   }
   return Response.json({checked,unavailable,next_cursor:ids.length===10?ids.at(-1)?.id:null});
  } catch {return new Response('Directory refresh unavailable',{status:503});}
 };
}
