import {createDeletionWorker} from './worker.mjs';
import {createAccessRestriction} from './access_restriction.mjs';
import {createConfiguredCompletionSender} from './completion_sender.mjs';
import {deletionJobStore} from './job_store.mjs';
import {createDataAccessVerification} from './data_access_verification.mjs';
import {createGoogleIdentityRevocation} from './google_revocation.mjs';
import {createGoogleCredentialStore} from './google_credential_store.mjs';
import {createErasedFileProbe} from './erased_file_probe.mjs';
import {createErasureEvidence} from './erasure_evidence.mjs';
import {createSubjectAccessProbe} from './subject_access_probe.mjs';
import {createServerGuardProbe} from './server_guard_probe.mjs';
import {createDeploymentProbe} from './deployment_probe.mjs';
import {createGoogleRevocationEvidence} from './google_revocation_evidence.mjs';

// Server-only assembly. Intentionally has no public HTTP route or scheduler.
// The data-plane verifier must perform real deployment/access checks; a DB
// restriction row or successful Auth ban alone is not sufficient evidence.
export function createConfiguredDeletionWorker({client,env,probeDeployment,probeSubject,readSubjectContext,probeErasedFiles,readErasureEvidence,providers={},readGoogleCredential,fetchImpl=fetch}) {
 if(typeof env!=='function' || env('ACCOUNT_DELETION_WORKER_ENABLED')!=='true')
  throw Error('deletion_worker_disabled');
 const rpc=async(name,args)=>{
  const result=await client.rpc(name,args);
  if(result.error) throw Error('deletion_state_unavailable');
  return result.data;
 };
 if(probeDeployment===undefined) {
  probeDeployment=createDeploymentProbe({rpc,origin:env('SUPABASE_URL'),serviceKey:env('SUPABASE_SERVICE_ROLE_KEY'),fetchImpl});
 }
 if(readSubjectContext!==undefined) {
  if(probeSubject!==undefined)throw Error('duplicate_subject_probe');
  probeSubject=createSubjectAccessProbe({origin:env('SUPABASE_URL'),apiKey:env('SUPABASE_ANON_KEY'),readContext:readSubjectContext,fetchImpl});
 }
 if(probeSubject===undefined) {
  probeSubject=createServerGuardProbe({rpc,origin:env('SUPABASE_URL'),serviceKey:env('SUPABASE_SERVICE_ROLE_KEY'),fetchImpl});
 }
 let erasureEvidence;
 if(readErasureEvidence===undefined && probeErasedFiles===undefined && env('ACCOUNT_DELETION_CREDENTIAL_KEY')) {
  erasureEvidence=createErasureEvidence({rpc,storage:client.storage,keyHex:env('ACCOUNT_DELETION_CREDENTIAL_KEY'),
   origin:env('SUPABASE_URL'),fetchImpl});
  readErasureEvidence=erasureEvidence.readEvidence;
 }
 if(readErasureEvidence!==undefined) {
  if(probeErasedFiles!==undefined)throw Error('duplicate_erased_file_probe');
  probeErasedFiles=createErasedFileProbe({storage:client.storage,readEvidence:readErasureEvidence,
   origin:env('SUPABASE_URL'),fetchImpl});
 }
 const {verifyDeploymentReady,verifyDataAccessRestricted,verifyErasedFileAccess}=createDataAccessVerification({rpc,probeDeployment,probeSubject,probeErasedFiles});
 const store=deletionJobStore(rpc);
 const sendCompletion=createConfiguredCompletionSender({env,fetchImpl});
 const verify=async job=>await verifyDataAccessRestricted(job)===true;
 const restrictAccess=createAccessRestriction({admin:client.auth.admin,renew:store.renew,
  restrictDataAccess:job=>rpc('restrict_account_deletion_data_access',{
   p_id:job.id,p_lease:job.leaseToken,
  }),verifyDataAccessRestricted:verify,
 });
 const connectedProviders={...providers};
 if(readGoogleCredential===undefined && env('ACCOUNT_DELETION_CREDENTIAL_KEY')) {
  readGoogleCredential=createGoogleCredentialStore({rpc,
   keyHex:env('ACCOUNT_DELETION_CREDENTIAL_KEY'),clientId:env('GOOGLE_SIGN_IN_CLIENT_ID'),
   clientSecret:env('GOOGLE_SIGN_IN_CLIENT_SECRET'),fetchImpl,
  }).readCredential;
 }
 if(readGoogleCredential!==undefined) {
  if(connectedProviders.google) throw Error('duplicate_google_revocation_adapter');
  connectedProviders.google=createGoogleIdentityRevocation({
   clientId:env('GOOGLE_SIGN_IN_CLIENT_ID'),clientSecret:env('GOOGLE_SIGN_IN_CLIENT_SECRET'),
   readCredential:readGoogleCredential,fetchImpl,
   ...(env('ACCOUNT_DELETION_CREDENTIAL_KEY') ? {revocationEvidence:createGoogleRevocationEvidence({
    rpc,keyHex:env('ACCOUNT_DELETION_CREDENTIAL_KEY'),clientId:env('GOOGLE_SIGN_IN_CLIENT_ID'),
   })} : {}),
  });
 }
 const worker=createDeletionWorker({client,providers:connectedProviders,sendCompletion,erasureEvidence,steps:{restrictAccess,verifyAccessRestricted:verify,verifyErasedFileAccess}});
 return async id=>{
  // Readiness is different from the per-account freeze, which does not exist
  // before restrictAccess runs. Neither check may silently substitute for it.
  try { if(await verifyDeploymentReady()!==true) return {status:'deployment_not_ready'}; }
  catch { return {status:'deployment_not_ready'}; }
  return worker(id);
 };
}
