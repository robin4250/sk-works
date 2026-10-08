// rpc is a server-only service client. Never instantiate from Flutter or expose
// this store as an authenticated-user endpoint.
export function deletionJobStore(rpc) {
  const advance = (job,action,step=null) => rpc('advance_account_deletion_job', {
    p_id:job.id,p_lease:job.leaseToken,p_action:action,p_step:step,
  });
  return {
    claim: id => rpc('claim_account_deletion_job',{p_id:id}),
    renew: job => advance(job,'renew'),
    checkpoint: (job,step) => advance(job,'checkpoint',step),
    complete: job => advance(job,'complete'),
    fail: (job,step) => advance(job,'fail',step),
  };
}
