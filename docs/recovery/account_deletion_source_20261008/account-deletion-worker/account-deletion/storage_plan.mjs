// Private server ports only. The RPC checks the job lease, completed access
// restriction, immutable plan, subject and digest before returning any paths.
export function storagePlanPorts({rpc,storage,renew}) {
 const readPlan = async (job, operation) => {
  const plan = await rpc(operation, {
   p_id:job.id,p_lease:job.leaseToken,
  });
  if (!plan || plan.userId!==job.userId || plan.digest!==job.reviewedPlanDigest ||
      plan.writesRestricted!==true || !Array.isArray(plan.files)) throw Error('file_plan_unavailable');
  return plan;
 };
 const readApprovedFiles = job => readPlan(job,'read_account_deletion_file_plan');
 return {
  readApprovedFiles,
  readGuardPlan: job => readPlan(job,'inspect_account_deletion_guard_plan'),
  verifyAbsent: async (job,bucket,paths) => {
   if (!Array.isArray(paths) || !paths.length || paths.length>100) return false;
   const plan=await readApprovedFiles(job);
   if (paths.some(path=>!plan.files.some(f=>f.bucket===bucket && f.path===path &&
       f.subjectUserId===job.userId && f.ownershipVerified===true && f.disposition==='erase')))
    return false;
   for (let i=0;i<paths.length;i++) {
    if (i%10===0 && await renew(job)!==true) return false;
    const result=await storage.from(bucket).exists(paths[i]);
    // Permission failures/timeouts are not proof of absence.
    if (result.error || result.data!==false) return false;
   }
   return true;
  },
 };
}
