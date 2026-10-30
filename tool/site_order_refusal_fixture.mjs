import fs from 'node:fs/promises';
export async function verifySiteOrderRefusal(db,c){
 const {id,UA,UB,UC,q,check,deny,signed,send,recipientTrade,recipientPeer,openNativePeer,second,queued,renderer}=c;
 await db.exec(await fs.readFile('docs/review/site-order-package-flow/refusal.sql.review-only','utf8'));
 const make=async n=>{await signed(UA);await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");const packet=await send(id(n));await signed(UB);return {...packet,request_id:id(n+1)};};
 const refuse=(p,connection=db)=>connection.query(`with refused as materialized(select site_order_package_private.refuse_order($1,$2,true) v)
 select v||jsonb_build_object('notifications',site_order_package_private.dispatch_refusal_notifications($1)) v from refused`,[p.package_id,p.request_id]).then(r=>r.rows[0].v);
 const reconcile=p=>q('select site_order_package_private.reconcile_refusal($1,$2) v',[p.package_id,p.request_id]);
 const stable=()=>q(`select jsonb_build_object('sites',(select count(*) from sites),'docs',(select count(*) from trade_document_consent_private.documents),'ready',(select count(*) from site_order_package_private.ready_reply_jobs),'originals',(select count(*) from site_order_artifact_private.pdf_records)) v`);
 const target=await make(12500),before=await stable();
 await deny(()=>q('select site_order_package_private.refuse_order($1,$2,false) v',[target.package_id,target.request_id]),/explicit_refusal_confirmation/);
 await signed(UA);await deny(()=>refuse(target),/received_package_not_found/);await signed(UC);await deny(()=>refuse(target),/received_package_not_found/);await signed(UB);
 await db.exec("create function pg_temp.reject_refusal_notice()returns trigger language plpgsql as $$begin raise exception 'fixture_refusal_notice_failure';end$$;create trigger fixture_refusal_notice before insert on public.app_notifications for each row execute function pg_temp.reject_refusal_notice()");
 await db.exec('begin');try{await deny(()=>refuse(target),/fixture_refusal_notice_failure/);}finally{await db.exec('rollback');}
 check(await q('select count(*)::int v from site_order_package_private.refusals'),0);
 check(await q('select status v from private.site_share_inbox where data_item_id=$1',[target.data_item_id]),'pending');
 check(await stable(),before);await db.exec('drop trigger fixture_refusal_notice on public.app_notifications');
 const rejected=await refuse(target);check(rejected.status,'rejected');check(rejected.notifications.app_inbox_inserted>0,true);check(await stable(),before);
 const notices=await q('select count(*)::int v from public.app_notifications');
 check((await refuse(target)).notifications.app_inbox_inserted,0);check(await q('select count(*)::int v from public.app_notifications'),notices);
 check((await reconcile(target)).operation_state,'accepted');
 check(await q('select status v from private.site_share_inbox where data_item_id=$1',[target.data_item_id]),'rejected');
 await deny(()=>refuse({...target,request_id:id(12502)}),/refusal_request_changed/);
 await deny(()=>q('select site_order_package_private.approve_order($1,$2,$3,$4) v',[target.package_id,recipientTrade,recipientPeer.connection_fingerprint,id(12503)]),/pending_inbox_required/);
 check((await q('select site_order_package_private.package_decision_detail($1) v',[target.package_id])).rejected,true);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 check((await reconcile(target)).operation_state,'accepted');await deny(()=>refuse(target),/master_feature_disabled/);
 await signed(UA);check((await q('select site_order_package_private.package_decision_detail($1) v',[target.package_id])).rejected,true);
 const original=await q("select site_order_package_private.archive_original($1,'order') v",[target.package_id]);check(Buffer.from(original).subarray(0,5).toString(),'%PDF-');
 const cancelled=await make(12510);check((await reconcile(cancelled)).operation_state,'cancelled');
 await deny(()=>refuse(cancelled),/operation_cancelled/);
 const received=await make(12520);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await (await import('./site_order_http_jwt_fixture.mjs')).verifySiteOrderHttpJwt(db,{id,UA,UB,UC,q,check,second,queued,renderer,openNativePeer,refusal:received});
 await signed(UB);
 for(const t of ['refusals','refusal_operations','refusal_notice_receipts'])await deny(()=>db.exec('truncate site_order_package_private.'+t+' cascade'),/immutable/);
 for(const role of ['anon','authenticated','service_role']){
 await db.exec('set role '+role);await deny(()=>refuse(target),/permission denied/);await db.exec('reset role');
 }
 // Both decisions share the existing package approval lock; rejection never
 // races past a concurrently committed site/acceptance creation.
 if(openNativePeer){
  const race=await make(12530),preview=await q('select site_order_package_private.preview_approval($1,$2,$3,$4) v',[race.package_id,recipientTrade,recipientPeer.connection_fingerprint,id(12532)]);
  const claims=await q('select auth.jwt() v'),uid=await q('select auth.uid() v'),peer=await openNativePeer();
  try{
   await peer.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[uid,JSON.stringify(claims)]);
   await db.exec('begin');
   try{
    await q('select site_order_package_private.approve_operation($1,$2,$3,true,$4) v',[preview.preview_id,preview.body_hash,preview.own_seal.seal_hash,id(12533)]);
    const holder=await q('select pg_backend_pid() v');const pending=refuse(race,peer).then(value=>({value}),error=>({error}));
    let waited=false;for(let n=0;n<200&&!waited;n++){
    waited=await q("select exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock' and $2=any(pg_blocking_pids(pid))) v",[peer.processID,holder]);if(!waited)await new Promise(resolve=>setTimeout(resolve,5));}
    check(waited,true);await db.exec('commit');check(/approved_order_cannot_be_refused/.test((await pending).error?.message),true);
   }finally{await db.exec('rollback');}
  }finally{await peer.end();}
 }
 console.log(JSON.stringify({status:'passed',refusal_atomic_notifications:true,native_decision_waits:openNativePeer?1:0,production_changed:false,device_push:false}));
}
