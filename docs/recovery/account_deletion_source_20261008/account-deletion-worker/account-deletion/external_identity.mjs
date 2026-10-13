// Password/phone accounts have no external provider token to revoke.
// A disabled sign-in button does NOT prove older accounts have no OAuth links.
export function createExternalIdentityInspection({admin,providers={}}) {
 return async job=>{
  const result=await admin.getUserById(job.userId);
  const user=result.data?.user;
  if(result.error || user?.id!==job.userId || !Array.isArray(user.identities)
   || user.identities.length===0) throw Error('identity_unconfirmed');
  const external=[];
  for(const identity of user.identities){
   if(!identity || typeof identity.provider!=='string') throw Error('identity_unconfirmed');
   if(['email','phone'].includes(identity.provider)) continue;
   if(typeof providers[identity.provider]!=='function') throw Error('provider_revocation_unavailable');
   external.push(identity);
  }
  // A persisted successful revocation has invalidated its credential. Retrying
  // a later deletion step must not require that same token to work again.
  for(const identity of job.completedSteps?.includes('revokeExternalIdentity') ? [] : external) {
   const inspect=providers[identity.provider].inspect;
   if(typeof inspect==='function' && await inspect(job,identity)!==true)
    throw Error('provider_credential_unconfirmed');
  }
  return external;
 };
}
export function createExternalIdentityRevocation({admin,providers={}}) {
 const inspect=createExternalIdentityInspection({admin,providers});
 return async job=>{
  // Re-inspect at execution too: identities can change after eligibility.
  const external=await inspect(job);
  for(const identity of external){
   if(await providers[identity.provider](job,identity)!==true)
    throw Error('provider_revocation_unconfirmed');
  }
  return true;
 };
}
