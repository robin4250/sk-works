// Review-only internal lifecycle. No independent approval, key activation or route.
// The pool must be request-scoped and carry independently verified local claims.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
async function withinRequest({pool,actor,session,requestId},cancel) {
 if(!pool||typeof pool.connect!=='function'||![actor,session,requestId].every(v=>typeof v==='string'&&uuid.test(v)))throw Error('invalid owner request lifecycle');
 const c=await pool.connect();
 try {
  await c.query('begin');
  await c.query("set local lock_timeout = '1s'");
  await c.query("set local statement_timeout = '5s'");
  const identity=await c.query(`select auth.uid() as actor,private.require_reauthentication_session() as session,
   public.is_current_user_master_admin() as master`);
  if(identity.rows.length!==1||identity.rows[0].actor!==actor||identity.rows[0].session!==session||identity.rows[0].master!==true)throw Error('eligible owner session required');
  const initial=await c.query(`select challenge_id,pending_id,device_id,key_sha256 from master_device_enrollment_candidate.owner_approval_requests
   where id=$1 and actor=auth.uid() and actor=$2
    and requester_session=private.require_reauthentication_session() and requester_session=$3`,[requestId,actor,session]);
  if(initial.rows.length!==1)throw Error('original owner request unavailable');
  const r=initial.rows[0];
  // Match issuance lock order: device -> original challenge/pending -> request.
  // Cancellation may withdraw a locked/expired request; it cannot unlock a device.
  const device=await c.query('select id from private.master_devices where id=$1 and master_user_id=$2 for share',[r.device_id,actor]);
  if(device.rows.length!==1)throw Error('owned original device required');
  const source=await c.query(`select ch.id,ch.expires_ms from master_device_enrollment_candidate.key_possession_challenges ch
   join master_device_enrollment_candidate.pending_key_migrations p
    on p.id=$2 and p.actor=ch.actor and p.device_id=ch.device_id and p.key_sha256=ch.key_sha256
   where ch.id=$1 and ch.actor=auth.uid() and ch.actor=$3
    and ch.session_id=private.require_reauthentication_session() and ch.session_id=$4
    and ch.device_id=$5 and ch.key_sha256=$6 and ch.consumed_at is not null and p.status='pending'
    and public.is_current_user_master_admin() for update of ch,p`,
   [r.challenge_id,r.pending_id,actor,session,r.device_id,r.key_sha256]);
  if(source.rows.length!==1)throw Error('original pending key required');
  const locked=await c.query(`select id,key_sha256,expires_ms from master_device_enrollment_candidate.owner_approval_requests
   where id=$1 and actor=auth.uid() and actor=$2
    and requester_session=private.require_reauthentication_session() and requester_session=$3
    and challenge_id=$4 and pending_id=$5 and device_id=$6 and key_sha256=$7
    and expires_ms=$8 and status='awaiting_independent_owner' and public.is_current_user_master_admin() for update`,
   [requestId,actor,session,r.challenge_id,r.pending_id,r.device_id,r.key_sha256,source.rows[0].expires_ms]);
  if(locked.rows.length!==1)throw Error('original owner request changed');
  if(cancel)await c.query(`insert into master_device_enrollment_candidate.owner_approval_request_cancellations(request_id,actor,requester_session)
   values($1,auth.uid(),private.require_reauthentication_session()) on conflict(request_id) do nothing`,[requestId]);
  const state=await c.query(`select exists(select 1 from master_device_enrollment_candidate.owner_approval_request_cancellations
    where request_id=$1 and actor=auth.uid() and actor=$2
     and requester_session=private.require_reauthentication_session() and requester_session=$3) as cancelled,
   $4::float8<=floor(extract(epoch from clock_timestamp())*1000) as expired`,[requestId,actor,session,locked.rows[0].expires_ms]);
  if(state.rows.length!==1)throw Error('owner request state unavailable');
  const status=state.rows[0].cancelled?'cancelled':state.rows[0].expired?'expired':'awaiting_independent_owner';
  await c.query('commit');
  return Object.freeze({id:requestId,status,keySha256:r.key_sha256});
 }catch(error){try{await c.query('rollback');}catch{}throw error;}
 finally{c.release();}
}
export const cancelIndependentOwnerApprovalRequest=args=>withinRequest(args,true);
export const inspectIndependentOwnerApprovalRequest=args=>withinRequest(args,false);
