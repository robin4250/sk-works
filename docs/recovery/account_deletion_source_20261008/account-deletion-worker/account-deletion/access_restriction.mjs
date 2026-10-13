// Auth suspension alone does not revoke already-issued JWT access tokens.
// The data guard must cover DB/RPC, Storage and server-side posting paths.
const minimumBanMs = 31 * 24 * 60 * 60 * 1000;
export function createAccessRestriction({admin,restrictDataAccess,verifyDataAccessRestricted,renew,now=Date.now}) {
 for(const port of [admin?.getUserById,admin?.updateUserById,restrictDataAccess,verifyDataAccessRestricted,renew]) {
  if(typeof port!=='function') throw Error('incomplete_access_restriction');
 }
 return async job=>{
  if(await renew(job)!==true) throw Error('lease_lost');
  if(await restrictDataAccess(job)!==true) throw Error('data_access_not_restricted');
  const before=await admin.getUserById(job.userId);
  if(before.error || before.data?.user?.id!==job.userId) throw Error('auth_subject_unconfirmed');
  const bannedUntil=Date.parse(before.data.user.banned_until??'');
  if(!Number.isFinite(bannedUntil) || bannedUntil<now()+minimumBanMs){
   if(await renew(job)!==true) throw Error('lease_lost');
   // Keep sign-in blocked until deletion finishes, including delayed retries.
   // Existing longer bans are left intact. Never reset a password or metadata.
   const result=await admin.updateUserById(job.userId,{ban_duration:'876000h'});
   if(result.error) throw Error('auth_restriction_unconfirmed');
  }
  const after=await admin.getUserById(job.userId);
  const confirmedUntil=Date.parse(after.data?.user?.banned_until??'');
  if(after.error || after.data?.user?.id!==job.userId || !Number.isFinite(confirmedUntil)
   || confirmedUntil<now()+minimumBanMs) throw Error('auth_restriction_unconfirmed');
  // Require the data-plane guard after the network operation as well.
  if(await renew(job)!==true) throw Error('lease_lost');
  if(await verifyDataAccessRestricted(job)!==true) throw Error('data_access_not_restricted');
  return true;
 };
}
