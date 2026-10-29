// New isolated CONTENT REVIEW contract. It deliberately does not finalize or
// mutate financial parents, replace their triggers, or grant public execution.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
export async function verifyMonthlyReview(db,c){
 const {id,A,B,C,UA,UB,UV,UC,PARTNER,actor,q,check,deny,localId,render,upload}=c;
 await actor(UA);
 await db.exec(`alter table trade_companies add column partner_company_id uuid,add column address text,
 add column corporate_number text,add column representative_name text;
 create table private.partner_company_profile_extensions(company_id uuid primary key,representative_name text);
 alter table payment_certificates add column deductions integer not null default 0,
 add column net_amount integer not null default 0,add column automatic_calculation boolean not null default true;
 update private.company_connections set status='accepted'`);
 await db.query("insert into trade_companies(id,company_id,partner_company_id,linked_company_id,trade_role,link_status,address,corporate_number,representative_name) values($1,$2,$3,$4,'subcontractor','linked','登録乙住所','2222222222222','登録乙代表')",[id(2100),A,PARTNER,B]);
 await db.query('insert into private.partner_company_profile_extensions values($1,$2)',[A,'登録甲代表']);
 const financial=()=>q(`select jsonb_build_object('parents',(select jsonb_agg(to_jsonb(p) order by id) from payment_certificates p),
 'invoice_parents',(select jsonb_agg(to_jsonb(i) order by id) from invoices i),
 'invoice_audit',(select jsonb_agg(to_jsonb(a) order by id) from invoice_approval_audit a),
 'invoice_approvals',(select jsonb_agg(to_jsonb(a) order by invoice_id,position) from invoice_approvals a)) v`);
 const epochParent=id(2199);
 await db.query("insert into payment_certificates(id,company_id,partner_company_id,period_start,period_end,revision,status,finalized_at,gross_amount,snapshot,calculation_blocked,deductions,net_amount) values($1,$2,$3,'2026-10-01','2026-10-31',1,'draft',null,110000,'{\"calculation_rows\":[{\"work_content\":\"消費税\",\"amount_yen\":10000}]}',false,1000,109000)",[epochParent,A,PARTNER]);
 const oldFinancial=await financial();
 const readerMeta=async()=>q("select jsonb_build_object('source_md5',md5(p.prosrc),'attributes',to_jsonb(p)-'prosrc') v from pg_proc p where p.oid='private.trade_document_source(text,uuid,text)'::regprocedure");
 const sourceBefore=await readerMeta();check(sourceBefore.source_md5,'3c5a2d13cb243f8c9dc7f7ea82e5b428');
 const epochBefore=await q("select private.trade_document_source('payment_certificate',$1,'1') v",[epochParent]);
 const sourcePatches=[
  ['payment_order_tax_from_snapshot_20261020','aa5a3f8262cd56f25bb43c89ad56d4d3'],
  ['payment_order_directory_party_source_20261021','c61f8835084400b68fbccd9cba35a926'],
  ['payment_order_own_representative_20261021','a24d433cb49462869a06d51081562a43'],
  ['invoice_party_representatives','ebcc70935938482054943560390038b2'],
 ];
 for(const [name,hash] of sourcePatches){
  await db.exec(await fs.readFile('docs/candidates/'+name+'.sql.review-only','utf8'));
  const current=await readerMeta();check(current.source_md5,hash);check(current.attributes,sourceBefore.attributes);check(await financial(),oldFinancial);
 }
 const epochAfter=await q("select private.trade_document_source('payment_certificate',$1,'1') v",[epochParent]);
 for(const key of ['source_fingerprint','source_revision','source_locked'])check(epochAfter[key],epochBefore[key]);
 if(c.confirmedTerms){
  await db.exec(await fs.readFile('docs/review/trade-document-terms/save-guard.sql.review-only','utf8'));
  await (await import('./trade_document_terms_save_fixture.mjs')).verifyTermsSave(db,{id,company:A,partner:PARTNER,actor:()=>actor(UA),expectedDelegate:'82fa37936aea1e0199e1b359e1379d65'});
 }
 check(epochAfter.defaults.tax_amount_yen,10000);
 check(epochAfter.defaults.counterparty,{name:'乙会社',address:'登録乙住所',corporate_number:'2222222222222',representative_name:'登録乙代表'});
 check(epochAfter.defaults.issuer.representative_name,'登録甲代表');
 console.log('PASS monthly source epoch: verbatim base -> tax -> directory -> own representative -> invoice representative patches, original metadata/financial state/fingerprint preserved, final production body ebcc70935938482054943560390038b2');
 const callbacksBefore=await q(`select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('source',md5(prosrc),'definition',pg_get_functiondef(p.oid),'attributes',to_jsonb(p)-'prosrc')) v
 from pg_proc p where p.oid in('trade_document_consent_private.parent_binding(text,uuid,uuid,uuid)'::regprocedure,
 'trade_document_consent_private.linked_view_allowed(text,uuid,uuid,integer,uuid)'::regprocedure)`);
 const candidate=await fs.readFile('docs/candidates/trade_document_monthly_review_20261022.sql.review-only','utf8');
 const actorDefinition=await q("select pg_get_functiondef('trade_document_consent_private.require_actor(uuid)'::regprocedure) v");
 await db.exec(actorDefinition.replace('begin','begin\n -- synthetic source drift\n'));
 await deny(()=>db.exec(candidate),/prerequisite changed/);await db.exec('rollback');await db.exec(actorDefinition);
 check(await q("select to_regclass('trade_document_consent_private.monthly_review_receipts') is null v"),true);
 await db.exec(candidate);
 check(await financial(),oldFinancial);
 const callbacksAfter=await q(`select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('source',md5(prosrc),'definition',pg_get_functiondef(p.oid),'attributes',to_jsonb(p)-'prosrc')) v
 from pg_proc p where p.oid in('trade_document_consent_private.parent_binding(text,uuid,uuid,uuid)'::regprocedure,
 'trade_document_consent_private.linked_view_allowed(text,uuid,uuid,integer,uuid)'::regprocedure)`);
 for(const sig of Object.keys(callbacksBefore))check(callbacksAfter[sig].attributes,callbacksBefore[sig].attributes);
 const state=x=>q(`select jsonb_build_object('parent',to_jsonb(p),
 'revision',(select to_jsonb(r) from trade_document_consent_private.revisions r where document_id=$2 and revision=1),
 'consents',(select jsonb_agg(to_jsonb(s)) from trade_document_consent_private.consents s where document_id=$2),
 'events',(select jsonb_agg(to_jsonb(e) order by e.id) from trade_document_consent_private.events e where document_id=$2),
 'review_receipts',(select jsonb_agg(to_jsonb(r)) from trade_document_consent_private.monthly_review_receipts r where document_id=$2),
 'primitive_receipts',(select jsonb_agg(to_jsonb(r)) from trade_document_consent_private.receipts r where payload->>'document_id'=$2::text)) v from payment_certificates p where id=$1`,[x.parent,x.doc]);
 const prepare=async(num)=>{
  await actor(UA);const parent=id(2200+num),doc=id(2300+num),local=localId(doc,A);
  await db.query("insert into payment_certificates(id,company_id,partner_company_id,period_start,period_end,revision,status,finalized_at,gross_amount,snapshot,calculation_blocked,deductions,net_amount) values($1,$2,$3,'2026-10-01','2026-10-31',1,'draft',null,110000,'{\"tax\":10000}',false,1000,109000)",[parent,A,PARTNER]);
  const workspace=await q("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[parent]);
  const payload={...workspace.defaults,issue_date:'2026-10-22',work_name:'保存済月次確認',work_address:'東京都',
   intro_text:'合成発注',payment_conditions:'翌月末',notes:'',issuer:{...workspace.defaults.issuer,representative_name:'甲代表'},
   counterparty:{...workspace.defaults.counterparty,corporate_number:'2222222222222'}};
  if(c.confirmedTerms)payload.contract_terms=c.confirmedTerms;
  await q("select public.save_trade_document_attachment('payment_certificate',$1,'1',0,$2::jsonb) v",[parent,JSON.stringify(payload)]);
  const body={...payload,issuer_company_id:A,counterparty_company_id:B,transaction_id:doc};delete body.company_seal_snapshot;delete body.company_seal_enabled;
  await q("select trade_document_consent_private.prepare_document($1,$2,$3,0,$4::jsonb,'payment_certificate',$5,'1',1) v",[doc,A,B,JSON.stringify(body),parent]);
  await db.query('select trade_document_consent_private.bind_local($1,$2,$3)',[doc,A,local]);
  return {parent,doc,local};
 };
 const preview=x=>q('select trade_document_consent_private.preview_monthly_review($1,$2,1) v',[x.local,A]);
 const confirm=(x,p,rid=id(2400+Number(x.doc.slice(-3))),review=true,seal=true)=>q('select trade_document_consent_private.confirm_monthly_review($1,$2,1,$3::jsonb,$4,$5,$6) v',[x.local,A,JSON.stringify(p),rid,review,seal]);
 const x=await prepare(1),p=await preview(x),before=await state(x);
 await deny(()=>confirm(x,p,id(2501),true,false),/both explicit/);check(await state(x),before);
 await deny(()=>confirm(x,p,id(2501),false,true),/both explicit/);check(await state(x),before);
 const receipt=await confirm(x,p,id(2501));
 check([receipt.monthly_review_recorded,receipt.seal_consent_recorded,receipt.financial_finalized,receipt.financial_parent_unchanged],[true,true,false,true]);
 const after=await state(x);check(after.parent,before.parent);check(after.review_receipts.length,1);check(after.consents.length,1);
 check(await confirm(x,p,id(2501)),receipt);check(await state(x),after);
 await deny(()=>confirm(x,{...p,monthly_review_only:false},id(2501)),/payload or actor mismatch/);check(await state(x),after);
 await db.query("insert into company_members values($1,$2,'admin')",[A,UB]);await actor(UB);
 await deny(()=>confirm(x,p,id(2501)),/payload or actor mismatch/);await actor(UA);await db.query('delete from company_members where company_id=$1 and user_id=$2',[A,UB]);
 const issued=await render(x.doc,1,A);await actor(UB);const peerLocal=localId(x.doc,B);
 await db.query('select trade_document_consent_private.bind_local($1,$2,$3)',[x.doc,B,peerLocal]);
 check(await render(x.doc,1,B),issued);check(issued.seals.length,1);check(issued.render_seal_company_id,A);
 check(x.local===peerLocal,false);
 await deny(()=>q('select trade_document_consent_private.confirm_monthly_review($1,$2,1,$3::jsonb,$4,true,true) v',[peerLocal,B,JSON.stringify(p),id(2502)]),/own monthly order/);
 await actor(UC);await deny(()=>preview(x),/permission/);await actor(UV);await deny(()=>preview(x),/permission/);await actor(UA);
 await db.exec("select set_config('test.blocked','true',false)");await deny(()=>confirm(x,p,id(2501)),/permission/);await db.exec("select set_config('test.blocked','false',false)");
 await deny(()=>q('select trade_document_consent_private.preview_monthly_review($1,$2,1) v',['preview:company:2026-10',A]),/uuid/);
 const stale=await prepare(2),sp=await preview(stale);await db.query('update payment_certificates set gross_amount=gross_amount+1,revision=revision+1 where id=$1',[stale.parent]);const ss=await state(stale);
 await deny(()=>confirm(stale,sp),/attachment|changed/);check(await state(stale),ss);
 const staleInitial=await prepare(10);await db.query('update payment_certificates set gross_amount=gross_amount+1 where id=$1',[staleInitial.parent]);const staleInitialState=await state(staleInitial);
 await deny(()=>preview(staleInitial),/attachment source changed/);check(await state(staleInitial),staleInitialState);
 const finalized=await prepare(3),fp=await preview(finalized);await db.query("update payment_certificates set status='finalized',finalized_at=now() where id=$1",[finalized.parent]);const fsnap=await state(finalized);
 await deny(()=>confirm(finalized,fp),/unfinalized/);check(await state(finalized),fsnap);
 const late=await prepare(4),lp=await preview(late),ls=await state(late);
 await db.exec("create function private.fixture_monthly_late_failure() returns trigger language plpgsql as $$begin raise exception 'fixture monthly late failure';end $$;create trigger fixture_monthly_late_failure before insert on trade_document_consent_private.monthly_review_receipts for each row execute function private.fixture_monthly_late_failure()");
 await deny(()=>confirm(late,lp),/monthly late failure/);check(await state(late),ls);await db.exec('drop trigger fixture_monthly_late_failure on trade_document_consent_private.monthly_review_receipts');
 const ambiguous=await prepare(5),ap=await preview(ambiguous);await db.query("insert into trade_companies(id,company_id,partner_company_id,linked_company_id,trade_role,link_status) values($1,$2,$3,$4,'subcontractor','linked')",[id(2101),A,PARTNER,B]);const ambState=await state(ambiguous);
 await deny(()=>confirm(ambiguous,ap),/unique partner/);check(await state(ambiguous),ambState);await db.query('delete from trade_companies where id=$1',[id(2101)]);
 const changedSeal=await prepare(7),sealPreview=await preview(changedSeal),sealState=await state(changedSeal);
 const sealRevision=await q('select revision v from private.company_seal_png_selection where company_id=$1',[A]);
 await upload(A,'甲会社',sealRevision,16);
 await deny(()=>confirm(changedSeal,sealPreview),/source changed/);check(await state(changedSeal),sealState);
 const disabled=await prepare(8),dp=await preview(disabled),ds=await state(disabled);
 await db.query("update private.company_connections set status='disabled'");await deny(()=>confirm(disabled,dp),/accepted/);check(await state(disabled),ds);
 await db.query("update private.company_connections set status='accepted'");
 const revoked=await prepare(9),rp=await preview(revoked),rs=await state(revoked);
 await db.query("update company_members set role='viewer' where company_id=$1 and user_id=$2",[A,UA]);await deny(()=>confirm(revoked,rp),/permission/);check(await state(revoked),rs);
 await db.query("update company_members set role='owner' where company_id=$1 and user_id=$2",[A,UA]);
 const primitive=await prepare(6);const pp=await preview(primitive);
 await q("select trade_document_consent_private.decide($1,1,$2,0,$3,'approve',$4,true,$5) v",[primitive.doc,A,pp.body_hash,pp.own_seal.seal_hash,id(2510)]);
 await deny(()=>render(primitive.doc,1,A),/view permission/);
 await actor(UB);await db.query('select trade_document_consent_private.bind_local($1,$2,$3)',[primitive.doc,B,localId(primitive.doc,B)]);await deny(()=>render(primitive.doc,1,B),/view permission/);await actor(UA);
 await db.query('update payment_certificates set gross_amount=gross_amount+1,revision=revision+1 where id=$1',[x.parent]);
 await deny(()=>render(x.doc,1,A),/attachment|changed/);check(await render(x.doc,1,A,true),issued);check(await confirm(x,p,id(2501)),receipt);
 await deny(()=>db.query('update trade_document_consent_private.monthly_review_receipts set actor_id=actor_id'),/immutable/);
 await db.exec('set role authenticated');await deny(()=>preview(x),/permission denied/);await db.exec('reset role');
 await db.exec('set role anon');await deny(()=>db.query('select * from trade_document_consent_private.monthly_review_receipts'),/permission denied/);await db.exec('reset role');
 if(c.openNativePeer) await verifyNativeMonthlyRace(db,{...c,prepare,preview,confirm,state});
 else console.log('SKIP native monthly review parent race: independent PostgreSQL connections unavailable in PGlite');
 assert.equal(receipt.financial_finalized,false);
 const finalFinancial=await financial();
 for(const parent of oldFinancial.parents)check(finalFinancial.parents.find(row=>row.id===parent.id),parent);
 for(const key of ['invoice_parents','invoice_audit','invoice_approvals'])check(finalFinancial[key],oldFinancial[key]);
 console.log('PASS monthly content-review NEW private candidate: saved UUID/revision/attachment/formal partner/issuer seal bound, explicit choices, one receipt/replay, changed payload/actor/preview/parent/finalized/ambiguous mapping refusals, late rollback, separate received copy, no financial parent finalization; public/API/UI/realJWT/production UNIMPLEMENTED');
 if(process.env.SKO_TRADE_DOCUMENT_API_REVIEW_HOOK){
  if(process.env.SKO_TRADE_DOCUMENT_API_REVIEW_HOOK!=='contract-v1')throw Error('unknown confirmation API review fixture hook');
  await (await import('./trade_document_confirmation_api_fixture.mjs')).verifyConfirmationApi(db,{...c,prepareMonthly:prepare,monthlyState:state});
 }
}

async function verifyNativeMonthlyRace(db,c){
 const {A,UA,prepare,preview,state,id,check,openNativePeer}=c;
 const x=await prepare(20),p=await preview(x);const editor=await openNativePeer(),reviewer=await openNativePeer();
 try{
  await editor.query('begin');await editor.query('update payment_certificates set gross_amount=gross_amount+1,revision=revision+1 where id=$1',[x.parent]);
  await reviewer.query("select set_config('test.uid',$1,false)",[UA]);
  const pid=(await reviewer.query('select pg_backend_pid() pid')).rows[0].pid;
  let done=false;
  const waiting=reviewer.query('select trade_document_consent_private.confirm_monthly_review($1,$2,1,$3::jsonb,$4,true,true) v',[x.local,A,JSON.stringify(p),id(2600)]).then(r=>({ok:true,result:r}),e=>({ok:false,error:e})).finally(()=>{done=true;});
  let observed=false;
  for(let attempt=0;attempt<100;attempt++){
   const r=await db.query("select wait_event_type,cardinality(pg_blocking_pids($1)) blockers from pg_stat_activity where pid=$1",[pid]);
   if(r.rows[0]?.wait_event_type==='Lock'&&r.rows[0]?.blockers>0){observed=true;break;}
   if(done)break;await new Promise(resolve=>setTimeout(resolve,20));
  }
  check(observed,true);await editor.query('commit');const outcome=await waiting;check(outcome.ok,false);check(outcome.error.code,'40001');
  const current=await state(x);check(current.review_receipts,null);check(current.consents,null);check(current.revision.state,'open');
  console.log('PASS native monthly review race: actual lock wait observed, prior financial edit wins and stale review/issuer consent both refuse');
 }finally{await editor.query('rollback').catch(()=>{});await reviewer.end();await editor.end();}
}
