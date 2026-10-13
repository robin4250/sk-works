// Server-only adapter. readApprovedFiles must load an immutable, reviewed plan
// from private storage, validate its digest and confirm writes are restricted.
// Never construct that result from a user's request body or a Storage listing.
import {officialDocumentReviewBuckets} from './policy.mjs';
const allowedBuckets = new Set([
 'profile-photos','worker-documents','qualification-certificates',
 'employee-onboarding-documents','attendance-evidence','chat-attachments',
 'communication-albums','communication-notes',
]);
const validPath = p => typeof p === 'string' && p.length > 0 && p.length <= 1024 &&
 !p.startsWith('/') && !p.includes('\\') && !/[\x00-\x1f]/.test(p) &&
 p.split('/').every(s=>s && s!=='.' && s!=='..');
export function createStorageErasure({storage,readApprovedFiles,verifyAbsent,renew,beforeDelete,evidence}) {
 if(typeof beforeDelete!=='function')throw Error('storage_access_guard_missing');
 return async job => {
  const plan = await readApprovedFiles(job);
  if (!plan || plan.userId!==job.userId || plan.digest!==job.reviewedPlanDigest ||
      plan.writesRestricted!==true || !Array.isArray(plan.files)) throw Error('invalid_file_plan');
  const groups = new Map(); const seen = new Set();
  // Validate the WHOLE plan before deleting anything.
  for (const f of plan.files) {
   if(officialDocumentReviewBuckets.includes(f?.bucket))
    throw Error('official_document_retention_unresolved');
   if (!allowedBuckets.has(f.bucket) || !validPath(f.path) || f.subjectUserId!==job.userId ||
       f.disposition!=='erase' || f.ownershipVerified!==true) throw Error('invalid_file_target');
   const key=JSON.stringify([f.bucket,f.path]);if(seen.has(key)) continue;seen.add(key);
   if(!groups.has(f.bucket))groups.set(f.bucket,[]);groups.get(f.bucket).push(f.path);
  }
  if(evidence && await evidence.prepare(job,plan)!==true)throw Error('erasure_evidence_unconfirmed');
  for(const [bucket,paths] of groups) {
   for(let offset=0;offset<paths.length;offset+=100) {
    if(await renew(job)!==true)throw Error('lease_lost');
    // Recheck for every batch, including retries. The initial plan's flag is
    // historical evidence and cannot authorize later batches by itself.
    if(await beforeDelete(job)!==true)throw Error('access_restriction_unconfirmed');
    const batch=paths.slice(offset,offset+100);
    // Storage API removes actual objects; never delete storage.objects via SQL.
    const result=await storage.from(bucket).remove(batch);
    if(result.error)throw Error('storage_delete_unconfirmed');
    if(await verifyAbsent(job,bucket,batch)!==true)throw Error('storage_still_present');
    if(evidence && await evidence.recordRemoval(job,bucket,batch)!==true)throw Error('erasure_evidence_unconfirmed');
   }
  }
  return true;
 };
}
