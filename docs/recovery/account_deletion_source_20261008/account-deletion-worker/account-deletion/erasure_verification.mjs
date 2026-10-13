// A successful delete request is not proof that data disappeared.
// Recheck Auth, the server's reviewed record inventory and every approved file.
export function createErasureVerification({admin,rpc,readApprovedFiles,verifyAbsent,renew}) {
 return async job=>{
  const auth=await admin.getUserById(job.userId);
  if(auth.error?.status!==404 || auth.error?.code!=='user_not_found')
   throw Error('auth_still_present');
  const records=await rpc('verify_account_deletion_records',{p_id:job.id,p_lease:job.leaseToken});
  if(records?.user_id!==job.userId || records?.inspection_complete!==true
   || records?.personal_rows_remaining!==0 || records?.retained_records_verified!==true)
   throw Error('record_erasure_unconfirmed');
  const plan=await readApprovedFiles(job);
  if(plan?.userId!==job.userId || plan?.digest!==job.reviewedPlanDigest
   || !Array.isArray(plan.files)) throw Error('file_plan_unavailable');
  const buckets=new Map();
  for(const file of plan.files){
   if(file.subjectUserId!==job.userId || file.disposition!=='erase' || file.ownershipVerified!==true)
    throw Error('file_plan_unavailable');
   if(!buckets.has(file.bucket)) buckets.set(file.bucket,new Set());
   buckets.get(file.bucket).add(file.path);
  }
  for(const [bucket,paths] of buckets){
   const list=[...paths];
   for(let i=0;i<list.length;i+=100){
    if(await renew(job)!==true) throw Error('lease_lost');
    if(await verifyAbsent(job,bucket,list.slice(i,i+100))!==true)
     throw Error('file_erasure_unconfirmed');
   }
  }
  return true;
 };
}
