// Read current DB configuration and both running Edge versions. This readiness
// check does not claim that any particular old URL is already inaccessible.
export function createDeploymentProbe({rpc,origin,serviceKey,fetchImpl=fetch}){
 const base=new URL(origin);
 if(base.protocol!=='https:'||base.username||base.password||base.pathname!=='/'||base.search||base.hash||!serviceKey||typeof rpc!=='function')throw Error('deployment_probe_not_configured');
 return async()=>{
  try{
   const r=await rpc('inspect_account_deletion_execution_readiness',{});
   if(r?.scope!=='data-api-and-rls-only'||r.data_api_hook_observed!==true||r.data_api_barrier_observed!==true||r.rls_guards_installed!==true||r.erasure_evidence_ready!==true||r.google_revocation_evidence_ready!==true)return null;
   for(const name of ['support-contact','create-employee-invite']){
    const response=await fetchImpl(base.origin+'/functions/v1/'+name,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json','x-sko-deletion-inspection':'v1'},body:'{"mode":"readiness"}'});
    if(response.status!==200)return null;const e=await response.json();
    if(e?.protocol!=='sko-deletion-guard-v1'||e.mode!=='readiness'||e.dataApiBarrierObserved!==true||e.rlsGuardsInstalled!==true)return null;
   }
   return {edgeGuardsDeployed:true,writeBarriersDeployed:true,erasureEvidenceReady:true};
  }catch{return null;}
 };
}
