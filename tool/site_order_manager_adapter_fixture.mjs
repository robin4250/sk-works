import fs from 'node:fs/promises';
import {createCanonicalSiteOrderRenderer} from './site_order_canonical_renderer.mjs';
export async function verifySiteOrderManagerAdapter(db,c){
 const {id,A,B,C,UA,UB,actor,q}=c;let checks=0;
 const check=(a,b)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw Error('manager fixture mismatch');checks++;};
 const deny=async(fn,pattern)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!pattern.test(error.message))throw Error('Expected '+pattern+' got '+error?.message);checks++;};
 const original=()=>q(`select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('trade_document_consent_private','site_order_artifact_private','trade_document_confirmation_api_private')`);
 const financial=()=>q(`select jsonb_build_object('invoices',(select jsonb_agg(to_jsonb(i)order by id)from invoices i),
 'payment_certificates',(select jsonb_agg(to_jsonb(p)order by id)from payment_certificates p)) v`);
 const beforeOriginal=await original(),beforeFinancial=await financial();
 await db.exec(await fs.readFile('tool/fixtures/site_order_scoped_actor.fixture.sql','utf8'));
 const candidate=await fs.readFile('docs/review/site-order-manager-purpose/adapter.sql.review-only','utf8');
 await deny(async()=>{
  await db.exec(`begin;create or replace function private.require_standalone_trade_document_access()
   returns jsonb language plpgsql security definer set search_path='' as $$begin return '{}'::jsonb;end $$;`);
  try{await db.exec(candidate);}finally{await db.exec('rollback');}
 },/site_manager_source_changed: private.require_standalone_trade_document_access/);
 await db.exec(candidate);
 await actor(UA);const sid=await q('select id v from auth.sessions where user_id=$1',[UA]);
 await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:UA,role:'authenticated',session_id:sid})]);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 await deny(()=>q('select trade_document_consent_private.require_actor($1) v',[A]),/permission/);
 const site=id(9301),foreignSite=id(9302),trade=id(2100),doc=id(10500),local=id(10501),request=id(10502);
 const peer=await q("select site_order_manager_private.counterparty_context($1,$2,'order') v",[A,trade]);
 const sample=JSON.parse(await fs.readFile('tool/canonical_renderer/synthetic-evidence.json','utf8'));
 const names=await q('select jsonb_object_agg(id,name) v from companies');
 const body={...sample.body,transaction_id:doc,issuer_company_id:A,counterparty_company_id:B,
  issuer:{...sample.body.issuer,name:names[A]},counterparty:{...sample.body.counterparty,name:names[B]}};
 const prepare=(d=doc,s=site,fp=peer.connection_fingerprint,revision=0)=>q('select site_order_manager_private.prepare_site_document($1,$2,$3,\'order\',$4,$5,$6::jsonb) v',[s,d,trade,fp,revision,JSON.stringify({...body,transaction_id:d})]);
 await deny(()=>q('select site_order_manager_private.prepare_document($1,$2,$3,0,$4::jsonb) v',[doc,A,B,JSON.stringify(body)]),/reserved_direction|registered_site/);
 await deny(()=>prepare(doc,foreignSite),/existing_own_site/);
 await deny(()=>prepare(doc,site,'0'.repeat(64)),/connection_changed/);
 const invalidDoc=id(10520);
 await deny(()=>q("select site_order_manager_private.prepare_site_document($1,$2,$3,'order',$4,0,$5::jsonb) v",[site,invalidDoc,trade,peer.connection_fingerprint,JSON.stringify({...body,transaction_id:invalidDoc,issuer_company_id:C})]),/directional document identity/);
 check(await q('select count(*)::int v from site_order_manager_private.document_scopes where document_id=$1',[invalidDoc]),0);
 const prepared=await prepare();check(prepared.revision,1);check(prepared.site_id,site);
 await q('select site_order_manager_private.bind_local($1,$2,$3) v',[doc,A,local]);
 const p=await q('select site_order_manager_private.preview_own($1,1,$2) v',[doc,A]);
 check(p.company_id,A);
 await deny(()=>q("select site_order_manager_private.prepare_document($1,$2,$3,1,$4::jsonb,'invoice',$5,'1',1) v",[doc,A,B,JSON.stringify(body),id(22)]),/no_financial_parent/);
 const approved=await q("select site_order_manager_private.decide($1,1,$2,$3,$4,'approve',$5,true,$6) v",[doc,A,p.epoch,p.body_hash,p.own_seal.seal_hash,request]);
 check(approved.current_state,'approved');
 const job=await q('select site_order_manager_private.prepare_job($1,$2,$3,1,$4,$5) v',[A,site,doc,id(10503),trade]);
 check(job.actor_id,UA);check(job.site_id,site);check(job.counterparty_company_id,B);
 const evidence=await q('select evidence v from site_order_artifact_private.render_jobs where id=$1',[job.job_id]);
 const render=await createCanonicalSiteOrderRenderer({dartExecutable:process.env.SKO_CANONICAL_DART,repositoryRoot:process.cwd()});
 const bytes=await render(evidence);
 const save=()=>q('select site_order_manager_private.register_canonical_pdf($1,$2) v',[job.job_id,bytes]);
 const receipt=await save();check(receipt.job_id,job.job_id);check(receipt.pdf_byte_length,bytes.length);check(await save(),receipt);
 await deny(()=>q('select site_order_artifact_private.register_canonical_pdf($1,$2) v',[job.job_id,bytes]),/permission/);
 await deny(()=>q('select site_order_manager_private.prepare_job($1,$2,$3,1,$4,$5) v',[A,foreignSite,doc,id(10504),trade]),/reserved_site/);
 await deny(()=>q('select site_order_manager_private.require_actor($1,$2) v',[B,doc]),/registered_site_document/);
 await db.query("update company_members set role='worker' where user_id=$1",[UA]);
 await deny(save,/management_required/);
 await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 await db.query('insert into company_members values($1,$2,\'manager\')',[C,UA]);
 await deny(save,/management_required/);await db.query('delete from company_members where company_id=$1 and user_id=$2',[C,UA]);
 await db.query('delete from auth.sessions where id=$1',[sid]);await deny(save,/session/);await db.query('insert into auth.sessions values($1,$2)',[sid,UA]);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");await deny(save,/master_feature_disabled/);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 await db.query("update private.company_connections set status='disabled'");await deny(save,/accepted/);await db.query("update private.company_connections set status='accepted'");
 await db.query('update sites set company_id=$1 where id=$2',[B,site]);await deny(save,/registered_site_document/);await db.query('update sites set company_id=$1 where id=$2',[A,site]);
 check(await save(),receipt);
 // Both directions have their own registered role. A customer registration
 // cannot be borrowed to create an outgoing subcontractor order.
 const customer=id(80),acceptanceDoc=id(10510),acceptanceLocal=id(10511);
 await deny(()=>q("select site_order_manager_private.counterparty_context($1,$2,'order') v",[A,customer]),/registered_direction/);
 const acceptancePeer=await q("select site_order_manager_private.counterparty_context($1,$2,'acceptance') v",[A,customer]);
 const acceptanceBody={...body,kind:'acceptance',transaction_id:acceptanceDoc};
 await q("select site_order_manager_private.prepare_site_document($1,$2,$3,'acceptance',$4,0,$5::jsonb) v",[site,acceptanceDoc,customer,acceptancePeer.connection_fingerprint,JSON.stringify(acceptanceBody)]);
 await q('select site_order_manager_private.bind_local($1,$2,$3) v',[acceptanceDoc,A,acceptanceLocal]);
 const ap=await q('select site_order_manager_private.preview_own($1,1,$2) v',[acceptanceDoc,A]);
 const ar=await q("select site_order_manager_private.decide($1,1,$2,$3,$4,'approve',$5,true,$6) v",[acceptanceDoc,A,ap.epoch,ap.body_hash,ap.own_seal.seal_hash,id(10512)]);
 check(ar.current_state,'approved');
 const aj=await q('select site_order_manager_private.prepare_job($1,$2,$3,1,$4,$5) v',[A,site,acceptanceDoc,id(10513),customer]);
 const ae=await q('select evidence v from site_order_artifact_private.render_jobs where id=$1',[aj.job_id]);
 const ab=await render(ae);const acceptanceReceipt=await q('select site_order_manager_private.register_canonical_pdf($1,$2) v',[aj.job_id,ab]);
 check(acceptanceReceipt.document_id,acceptanceDoc);check(acceptanceReceipt.pdf_byte_length,ab.length);
 await deny(()=>q('select site_order_manager_private.require_actor($1,$2) v',[A,id(9303)]),/registered_site_document/);
 for(const role of ['authenticated','service_role']){
  await db.exec('set role '+role);await deny(save,/permission denied/);await db.exec('reset role');
 }
 check(await original(),beforeOriginal);check(await financial(),beforeFinancial);
 await deny(()=>db.exec('truncate site_order_manager_private.document_scopes cascade'),/immutable/);
 check(await q('select count(*)::int v from site_order_manager_private.generated_sources'),8);
 await db.query("update company_members set role='owner' where user_id=$1",[UA]);
 console.log(JSON.stringify({status:'passed',checks,scope:'generated site-scoped manager SQL + actual PDF; original global owner/admin guards unchanged',production_applied:false,real_auth:false}));
}
