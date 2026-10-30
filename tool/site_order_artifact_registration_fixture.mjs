import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';

export async function verifySiteOrderArtifactRegistration(db,c) {
 const {id,A,B,C,UA,UB,UC,actor,q,prepare,preview,decide,confirmedTerms}=c;
 if(!confirmedTerms)throw Error('Exact confirmed terms hook required');
 let checks=0;
 const check=(a,b,message)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw Error(message||`${JSON.stringify(a)} != ${JSON.stringify(b)}`);checks++;};
 const deny=async(fn,pattern)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!pattern.test(error.message))throw Error(`Expected ${pattern}, got ${error?.message}`);checks++;};
 const asActor=async uid=>{
  await actor(uid);const sid=await q('select id v from auth.sessions where user_id=$1',[uid]);
  if(!sid)throw Error('Existing synthetic session missing');
  await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:uid,role:'authenticated',session_id:sid})]);
  return sid;
 };
 // Existing actual API actor performs the synthetic claims/session checks.
 // This adapter is fixture-only and is not relabelled production reauth proof.
 await db.exec(`create table public.sites(id uuid primary key,company_id uuid,name text);
 create table private.master_feature_settings(feature_key text primary key,enabled boolean);
 create function private.require_reauthentication_session() returns uuid language plpgsql as $$
 begin perform trade_document_confirmation_api_private.actor();return (auth.jwt()->>'session_id')::uuid;end $$;`);
 await db.exec(await fs.readFile('tool/fixtures/site_order_master_gate.fixture.sql','utf8'));
 const protectedFunctions=()=>q(`select jsonb_agg(jsonb_build_object('oid',p.oid,'name',p.oid::regprocedure::text,
 'source',md5(p.prosrc),'owner',p.proowner,'definer',p.prosecdef,'config',p.proconfig,'acl',p.proacl::text)order by p.oid) v
 from pg_proc p where p.oid=any(array['trade_document_confirmation_api_private.actor()'::regprocedure,
 'trade_document_consent_private.require_actor(uuid)'::regprocedure,
 'trade_document_consent_private.lock_pair(uuid,uuid)'::regprocedure,
 'trade_document_consent_private.render_approved(uuid,integer,uuid,boolean)'::regprocedure,
 'private.require_trade_documents_master_feature()'::regprocedure])`);
 const beforeFunctions=await protectedFunctions();
 const financial=()=>q(`select jsonb_build_object('invoices',(select jsonb_agg(to_jsonb(i)order by id)from public.invoices i),
 'payment_certificates',(select jsonb_agg(to_jsonb(p)order by id)from public.payment_certificates p)) v`);
 const beforeFinancial=await financial();
 await db.exec(await fs.readFile('docs/review/site-order-artifact-registration/private-register.sql.review-only','utf8'));
 const site=id(9301),foreignSite=id(9302),doc=id(9303),request=id(9304);
 await db.query('insert into public.sites values($1,$2,\'合成工事\'),($3,$4,\'別会社現場\')',[site,A,foreignSite,B]);
 await db.query("insert into private.master_feature_settings values('site_order_documents',true)");
 await asActor(UA);
 await db.query("update private.company_connections set status='accepted'");
 const names=await q('select jsonb_object_agg(id,name) v from public.companies');
 const body={kind:'order',issuer_company_id:A,counterparty_company_id:B,
   issuer:{name:names[A]},counterparty:{name:names[B]},total_amount_yen:100,
   work_name:'合成工事',contract_terms:confirmedTerms};
 await prepare(doc,0,body);await decide(doc,1,A,await preview(doc,1,A));
 const trade=id(2100);
 const makeJob=(s=site,r=request)=>q('select site_order_artifact_private.prepare_job($1,$2,$3,1,$4,$5) v',[A,s,doc,r,trade]);
 const job=await makeJob();
 check(job.document_id,doc);check(job.site_id,site);check(await makeJob(),job);
 check(job.actor_id,UA);check(job.request_id,request);
 check(job.counterparty_company_id,B);check(job.counterparty_name,names[B]);
 check(job.counterparty_trade_company_id,trade);
 check(/^[a-f0-9]{64}$/.test(job.counterparty_connection_fingerprint),true);
 await deny(()=>q('select site_order_artifact_private.prepare_job($1,$2,$3,1,$4,$5) v',
   [A,site,doc,id(9305),id(8200)]),/registered_counterparty/);
 await deny(()=>makeJob(foreignSite),/own_site/);
 await deny(()=>q('select site_order_artifact_private.prepare_job($1,$2,$3,2,$4,$5) v',[A,site,doc,request,trade]),/request_changed/);
 const pdf=Buffer.from('%PDF-1.7\nfixture-only-not-a-layout-proof\n%%EOF','utf8');
 const save=(bytes=pdf)=>q('select site_order_artifact_private.register_canonical_pdf($1,$2) v',[job.job_id,bytes]);
 const receipt=await save();
 check(receipt.pdf_sha256,createHash('sha256').update(pdf).digest('hex'));
 check(receipt.pdf_byte_length,pdf.length);check(receipt.render_hash,job.render_hash);
 check(receipt.session_id,job.session_id);
 check(await save(),receipt);
 check(receipt.counterparty_connection_fingerprint,job.counterparty_connection_fingerprint);
 await db.query('update public.companies set name=$2 where id=$1',[B,'改名後の乙会社']);
 await deny(()=>save(),/counterparty_changed/);
 await deny(()=>makeJob(),/request_changed/);
 await deny(()=>makeJob(site,id(9306)),/exact_approved_form/);
 check(await q('select counterparty_name v from site_order_artifact_private.render_jobs where id=$1',[job.job_id]),names[B]);
 await db.query('update public.companies set name=$2 where id=$1',[B,names[B]]);
 await db.query('update public.trade_companies set linked_company_id=$2 where id=$1',[trade,C]);
 await deny(()=>save(),/registered_counterparty/);
 await db.query('update public.trade_companies set linked_company_id=$2 where id=$1',[trade,B]);
 const connection=await q(`select jsonb_build_object('id',id,'updated_at',updated_at) v
   from private.company_connections where parent_company_id=$1 and child_company_id=$2`,[A,B]);
 await db.query("update private.company_connections set updated_at=clock_timestamp()+interval '1 second' where id=$1",[connection.id]);
 await deny(()=>save(),/counterparty_changed/);
 await deny(()=>makeJob(),/request_changed/);
 await db.query('update private.company_connections set updated_at=$2::timestamptz where id=$1',[connection.id,connection.updated_at]);
 check(await save(),receipt);
 await deny(()=>save(Buffer.from('%PDF-1.7\nchanged-original-content\n%%EOF')),/pdf_original_changed/);
 await deny(()=>save(Buffer.from('not a PDF at all and never accepted')),/pdf_bytes_required/);
 await asActor(UB);await deny(()=>save(),/original_actor_session/);
 await asActor(UC);await deny(()=>makeJob(),/permission/);
 const sid=await asActor(UA);
 await db.query('delete from auth.sessions where id=$1',[sid]);
 await deny(()=>save(),/session/);
 await db.query('insert into auth.sessions values($1,$2)',[sid,UA]);
 await db.exec('set role authenticated');
 await deny(()=>save(),/permission denied/);
 await db.exec('reset role; set role service_role');
 await deny(()=>save(),/permission denied/);
 await db.exec('reset role');
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await deny(()=>save(),/master_feature_disabled/);
 check(await q('select count(*)::int v from site_order_artifact_private.pdf_records'),1);
 await deny(()=>db.exec('delete from site_order_artifact_private.pdf_records'),/immutable/);
 await deny(()=>db.exec("update site_order_artifact_private.pdf_records set pdf_bytes=convert_to('changed','UTF8')"),/immutable/);
 await deny(()=>db.exec('delete from site_order_artifact_private.render_jobs'),/immutable/);
 await deny(()=>db.exec('truncate site_order_artifact_private.pdf_records'),/immutable/);
 await deny(()=>db.exec('truncate site_order_artifact_private.render_jobs cascade'),/immutable/);
 check(await protectedFunctions(),beforeFunctions,'Existing guard functions changed');
 check(await financial(),beforeFinancial,'Financial rows changed');
 console.log(JSON.stringify({status:'passed',checks,scope:'existing consent/API source reuse plus private PDF-byte registration; synthetic auth and fixture-only PDF bytes; not canonical-renderer or production proof',production_applied:false}));
}
