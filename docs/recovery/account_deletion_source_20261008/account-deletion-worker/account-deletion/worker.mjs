import {createCompletionNotice} from './completion_notice.mjs';
import {processDeletion} from './processor.mjs';
import {deletionJobStore} from './job_store.mjs';
import {storagePlanPorts} from './storage_plan.mjs';
import {createStorageErasure} from './storage_erasure.mjs';
import {createAuthErasure} from './auth_erasure.mjs';
import {createExternalIdentityRevocation,createExternalIdentityInspection} from './external_identity.mjs';
import {createErasureVerification} from './erasure_verification.mjs';
import {officialDocumentReviewBuckets} from './policy.mjs';

// Accept a SERVER-ONLY service client, never a user's Supabase client.
// No HTTP endpoint/schedule: keep disabled until all lifecycle steps are real.
export function createDeletionWorker({client,steps,providers={},sendCompletion,erasureEvidence}) {
 for (const name of ['restrictAccess','verifyAccessRestricted','verifyErasedFileAccess']) {
  if (typeof steps?.[name]!=='function') throw Error('incomplete_worker');
 }
 if (typeof steps?.notifyCompletion!=='function' && typeof sendCompletion!=='function') throw Error('incomplete_worker');
 const rpc=async(name,args)=>{
  const result=await client.rpc(name,args);
  if (result.error) throw Error('deletion_state_unavailable');
  return result.data;
 };
 const store=deletionJobStore(rpc);
 const files=storagePlanPorts({rpc,storage:client.storage,renew:store.renew});
 const defaultNotice = typeof steps?.notifyCompletion !== 'function';
 const ports={
  ...(defaultNotice ? {notifyCompletion:createCompletionNotice({rpc,send:sendCompletion,renew:store.renew})} : {}),
  checkEligibility:job=>rpc('check_account_deletion_eligibility',{
   p_id:job.id,p_lease:job.leaseToken,
  }),
  preserveRequiredRecords:job=>rpc('preserve_account_deletion_company_records',{
   p_id:job.id,p_lease:job.leaseToken,
  }),
  erasePersonalContent:job=>rpc('erase_account_deletion_personal_content',{
   p_id:job.id,p_lease:job.leaseToken,
  }),
  revokeExternalIdentity:createExternalIdentityRevocation({admin:client.auth.admin,providers}),
  verifyErasure:createErasureVerification({admin:client.auth.admin,rpc,...files,renew:store.renew}),
  ...steps,...store,
  erasePersonalFiles:createStorageErasure({storage:client.storage,...files,renew:store.renew,
   beforeDelete:steps.verifyAccessRestricted,evidence:erasureEvidence}),
  eraseAuthAccount:createAuthErasure({admin:client.auth.admin,rpc,beforeDelete:steps.verifyAccessRestricted}),
 };
 if(typeof steps?.revokeExternalIdentity!=='function') {
  const eligibility=ports.checkEligibility;
  const inspect=createExternalIdentityInspection({admin:client.auth.admin,providers});
  ports.checkEligibility=async job=>{
   if(await eligibility(job)!==true) return false;
   // Once Auth was erased, retries continue with final verification/notice.
   if(!job.completedSteps.includes('eraseAuthAccount')) {
    try { await inspect(job); }
    catch(error) {
     // Auth may have been erased while its checkpoint response was lost.
     // Accept absence only at the exact Auth step, with a fresh server permit.
     if(job.completedSteps.length!==5) throw error;
     const permit=await rpc('authorize_account_erasure',{p_id:job.id,p_lease:job.leaseToken});
     if(permit?.user_id!==job.userId) throw error;
     const result=await client.auth.admin.getUserById(job.userId);
     if(result.error?.status!==404 || result.error?.code!=='user_not_found') throw error;
    }
   }
   return true;
  };
 }
 if (defaultNotice) {
  const eligibility=ports.checkEligibility;
  ports.checkEligibility=async job=> await eligibility(job)===true &&
    await rpc('prepare_account_deletion_notice',{p_id:job.id,p_lease:job.leaseToken})===true;
 }
 // A recorded restriction is not current evidence after a retry or outage.
 // These checks supplement server-side write barriers, not replace them.
 for(const name of ['preserveRequiredRecords','revokeExternalIdentity','erasePersonalContent','erasePersonalFiles','eraseAuthAccount']) {
  const operation=ports[name];
  ports[name]=async(job,...args)=>{
   // Auth's own adapter checks the live guard immediately before mutation.
   // A server-authorized already-absent retry performs no Auth mutation.
   if(name!=='eraseAuthAccount' && await steps.verifyAccessRestricted(job)!==true)
    throw Error('access_restriction_unconfirmed');
   // Check before row/reference changes, not only at the later Storage step.
   // Recheck resumed jobs too. This covers listed files; inventory completeness
   // and per-record retention remain separate release requirements.
   const plan=await files.readGuardPlan(job);
   if(plan.files.some(f=>officialDocumentReviewBuckets.includes(f?.bucket)))
    throw Error('official_document_retention_unresolved');
   return operation(job,...args);
  };
 }
 // File absence alone is not proof that a previously served bearer URL is
 // inaccessible. Check the reviewed plan after file removal, on Auth retries,
 // and immediately before the final completion/notice stages.
 for(const name of ['eraseAuthAccount','verifyErasure','notifyCompletion']) {
  const operation=ports[name];
  ports[name]=async(job,...args)=>{
   if(await steps.verifyErasedFileAccess(job)!==true)
    throw Error('erased_file_access_unconfirmed');
   return operation(job,...args);
  };
 }
 return id=>processDeletion(id,ports);
}
