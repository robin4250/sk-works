// Disposable Auth surroundings only. Real SQL locks and actual canonical PDF
// bytes are exercised; this is not a live GoTrue or production claim.
export async function verifyReplyRecoveryRaces(db,c){
 const {id,UA,UB,q,check,deny,signed,send,recipientTrade,recipientPeer,renderer,openNativePeer}=c;
 const primarySid=id(15003);
 const claims=sid=>({sub:UB,role:'authenticated',session_id:sid});
 const use=async(connection,sid)=>connection.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[UB,JSON.stringify(claims(sid))]);
 const make=async n=>{
  await signed(UA);
  const packet=await send(id(n));
  await use(db,primarySid);
  const approval=await q('select site_order_package_private.preview_approval($1,$2,$3,$4) v',[packet.package_id,recipientTrade,recipientPeer.connection_fingerprint,id(n+1)]);
  const ready=await q('select site_order_package_private.approve_with_consent($1,$2,$3,true,$4) v',[approval.preview_id,approval.body_hash,approval.own_seal.seal_hash,id(n+2)]);
  const sid=id(n+3);
  await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid,UB]);
  await use(db,sid);
  const preview=await q('select site_order_package_private.preview_reply_recovery($1,$2) v',[packet.package_id,id(n+4)]);
  return {packet,ready,preview,sid,request:id(n+5)};
 };
 const confirm=(x,connection=db)=>connection.query('select site_order_package_private.confirm_reply_recovery($1,$2,$3,$4,true,$5) v',
  [x.preview.preview_id,x.preview.body_hash,x.preview.render_hash,x.preview.seal_hash,x.request]).then(r=>r.rows[0].v);
 const reconcile=(x,connection=db)=>connection.query('select site_order_package_private.reconcile_reply_recovery($1,$2,$3) v',
  [x.packet.package_id,x.preview.preview_id,x.request]).then(r=>r.rows[0].v);
 const deliver=(x,connection=db)=>connection.query('select site_order_package_private.deliver_recovered_acceptance($1,$2,$3,$4) v',
  [x.packet.package_id,x.original.receipt_id,x.request,x.lease.lease_id]).then(r=>r.rows[0].v);
 const stageOriginal=async x=>{
  x.lease=await confirm(x);
  const pdf=await renderer(x.preview.evidence);
  x.original=await q('select site_order_package_private.register_recovered_pdf($1,$2,$3) v',[x.ready.job_id,pdf,x.lease.lease_id]);
 };
 // A separate old session's expiry metadata may be in the past while the new
 // caller's SID is live. The fixture actor's expiry logic is synthetic; row
 // deletion in the preceding test proves revoked-old-SID recovery separately.
 await db.exec('alter table auth.sessions add column if not exists not_after timestamptz');
 const expired=await make(15100);
 await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 minute' where id=$1",[primarySid]);
 check(await q('select not_after<clock_timestamp() v from auth.sessions where id=$1',[primarySid]),true);
 await deny(()=>q('select site_order_package_private.ready_reply($1) v',[expired.packet.package_id]),/exact_own_reply_job/);
 const expiredLease=await confirm(expired);
 const {processRecoveredSiteOrderReply}=await import('./site_order_canonical_core.mjs');
 check((await processRecoveredSiteOrderReply(db,expired.packet.package_id,expiredLease.lease_id,renderer,claims(expired.sid))).status,'recipient_stored');
 check(await q('select session_id v from site_order_artifact_private.render_jobs where id=$1',[expired.ready.job_id]),primarySid);
 await db.query('update auth.sessions set not_after=null where id=$1',[primarySid]);

 let nativeWaits=0;
 if(openNativePeer){
  const peer=await openNativePeer();
  const waitFor=async held=>{
   let waited=false;
   for(let n=0;n<200&&!waited;n++){
    waited=await q("select exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock' and $2=any(pg_blocking_pids(pid))) v",[peer.processID,held]);
    if(!waited)await new Promise(resolve=>setTimeout(resolve,5));
   }
   check(waited,true);nativeWaits++;
  };
  try{
   for(const mode of ['confirmed_first','cancelled_first']){
    const x=await make(mode==='confirmed_first'?15120:15130);
    await use(peer,x.sid);
    await db.exec('begin');
    try{
     if(mode==='confirmed_first')await confirm(x);else await reconcile(x);
     const held=await q('select pg_backend_pid() v');
     const pending=(mode==='confirmed_first'?reconcile(x,peer):confirm(x,peer)).then(value=>({value}),error=>({error}));
     await waitFor(held);await db.exec('commit');
     const result=await pending;
     if(mode==='confirmed_first'){
      // A confirmation is not delivery; serialized recovery cancels this
      // unsent lease and a late exact confirmation must not claim success.
      check(result.value?.operation_state,'cancelled');
      await deny(()=>confirm(x),/operation_retired/);
     }else{
      check(/operation_retired/.test(result.error?.message),true);
      check(await q('select count(*)::int v from site_order_package_private.reply_recovery_leases where preview_id=$1',[x.preview.preview_id]),0);
     }
    }finally{await db.exec('rollback');}
   }
   for(const mode of ['delivered_first','cancelled_first']){
    const x=await make(mode==='delivered_first'?15140:15150);
    await stageOriginal(x);await use(peer,x.sid);
    await db.exec('begin');
    try{
     if(mode==='delivered_first')await deliver(x);else await reconcile(x);
     const held=await q('select pg_backend_pid() v');
     const pending=(mode==='delivered_first'?reconcile(x,peer):deliver(x,peer)).then(value=>({value}),error=>({error}));
     await waitFor(held);await db.exec('commit');
     const result=await pending;
     if(mode==='delivered_first'){
      check(result.value?.operation_state,'accepted');
      check(result.value?.reply_recipient_stored,true);
     }else{
      check(/recovery_lease/.test(result.error?.message),true);
      check(await q('select count(*)::int v from site_order_package_private.acceptance_deliveries where package_id=$1',[x.packet.package_id]),0);
     }
    }finally{await db.exec('rollback');}
   }
  }finally{await peer.end();}
 }
 if(openNativePeer)check(nativeWaits,4);
 console.log(JSON.stringify({reply_recovery_new_barriers:true,native_observed_waits:nativeWaits,
  expired_old_sid_metadata:true,expiry_auth_surroundings_synthetic:true,real_gotrue:false,production_changed:false}));
}
