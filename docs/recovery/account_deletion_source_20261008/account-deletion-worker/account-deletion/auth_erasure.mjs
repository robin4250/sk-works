// Server-only. Authorization is checked against the persisted job, its lease,
// completed prerequisites and remaining restrictive foreign keys.
const isMissing = error => error?.status === 404 && error?.code === 'user_not_found';
export function createAuthErasure({admin,rpc,beforeDelete=async()=>false}) {
 return async job => {
  const permit = await rpc('authorize_account_erasure',{p_id:job.id,p_lease:job.leaseToken});
  if (!permit || permit.user_id !== job.userId) throw Error('erasure_not_authorized');
  const before = await admin.getUserById(job.userId);
  if (isMissing(before.error)) return true; // Retry after successful deletion.
  if (before.error || before.data?.user?.id !== job.userId) throw Error('identity_unconfirmed');
  // A missing account on a retry needs no further mutation. Otherwise the
  // current restriction must be verified immediately before Auth deletion.
  if(await beforeDelete(job)!==true) throw Error('access_restriction_unconfirmed');
  const removed = await admin.deleteUser(job.userId, false);
  if (removed.error && !isMissing(removed.error)) throw Error('auth_delete_unconfirmed');
  const after = await admin.getUserById(job.userId);
  if (!isMissing(after.error)) throw Error('auth_erasure_unconfirmed');
  return true;
 };
}
