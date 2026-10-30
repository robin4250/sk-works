import fs from 'node:fs/promises';
export async function verifySiteOrderApprovalOperations(db,c){
 const {id,UA,UB,UC,q,check,deny,signed,send,recipientTrade,recipientPeer,openNativePeer}=c;
 const sql=await fs.readFile('docs/review/site-order-package-flow/approval-operation.sql.review-only','utf8');
 await db.exec(sql);
 const make=async n=>{
  await signed(UA);await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
  const packet=await send(id(n));await signed(UB);
  const preview=await q('select site_order_package_private.preview_approval($1,$2,$3,$4) v',[packet.package_id,recipientTrade,recipientPeer.connection_fingerprint,id(n+1)]);
  return {packet,preview,request:id(n+2)};
 };
 const reconcile=(x,connection=db)=>connection.query('select site_order_package_private.reconcile_approval($1,$2,$3) v',[x.packet.package_id,x.preview.preview_id,x.request]).then(r=>r.rows[0].v);
 const approve=(x,connection=db)=>connection.query('select site_order_package_private.approve_operation($1,$2,$3,true,$4) v',[x.preview.preview_id,x.preview.body_hash,x.preview.own_seal.seal_hash,x.request]).then(r=>r.rows[0].v);
 const snapshot=()=>q(`select jsonb_build_object('sites',(select count(*) from sites),'docs',(select count(*) from trade_document_consent_private.documents),'ready',(select count(*) from site_order_package_private.ready_reply_jobs)) v`);
 const cancelled=await make(12400),before=await snapshot();
 check((await reconcile(cancelled)).operation_state,'cancelled');
 check((await reconcile(cancelled)).operation_state,'cancelled');
 check(await snapshot(),before);
 await deny(()=>approve(cancelled),/operation_cancelled/);
 check(await snapshot(),before);
 await deny(()=>reconcile({...cancelled,request:id(12409)}),/operation_request_changed/);
 await signed(UC);await deny(()=>reconcile(cancelled),/own_preview_required/);
 await signed(UB);await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 check((await reconcile(cancelled)).operation_state,'cancelled');
 await deny(()=>approve(cancelled),/master_feature_disabled/);
 const accepted=await make(12410),queued=await approve(accepted);
 check(queued.status,'approved_reply_queued');check(await approve(accepted),queued);
 const saved=await snapshot();check((await reconcile(accepted)).operation_state,'accepted');check(await snapshot(),saved);
 // A fresh live SID may read the exact prior actor's result but cannot reuse
 // expired/other-session seal consent to create another signature/job.
 const sid=await q('select id v from auth.sessions where user_id=$1 limit 1',[UB]),newSid=id(12419);
 await db.query('insert into auth.sessions select (jsonb_populate_record(null::auth.sessions,to_jsonb(s)||jsonb_build_object(\'id\',$1::uuid))).* from auth.sessions s where id=$2',[newSid,sid]);
 await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:UB,role:'authenticated',session_id:newSid})]);
 check((await reconcile(accepted)).operation_state,'accepted');await deny(()=>approve(accepted),/own_preview_required/);
 await signed(UB);
 await deny(()=>db.exec('truncate site_order_package_private.approval_operations'),/immutable/);
 for(const role of ['anon','authenticated','service_role']){
  await db.exec('set role '+role);await deny(()=>reconcile(accepted),/permission denied/);await db.exec('reset role');
 }
 if(openNativePeer){
  const claims=await q('select auth.jwt() v'),actorId=await q('select auth.uid() v');
  const peer=await openNativePeer();
  try{
   await peer.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[actorId,JSON.stringify(claims)]);
   for(const mode of ['accepted','cancelled']){
    const target=await make(mode==='accepted'?12420:12430);
    await db.exec('begin');
    try{
     if(mode==='accepted')await approve(target);else await reconcile(target);
     const held=await q('select pg_backend_pid() v');
     const pending=(mode==='accepted'?reconcile(target,peer):approve(target,peer)).then(value=>({value}),error=>({error}));
     let waited=false;
     for(let n=0;n<200&&!waited;n++){
      waited=await q("select exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock' and $2=any(pg_blocking_pids(pid))) v",[peer.processID,held]);
      if(!waited)await new Promise(resolve=>setTimeout(resolve,5));
     }
     check(waited,true);await db.exec('commit');const outcome=await pending;
     if(mode==='accepted')check(outcome.value?.operation_state,'accepted');
     else check(/operation_cancelled/.test(outcome.error?.message),true);
    }finally{await db.exec('rollback');}
   }
  }finally{await peer.end();}
 }
 const projection=await q('select site_order_package_private.package_detail($1) v',[accepted.packet.package_id]);
 check(Object.hasOwn(projection.site_projection,'notes'),false);
 check(typeof projection.site_projection.name,'string');
 console.log(JSON.stringify({status:'passed',approval_operation_barriers:true,native_waits:openNativePeer?2:0,real_auth:false,production_changed:false}));
}
