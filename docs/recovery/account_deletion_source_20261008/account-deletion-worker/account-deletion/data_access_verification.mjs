// Actual DB inspection plus mandatory probes for paths PostgreSQL cannot see.
// Authenticated access/new URL creation must stop before erasure. Existing
// bearer URL access is checked after object removal, before Auth removal and
// again before completion. Never substitute elapsed time or a constant true.
export function createDataAccessVerification({rpc,probeDeployment,probeSubject,probeErasedFiles}) {
 if([rpc,probeDeployment,probeSubject,probeErasedFiles].some(p=>typeof p!=='function'))
  throw Error('access_probes_missing');
 const databaseReady=r=>r?.scope==='data-api-and-rls-only' &&
  r.data_api_hook_observed===true && r.data_api_barrier_observed===true && r.rls_guards_installed===true;
 return {
  verifyDeploymentReady:async()=>{
   try {
    if(!databaseReady(await rpc('inspect_account_deletion_access_controls',{})))return false;
    const p=await probeDeployment();
    return p?.edgeGuardsDeployed===true && p.writeBarriersDeployed===true &&
     p.erasureEvidenceReady===true;
   }catch{return false;}
  },
  verifyErasedFileAccess:async job=>{
   try {
    const plan=await rpc('read_account_deletion_file_plan',{p_id:job.id,p_lease:job.leaseToken});
    if(plan?.userId!==job.userId || plan.digest!==job.reviewedPlanDigest ||
      plan.writesRestricted!==true || !Array.isArray(plan.files))return false;
    const p=await probeErasedFiles({userId:job.userId,jobId:job.id,planDigest:plan.digest,files:plan.files,leaseToken:job.leaseToken});
    return p?.userId===job.userId && p.jobId===job.id && p.planDigest===plan.digest &&
      p.allObjectsAbsent===true && p.existingSignedUrlsInvalidated===true;
   }catch{return false;}
  },
  verifyDataAccessRestricted:async job=>{
   try {
    const r=await rpc('inspect_account_deletion_subject_access',{p_id:job.id,p_lease:job.leaseToken});
    if(!databaseReady(r) || r.user_id!==job.userId || r.restriction_present!==true ||
     r.auth_ban_confirmed!==true || r.server_activities_clear!==true || typeof r.restricted_at!=='string' ||
     !Number.isFinite(Date.parse(r.restricted_at)))return false;
    const p=await probeSubject({userId:job.userId,jobId:job.id,restrictedAt:r.restricted_at,leaseToken:job.leaseToken});
    return p?.userId===job.userId && p.jobId===job.id && p.restrictedAt===r.restricted_at &&
     p.edgeRequestsBlocked===true &&
     p.concurrentWritesBlocked===true && p.newSignedUrlsBlocked===true;
   }catch{return false;}
  },
 };
}
