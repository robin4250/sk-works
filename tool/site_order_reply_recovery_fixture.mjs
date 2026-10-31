// Disposable SQL composition. Auth surroundings remain synthetic.
import fs from 'node:fs/promises';
export async function verifyReplyRecovery(db,c){
 const {id,UA,UB,UC,q,check,deny,signed,send,recipientTrade,recipientPeer,renderer,openNativePeer}=c;
 const originals=()=>q(`select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p where p.oid in(
 'site_order_manager_private.register_canonical_pdf(uuid,bytea)'::regprocedure,
 'site_order_package_private.deliver_acceptance(uuid,uuid,uuid)'::regprocedure,
 'site_order_package_private.ready_reply(uuid)'::regprocedure,
 'site_order_manager_private.decide(uuid,integer,uuid,integer,text,text,text,boolean,uuid)'::regprocedure)`);
 const before=await originals();
 await db.exec(await fs.readFile('docs/review/site-order-package-flow/reply-recovery.sql.review-only','utf8'));
 check(await originals(),before);
 await signed(UA);await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 const incoming=await send(id(15000));
 await signed(UB);await db.query("update company_members set role='manager' where user_id=$1",[UB]);
 const review=await q('select site_order_package_private.preview_approval($1,$2,$3,$4) v',[incoming.package_id,recipientTrade,recipientPeer.connection_fingerprint,id(15001)]);
 const ready=await q('select site_order_package_private.approve_with_consent($1,$2,$3,true,$4) v',[review.preview_id,review.body_hash,review.own_seal.seal_hash,id(15002)]);
 const newSid=id(15003);
 const frozen=await q(`select jsonb_build_object('job',to_jsonb(j),'consents',(select jsonb_agg(to_jsonb(c)) from trade_document_consent_private.consents c where c.document_id=j.document_id)) v
 from site_order_artifact_private.render_jobs j where id=$1`,[ready.job_id]);
 const oldSid=frozen.job.session_id;
 await db.query('insert into auth.sessions values($1,$2)',[newSid,UB]);
 const claims={sub:UB,role:'authenticated',session_id:newSid};
 const useNew=async()=>{await db.query("select set_config('test.uid',$1,false)",[UB]);await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify(claims)]);};
 await useNew();
 // The original SID is actually revoked, not merely different from the caller.
 // Only the disposable Auth surroundings change; original job/consent stay frozen.
 await db.query('delete from auth.sessions where id=$1',[oldSid]);
 check(await q('select exists(select 1 from auth.sessions where id=$1) v',[oldSid]),false);
 await deny(()=>q('select site_order_package_private.ready_reply($1) v',[incoming.package_id]),/exact_own_reply_job/);
 const preview=await q('select site_order_package_private.preview_reply_recovery($1,$2) v',[incoming.package_id,id(15004)]);
 check(preview.body_hash,frozen.job.body_hash);check(preview.render_hash,frozen.job.render_hash);
 check(preview.body,frozen.job.evidence.body);
 const confirm=(hash=preview.body_hash,yes=true)=>q('select site_order_package_private.confirm_reply_recovery($1,$2,$3,$4,$5,$6) v',
 [preview.preview_id,hash,preview.render_hash,preview.seal_hash,yes,id(15005)]);
 await deny(()=>confirm(preview.body_hash,false),/explicit_recovery_review/);
 await deny(()=>confirm('a'.repeat(64)),/explicit_recovery_review/);
 const lease=await confirm();check(await confirm(),lease);
 check((await q('select site_order_package_private.reply_recovery_status($1,$2) v',[incoming.package_id,id(15005)])).confirmed,true);
 const cancelledPreview=await q('select site_order_package_private.preview_reply_recovery($1,$2) v',[incoming.package_id,id(15008)]);
 const cancelled=await q('select site_order_package_private.reconcile_reply_recovery($1,$2,$3) v',[incoming.package_id,cancelledPreview.preview_id,id(15009)]);
 check(cancelled.operation_state,'cancelled');
 await deny(()=>q('select site_order_package_private.confirm_reply_recovery($1,$2,$3,$4,true,$5) v',
 [cancelledPreview.preview_id,cancelledPreview.body_hash,cancelledPreview.render_hash,cancelledPreview.seal_hash,id(15009)]),/operation_retired/);
 const unusedPreview=await q('select site_order_package_private.preview_reply_recovery($1,$2) v',[incoming.package_id,id(15010)]);
 const unusedLease=await q('select site_order_package_private.confirm_reply_recovery($1,$2,$3,$4,true,$5) v',
 [unusedPreview.preview_id,unusedPreview.body_hash,unusedPreview.render_hash,unusedPreview.seal_hash,id(15011)]);
 check((await q('select site_order_package_private.reconcile_reply_recovery($1,$2,$3) v',[incoming.package_id,unusedPreview.preview_id,id(15011)])).operation_state,'cancelled');
 await deny(()=>q('select site_order_package_private.require_reply_recovery_lease($1,$2) v',[unusedLease.lease_id,ready.job_id]),/recovery_lease/);
 await deny(()=>q('select site_order_package_private.confirm_reply_recovery($1,$2,$3,$4,true,$5) v',
 [unusedPreview.preview_id,unusedPreview.body_hash,unusedPreview.render_hash,unusedPreview.seal_hash,id(15011)]),/operation_retired/);
 const {processRecoveredSiteOrderReply}=await import('./site_order_canonical_core.mjs');
 const result=await processRecoveredSiteOrderReply(db,incoming.package_id,lease.lease_id,renderer,claims);
 check(result.status,'recipient_stored');
 const receipt=await q('select to_jsonb(r) v from site_order_artifact_private.pdf_records r where job_id=$1',[ready.job_id]);
 check(receipt.receipt_id,result.original_receipt_id);
 const nativePdf=await q('select pdf_bytes v from site_order_artifact_private.pdf_records where job_id=$1',[ready.job_id]);
 await deny(()=>q('select site_order_manager_private.register_canonical_pdf($1,$2) v',[ready.job_id,nativePdf]),/original_actor_session/);
 const replay=await processRecoveredSiteOrderReply(db,incoming.package_id,lease.lease_id,()=>{throw Error('must reuse original');},claims);
 check(replay.original_receipt_id,result.original_receipt_id);
 check((await q('select site_order_package_private.reconcile_reply_recovery($1,$2,$3) v',[incoming.package_id,preview.preview_id,id(15005)])).operation_state,'accepted');
 check(await q(`select jsonb_build_object('job',to_jsonb(j),'consents',(select jsonb_agg(to_jsonb(c)) from trade_document_consent_private.consents c where c.document_id=j.document_id)) v
 from site_order_artifact_private.render_jobs j where id=$1`,[ready.job_id]),frozen);
 // Later seal/connection/membership/source changes cannot be healed by a lease.
 for(const change of [
  ["update companies set company_seal_enabled=false where id=$1",[frozen.job.company_id]],
  ["update company_members set role='worker' where user_id=$1",[UB]],
  ["update trade_companies set link_status='unlinked' where id=$1",[recipientTrade]],
  ["update private.master_feature_settings set enabled=false where feature_key='site_order_documents'",[]],
 ]){
  await db.exec('begin');try{await db.query(change[0],change[1]);await deny(()=>q('select site_order_package_private.require_reply_recovery_lease($1,$2) v',[lease.lease_id,ready.job_id]),/./);}finally{await db.exec('rollback');}
 }
 await signed(UC);await deny(()=>q('select site_order_package_private.ready_recovered_reply($1,$2) v',[incoming.package_id,lease.lease_id]),/recovery_lease/);
 await signed(UA);await deny(()=>q('select site_order_package_private.preview_reply_recovery($1,$2) v',[incoming.package_id,id(15006)]),/own_recovery_target/);
 await useNew();await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 check((await q('select site_order_package_private.reply_recovery_status($1,$2) v',[incoming.package_id,id(15005)])).reply_recipient_stored,true);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 await db.query('delete from auth.sessions where id=$1',[newSid]);
 await deny(()=>q('select site_order_package_private.require_reply_recovery_lease($1,$2) v',[lease.lease_id,ready.job_id]),/./);
 await db.query('insert into auth.sessions values($1,$2)',[newSid,UB]);
 for(const role of ['anon','authenticated','service_role']){
  await db.exec('set role '+role);await deny(()=>q('select site_order_package_private.preview_reply_recovery($1,$2) v',[incoming.package_id,id(15007)]),/permission denied/);await db.exec('reset role');
 }
 check(await originals(),before);
 check(frozen.job.session_id,oldSid);
 await (await import('./site_order_reply_recovery_races.mjs')).verifyReplyRecoveryRaces(db,
 {id,UA,UB,q,check,deny,signed,send,recipientTrade,recipientPeer,renderer,openNativePeer});
 console.log(JSON.stringify({reply_recovery:true,original_functions_and_jobs_consents_retained:true,new_session_verified_in_synthetic_auth:true,actual_renderer:true,production_changed:false}));
}
