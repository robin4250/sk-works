// Internal read-only branch. A user JWT cannot invoke this branch. The subject
// is loaded from a leased server job, never from a caller-supplied user ID.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply=(data,status)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export function createDeletionInspection({serviceKey,rpc,checkAccess}) {
 return async req=>{
  if(req.headers.get('x-sko-deletion-inspection')!=='v1')return null;
  if(!serviceKey||req.headers.get('authorization')!=='Bearer '+serviceKey)return reply({error:'forbidden'},403);
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  try{
   const raw=await req.text();if(raw.length>256)return reply({error:'invalid_request'},400);
   const p=JSON.parse(raw);
   if(p?.mode==='readiness' && Object.keys(p).length===1){
    const r=await rpc('inspect_account_deletion_access_controls',{});
    if(r?.data_api_hook_observed!==true||r.data_api_barrier_observed!==true||r.rls_guards_installed!==true)throw Error('not_ready');
    return reply({protocol:'sko-deletion-guard-v1',mode:'readiness',dataApiBarrierObserved:r.data_api_barrier_observed,rlsGuardsInstalled:r.rls_guards_installed},200);
   }
   if(!uuid.test(p?.jobId??'')||!uuid.test(p?.leaseToken??'')||Object.keys(p).some(k=>!['jobId','leaseToken'].includes(k)))return reply({error:'invalid_request'},400);
   const r=await rpc('inspect_account_deletion_live_guards',{p_id:p.jobId,p_lease:p.leaseToken});
   if(r?.job_id!==p.jobId||!uuid.test(r.user_id??'')||r.restriction_present!==true||r.auth_ban_confirmed!==true||!Number.isFinite(Date.parse(r.restricted_at)))throw Error('not_restricted');
   const allowed=await checkAccess(r.user_id);
   if(allowed!==false)throw Error('not_restricted');
   return reply({protocol:'sko-deletion-guard-v1',jobId:p.jobId,userId:r.user_id,restrictedAt:r.restricted_at,accessAllowed:allowed},200);
  }catch{return reply({error:'inspection_unavailable'},503);}
 };
}
