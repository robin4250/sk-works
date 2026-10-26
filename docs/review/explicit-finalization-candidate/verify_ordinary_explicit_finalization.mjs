// Native PG17 only. Existing installers are reused; old successful suites are not replayed.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url));
const adminFolder=resolve(here,'../attendance-admin-override-candidate'),documentFolder=resolve(here,'../supervisor-document-candidate');
const folder=await mkdtemp(join(tmpdir(),'ordinary-explicit-finalization-'));
try{
 const bootstrap=join(folder,'admin-bootstrap.mjs');
 const emitted=spawnSync(process.execPath,[resolve(adminFolder,'verify_admin_override.mjs')],{stdio:'inherit',env:{...process.env,SKO_ADMIN_EMIT_ONLY:bootstrap}});
 assert.equal(emitted.status,0,'Existing source-bound installer');
 const original=await readFile(bootstrap,'utf8'),marker=" eq(await q('select count(*)::int v from attendance_admin_override_private.rollout'),0,";
 assert.equal(original.split(marker).length,2);
 const setup=original.slice(0,original.indexOf(marker)),tail=original.slice(original.indexOf('}catch(error){'));
 const unit=String.raw`
 phase='ordinary-source-shape-and-exact-producers';
 const candidateRoot=process.env.SKO_ORDINARY_EXPLICIT_ROOT;
 const sqlLiteral=s=>"'"+String(s).replaceAll("'","''")+"'";
 const identifier=s=>{assert.match(s,/^[a-z_][a-z_0-9]*$/);return '"'+s+'"';};
 const columns=JSON.parse(await readFile(candidateRoot+'/sources/financial-fixture-columns.json','utf8'));
 const grouped=new Map();
 for(const col of columns){const key=col.table_schema+'.'+col.table_name;if(!grouped.has(key))grouped.set(key,[]);grouped.get(key).push(col);}
 for(const col of columns.filter(x=>x.data_type==='USER-DEFINED')){
  if(!await q('select to_regtype($1) is not null v',[col.udt_schema+'.'+col.udt_name])){
   assert.ok(Array.isArray(col.enum_labels)&&col.enum_labels.length);await exec('create type '+identifier(col.udt_schema)+'.'+identifier(col.udt_name)+' as enum('+col.enum_labels.map(sqlLiteral).join(',')+')');
  }
 }
 for(const [table,cols]of grouped){
  const [schema,name]=table.split('.'),tableSql=identifier(schema)+'.'+identifier(name);
  await exec('create table if not exists '+tableSql+'()');
  const known=new Set((await client.query('select column_name from information_schema.columns where table_schema=$1 and table_name=$2',[schema,name])).rows.map(x=>x.column_name));
  for(const col of cols.sort((a,b)=>a.ordinal_position-b.ordinal_position)){
   if(known.has(col.column_name))continue;
   const type=col.data_type==='ARRAY'?identifier(col.udt_schema)+'.'+identifier(col.udt_name.slice(1))+'[]':identifier(col.udt_schema)+'.'+identifier(col.udt_name);
   await exec('alter table '+tableSql+' add column '+identifier(col.column_name)+' '+type+(col.column_default?' default '+col.column_default:''));
  }
 }
 // Tax/leave surroundings remain the inherited explicit neutral fixtures. They
 // are not proof of real tax enrollment or insurance amounts. The financial
 // producers and invoice/seal/route/expense dependencies below are real source.
 await exec("alter table sites add column if not exists name text,add column if not exists formal_name text,add column if not exists created_at timestamptz default now();create table public.member_feature_permissions(company_id uuid,user_id uuid,can_view_invoices boolean default false,can_manage_invoices boolean default false,can_manage_payroll boolean default false,can_manage_people boolean default false,can_manage_attendance boolean default false,can_approve_daily_report_edits boolean default false,can_manage_partner_chat boolean default false);");
 const dependencies=[];for(const file of ['financial-dependencies.json','financial-dependencies2.json','financial-dependencies3.json'])dependencies.push(...JSON.parse(await readFile(candidateRoot+'/sources/'+file,'utf8')));
 const producers=JSON.parse(await readFile(candidateRoot+'/financial-source-originals.json','utf8'));
 const ranks={aoyagi_reisho_name_supported:0,rate_formula_label:1,resolve_rate_formula:2,route_signed_checkout_sources:3,route_signed_site_rates:4,route_signed_checkout_components:5,route_billing_invoice_blocked:6,uploaded_company_seal_snapshot:7,document_company_seal_snapshot:8,ensure_unassigned_invoice_customer:9,expense_cost_components:10,route_billing_invoice_components:11};
 for(const row of dependencies.sort((a,b)=>(ranks[a.identity.match(/private\.([^ (]+)/)[1]]??100)-(ranks[b.identity.match(/private\.([^ (]+)/)[1]]??100))){eq(md5(dbBody(row.definition)),row.body_md5,'Exact dependency '+row.identity);await exec(row.definition);}
 for(const row of producers){eq(md5(dbBody(row.definition)),row.body_md5,'Exact financial producer '+row.identity);if(row.identity==='private.has_company_feature(uuid,text)')await exec('drop function private.has_company_feature(uuid,text)');await exec(row.definition);if(row.acl!==null)await exec('revoke all on function '+row.identity+' from public,anon,authenticated,service_role');}
 await exec('create trigger fixture_actual_attendance_refresh_invoice after insert or update or delete on public.attendance_entries for each row execute function private.attendance_refresh_invoice()');
 const customer=id(9901);
 await client.query("update companies set name='合成の検証会社',tax_rate=0,company_seal_style='legacy' where id=$1",[A]);
 await client.query("insert into customers(id,company_id,name) values($1,$2,'合成の取引先')",[customer,A]);
 await client.query("update sites set customer_id=$1,name='合成の現場',formal_name='合成の現場' where id=$2",[customer,SITE]);
 await client.query('insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values($1,$2,10000,0)',[A,SITE]);
 await client.query("update company_members set role='worker' where company_id=$1 and user_id in($2,$3)",[A,memberB,memberC]);
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date,source_clock_in_id) values($1,$2,$3,$4,'clock_out',$5::date+time '17:00',$5,$6)",[id(9303),A,W2,SITE,docDay,id(9302)]);
 await sharedCall(U,id(80),'select public.reuse_my_shared_daily_report($1) v',[docStart]);
 await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(9302)]);
 const business=()=>q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r),'workers',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w),'clocks',(select jsonb_agg(to_jsonb(c) order by id) from attendance_verifications c),'entries',(select jsonb_agg(to_jsonb(e) order by id) from attendance_entries e),'payroll',(select jsonb_agg(to_jsonb(p) order by worker_id,period_start) from payroll_statements p),'invoices',(select jsonb_agg(to_jsonb(i) order by id) from invoices i),'ledger',(select jsonb_agg(to_jsonb(l) order by id) from checkout_shared_hours_private.ledger l),'confirmations',(select jsonb_agg(to_jsonb(c) order by id) from checkout_shared_hours_private.confirmations c),'events',(select jsonb_agg(to_jsonb(e) order by id) from shared_daily_report_private.signature_events e)) v");
 const snapshot=async()=>({...await business(),explicit:await q('select jsonb_agg(to_jsonb(e) order by id) v from explicit_report_finalization_private.events e'),permits:await q('select jsonb_agg(to_jsonb(p) order by report_id) v from explicit_report_finalization_private.permits p')});
 phase='ordinary-default-off-install';
 const actualSignature=JSON.parse(await readFile(candidateRoot+'/source-originals.json','utf8')).find(x=>x.signature==='private.save_daily_report_signature(uuid,text,text,jsonb)');
 eq(await q("select md5(prosrc) v from pg_proc where oid='private.save_daily_report_signature(uuid,text,text,jsonb)'::regprocedure"),actualSignature.body_md5,'Fixture retains the actual signature function body');
 // The inherited installer grants service_role for its separate legacy tests.
 // Match the captured production ACL before testing the strict new source guard.
 await exec('revoke execute on function private.save_daily_report_signature(uuid,text,text,jsonb) from service_role');
 const before=await business();await exec(await readFile(candidateRoot+'/explicit-finalization.sql.review-only','utf8'));
 eq(await business(),before,'OFF installation preserves all source and financial rows');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.rollout'),0,'No company activation');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.reports'),0,'No report activation');
 await client.query('insert into explicit_report_finalization_private.reports(company_id,report_id,enabled) values($1,$2,true)',[A,rid]);
 const context=async(actor=U,sid=id(80))=>sharedCall(actor,sid,'select public.read_shared_daily_report_context($1) v',[rid]);
 const peer=await sharedCall(memberB,sidB,'select public.read_shared_worker_facts($1,$2) v',[rid,W2]);
 assert.ok(peer.proposed_worker_facts,'Explicit category and selections are required');
 const peerFacts={...peer.proposed_worker_facts};delete peerFacts.company_allowance_legacy_labels;
 await sharedCall(memberB,sidB,'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,$4,$5,$6) v',[rid,W2,JSON.stringify(peerFacts),null,peer.revision,peer.scope_fingerprint]);
 let c=await context();
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'representative','合成の実報告者',signature,c.report_updated_at,c.signature_scope_fingerprint]);
 c=await context(memberB,sidB);
 eq(c.explicit_finalization_required,true,'Frozen participant resumes same explicit report');
 await sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,id(9302),'合成の実責任者',signature,c.report_updated_at,c.signature_scope_fingerprint]);
 c=await context(memberB,sidB);
 eq(await q('select status v from daily_reports where id=$1',[rid]),'draft','④ stores evidence, not final status');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[rid]),0,'④ formal attendance zero');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.ledger where report_id=$1',[rid]),0,'④ ledger zero');
 eq(await q("select count(*)::int v from payroll_statements where company_id=$1 and period_start='2026-10-01'",[A]),0,'④ payroll projection zero');
 eq(await q('select count(*)::int v from invoices where company_id=$1',[A]),0,'④ invoice projection zero');
 eq(c.explicit_finalization_ready,true,'Only explicit ⑤ is now enabled');
 const request=[rid,c.report_updated_at,c.signature_scope_fingerprint];
 const finish=()=>sharedCall(memberB,sidB,'select public.finalize_shared_daily_report($1,$2::timestamptz,$3) v',request);
 phase='ordinary-producer-error-rollback';
 await exec("create function public.fixture_invoice_generation_failure() returns trigger language plpgsql as $$begin raise exception 'fixture_invoice_generation_failure';end$$;create trigger fixture_invoice_generation_failure before insert on public.invoices for each row execute function public.fixture_invoice_generation_failure();");
 const failureBefore=await snapshot();await reject(finish,/fixture_invoice_generation_failure/);eq(await snapshot(),failureBefore,'Producer error rolls back status, entries, ledger, payroll, invoice and receipts');
 await exec('drop trigger fixture_invoice_generation_failure on public.invoices;drop function public.fixture_invoice_generation_failure()');
 phase='ordinary-producer-early-return-rollback';
 await client.query("insert into invoices(id,company_id,customer_id,billing_period_start,billing_period_end,status,automatic_calculation,snapshot,grand_total) values($1,$2,$3,'2026-10-01','2026-10-31','approved',false,'{\"fixture\":\"immutable approved invoice\"}',12345)",[id(9902),A,customer]);
 const protectedBefore=await snapshot();await reject(finish,/explicit_report_finalized_invoice_protected|explicit_report_invoice_projection_missing/);eq(await snapshot(),protectedBefore,'Actual producer early return cannot be partial success');
 await client.query('delete from invoices where id=$1',[id(9902)]);
 phase='ordinary-actual-producer-final-save';
 const done=await finish();eq(done.explicit_finalization_completed,true,'⑤ commits completion');
 eq(await q('select status v from daily_reports where id=$1',[rid]),'signed','Existing real final writer signs source');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[rid]),2,'One formal day per participant');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.ledger where report_id=$1',[rid]),2,'One confirmed ledger per participant');
 for(const wid of [reportWorker,W2])eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,wid]),'1','Actual salary producer counts one day per participant');
 eq(await q('select count(*)::int v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation is true',[A,customer]),1,'Actual invoice producer creates one customer/month draft');
 const invoice=await q('select to_jsonb(i) v from invoices i where company_id=$1 and customer_id=$2',[A,customer]);eq(invoice.calculation_blocked,false,'Actual invoice is not blocked');eq(invoice.snapshot.sites.some(s=>s.site_id===SITE),true,'Invoice keeps actual site source');
 const actualSite=invoice.snapshot.sites.find(s=>s.site_id===SITE);
 eq(actualSite.lines.filter(line=>Number(line.unit_price)===10000).reduce((sum,line)=>sum+Number(line.quantity),0),2,'Actual invoice counts both participant-days once');
 eq(invoice.grand_total,20000,'Actual source quantity two times explicit synthetic daily rate 10000');
 const settled=await snapshot();await finish();eq(await snapshot(),settled,'Exact lost-result retry duplicates no source, payroll, invoice or final audit');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.permits'),0,'No reusable final-save permit');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,signature_capture_deferred:true,actual_four_financial_producers:true,actual_invoice_non_route_dependencies:true,actual_payroll_one_day_per_participant:true,invoice_one_customer_month:true,error_and_early_return_atomic_rollback:true,exact_retry_idempotent:true,synthetic_auth_and_neutral_tax_leave:true,old_document_conversion_and_admin_crud_covered:false,production_changed:false}));
`;
 const proof=join(folder,'proof.mjs'),generated=setup+unit+tail;await writeFile(proof,generated);
 if(process.env.SKO_ORDINARY_EXPLICIT_EMIT_ONLY)await writeFile(process.env.SKO_ORDINARY_EXPLICIT_EMIT_ONLY,generated);
 else{const result=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve(documentFolder,'document-signature-and-edit.sql.review-only'),SKO_DOCUMENT_TRIGGER_PINS:resolve(documentFolder,'trigger-source-pins.json'),SKO_ADMIN_CANDIDATE:resolve(adminFolder,'attendance-admin-override.sql.review-only'),SKO_ADMIN_ORIGINALS:resolve(adminFolder,'native-original-sources.sql'),SKO_ORDINARY_EXPLICIT_ROOT:here}});if(result.error)throw result.error;process.exitCode=result.status??1;}
}finally{await rm(folder,{recursive:true,force:true});}
