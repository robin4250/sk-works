// Current policy evaluation plus calls to BOTH deployed Edge guards.
// No client JWT/positive-control file is required, including after a restart.
// Historical bearer URLs are still verified separately after file erasure.
export function createServerGuardProbe({rpc,origin,serviceKey,fetchImpl=fetch}) {
 const base=new URL(origin);
 if(base.protocol!=='https:'||base.username||base.password||base.pathname!=='/'||base.search||base.hash||!serviceKey||typeof rpc!=='function')throw Error('server_guard_probe_not_configured');
 return async ({userId,jobId,restrictedAt,leaseToken})=>{
  try{
   const r=await rpc('inspect_account_deletion_live_guards',{p_id:jobId,p_lease:leaseToken});
   if(r?.scope!=='data-api-and-rls-only'||r.job_id!==jobId||r.user_id!==userId||r.restricted_at!==restrictedAt||
    !Number.isFinite(Date.parse(restrictedAt))||r.restriction_present!==true||r.auth_ban_confirmed!==true||
    r.data_api_hook_observed!==true||r.data_api_barrier_observed!==true||r.rls_guards_installed!==true||
    r.server_activities_clear!==true||r.storage_guard_denies_subject!==true||r.storage_buckets_private!==true||r.server_guard_denies_subject!==true)return null;
   for(const name of ['support-contact','create-employee-invite']){
    const response=await fetchImpl(base.origin+'/functions/v1/'+name,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),
     headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json','x-sko-deletion-inspection':'v1'},
     body:JSON.stringify({jobId,leaseToken})});
    if(response.status!==200)return null;
    const e=await response.json();
    if(e?.protocol!=='sko-deletion-guard-v1'||e.jobId!==jobId||e.userId!==userId||e.restrictedAt!==restrictedAt||e.accessAllowed!==false)return null;
   }
   return {userId,jobId,restrictedAt,edgeRequestsBlocked:true,concurrentWritesBlocked:true,newSignedUrlsBlocked:true};
  }catch{return null;}
 };
}
