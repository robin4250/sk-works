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
 const vehicleSource=JSON.parse(await readFile('tool/fixtures/shared_worker_facts_sources.json','utf8')).functions.find(f=>f.signature==='private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric)');
 eq(md5(dbBody(vehicleSource.definition)),vehicleSource.source_md5,'Exact observed legacy vehicle validator dependency');await exec(vehicleSource.definition);

 const ranks={aoyagi_reisho_name_supported:0,rate_formula_label:1,resolve_rate_formula:2,route_signed_checkout_sources:3,route_signed_site_rates:4,route_signed_checkout_components:5,route_billing_invoice_blocked:6,uploaded_company_seal_snapshot:7,document_company_seal_snapshot:8,ensure_unassigned_invoice_customer:9,expense_cost_components:10,route_billing_invoice_components:11};
 for(const row of dependencies.sort((a,b)=>(ranks[a.identity.match(/private\.([^ (]+)/)[1]]??100)-(ranks[b.identity.match(/private\.([^ (]+)/)[1]]??100))){eq(md5(dbBody(row.definition)),row.body_md5,'Exact dependency '+row.identity);await exec(row.definition);}
 for(const row of producers){eq(md5(dbBody(row.definition)),row.body_md5,'Exact financial producer '+row.identity);if(row.identity==='private.has_company_feature(uuid,text)')await exec('drop function private.has_company_feature(uuid,text)');await exec(row.definition);if(row.acl!==null)await exec('revoke all on function '+row.identity+' from public,anon,authenticated,service_role');}
 await exec('create trigger fixture_actual_attendance_refresh_invoice after insert or update or delete on public.attendance_entries for each row execute function private.attendance_refresh_invoice()');
 const customer=id(9901);
 await client.query("update companies set name='合成の検証会社',tax_rate=0,company_seal_style='legacy' where id=$1",[A]);
 await client.query("insert into customers(id,company_id,name) values($1,$2,'合成の取引先')",[customer,A]);
 await client.query("update sites set customer_id=$1,name='合成の現場',formal_name='合成の現場' where id=$2",[customer,SITE]);
 await client.query('insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values($1,$2,10000,0)',[A,SITE]);
 await client.query("update company_members set role='worker' where company_id=$1 and user_id in($2,$3,$4)",[A,U,memberB,memberC]);
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date,source_clock_in_id) values($1,$2,$3,$4,'clock_out',$5::date+time '17:00',$5,$6)",[id(9303),A,W2,SITE,docDay,id(9302)]);
 await sharedCall(U,id(80),'select public.reuse_my_shared_daily_report($1) v',[docStart]);
 await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(9302)]);
 const business=()=>q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r),'workers',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w),'clocks',(select jsonb_agg(to_jsonb(c) order by id) from attendance_verifications c),'entries',(select jsonb_agg(to_jsonb(e) order by id) from attendance_entries e),'payroll',(select jsonb_agg(to_jsonb(p) order by worker_id,period_start) from payroll_statements p),'invoices',(select jsonb_agg(to_jsonb(i) order by id) from invoices i),'ledger',(select jsonb_agg(to_jsonb(l) order by id) from checkout_shared_hours_private.ledger l),'confirmations',(select jsonb_agg(to_jsonb(c) order by id) from checkout_shared_hours_private.confirmations c),'events',(select jsonb_agg(to_jsonb(e) order by id) from shared_daily_report_private.signature_events e)) v");
 const snapshot=async()=>{
  const tables=(await client.query("select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p') and (n.nspname in('explicit_report_finalization_private','shared_daily_report_private','checkout_shared_hours_private','company_checkout_allowance_private','attendance_admin_override_private','management_registered_allowance_private','shared_report_edit_private','attendance_stepup_private') or (n.nspname='private' and c.relname in('reauthentication_proofs','reauthentication_rollout')) or (n.nspname='public' and c.relname in('daily_report_edit_requests','daily_report_edit_approvals','app_notifications','user_secondary_credentials'))) order by n.nspname,c.relname")).rows;
  const moduleTables={};for(const t of tables)moduleTables[t.nspname+'.'+t.relname]=await q('select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) v from '+identifier(t.nspname)+'.'+identifier(t.relname)+' t');
  return {...await business(),moduleTables,explicit:moduleTables['explicit_report_finalization_private.events'],permits:moduleTables['explicit_report_finalization_private.permits'],coordinator_events:moduleTables['explicit_report_finalization_private.coordinator_events'],coordinator_permits:moduleTables['explicit_report_finalization_private.coordinator_permits'],source_bindings:moduleTables['explicit_report_finalization_private.source_bindings']};
 };
 phase='ordinary-default-off-install';
 const actualSignature=JSON.parse(await readFile(candidateRoot+'/source-originals.json','utf8')).find(x=>x.signature==='private.save_daily_report_signature(uuid,text,text,jsonb)');
 eq(await q("select md5(prosrc) v from pg_proc where oid='private.save_daily_report_signature(uuid,text,text,jsonb)'::regprocedure"),actualSignature.body_md5,'Fixture retains the actual signature function body');
 // The inherited installer grants service_role for its separate legacy tests.
 // Match the captured production ACL before testing the strict new source guard.
 await exec('revoke execute on function private.save_daily_report_signature(uuid,text,text,jsonb) from service_role');
 const catalogueBeforeExplicit=await q("select jsonb_agg(jsonb_build_object('identity',p.oid::regprocedure::text,'oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'definer',p.prosecdef,'volatility',p.provolatile) order by p.oid::regprocedure::text) v from pg_proc p where p.oid=any(select to_regprocedure(x)::oid from unnest($1::text[]) x)",[JSON.parse(await readFile(candidateRoot+'/source-originals.json','utf8')).map(x=>x.signature)]);
 const constraintsBeforeExplicit=await q("select jsonb_agg(jsonb_build_object('name',conname,'type',contype,'definition',pg_get_constraintdef(oid,true),'validated',convalidated,'deferrable',condeferrable,'deferred',condeferred) order by conname) v from pg_constraint where conrelid='checkout_shared_hours_private.confirmations'::regclass");
 const explicitInstallSql=await readFile(candidateRoot+'/explicit-finalization.sql.review-only','utf8');
 const before=await business();await exec(explicitInstallSql);
 eq(await business(),before,'OFF installation preserves all source and financial rows');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.rollout'),0,'No company activation');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.reports'),0,'No report activation');

 phase='ordinary-unused-restore-exact-original-catalogue';
 const ordinaryOriginalSignatures=JSON.parse(await readFile(candidateRoot+'/source-originals.json','utf8')).map(x=>x.signature);
 const ordinaryCatalogue=()=>q("select jsonb_agg(jsonb_build_object('identity',p.oid::regprocedure::text,'oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'definer',p.prosecdef,'volatility',p.provolatile) order by p.oid::regprocedure::text) v from pg_proc p where p.oid=any(select to_regprocedure(x)::oid from unnest($1::text[]) x)",[ordinaryOriginalSignatures]);
 const ordinaryConstraints=()=>q("select jsonb_agg(jsonb_build_object('name',conname,'type',contype,'definition',pg_get_constraintdef(oid,true),'validated',convalidated,'deferrable',condeferrable,'deferred',condeferred) order by conname) v from pg_constraint where conrelid='checkout_shared_hours_private.confirmations'::regclass");
 const ordinaryRestoreSql=await readFile(candidateRoot+'/explicit-finalization-restore-unused.sql.review-only','utf8');
 const installedOrdinaryCatalogue=await ordinaryCatalogue(),installedOrdinaryConstraints=await ordinaryConstraints();
 await exec('create view public.fixture_external_ordinary_dependency as select explicit_report_finalization_private.required(null::uuid) needed');
 const ordinaryViewOid=await q("select 'public.fixture_external_ordinary_dependency'::regclass::oid::text v");
 const beforeBlockedRestore=await snapshot();
 await reject(()=>exec(ordinaryRestoreSql),/depend|cannot drop/i);await exec('rollback');
 eq(await q("select 'public.fixture_external_ordinary_dependency'::regclass::oid::text v"),ordinaryViewOid,'Unknown external dependency blocks restore and preserves exact external view OID');
 eq(await ordinaryCatalogue(),installedOrdinaryCatalogue,'Blocked unused restore rolls back every original function and OID');
 eq(await ordinaryConstraints(),installedOrdinaryConstraints,'Blocked unused restore rolls back coordinator confirmation constraints');
 eq(await snapshot(),beforeBlockedRestore,'Blocked unused restore preserves every source, financial and module table');
 await exec('drop view public.fixture_external_ordinary_dependency');
 await exec(ordinaryRestoreSql);
 eq(await q("select to_regnamespace('explicit_report_finalization_private') is null v"),true,'Unused restore removes only explicit new schema');
 eq(await ordinaryCatalogue(),catalogueBeforeExplicit,'Unused restore preserves exact original definition, OID, owner, ACL, config and security mode');
 eq(await ordinaryConstraints(),constraintsBeforeExplicit,'Unused restore restores original confirmation constraints');
 eq(await business(),before,'Unused restore leaves every original business and financial row unchanged');
 await exec(explicitInstallSql);
 eq(await ordinaryCatalogue(),installedOrdinaryCatalogue,'Exact reviewed candidate reinstalls after unused restore with original routine OIDs');
 eq(await ordinaryConstraints(),installedOrdinaryConstraints,'Reinstall restores exact coordinator constraints');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.events'),0,'Reinstalled unused module has no signature or financial event');

 await client.query('insert into explicit_report_finalization_private.reports(company_id,report_id,enabled) values($1,$2,true)',[A,rid]);
 const context=async(actor=U,sid=id(80))=>sharedCall(actor,sid,'select public.read_shared_daily_report_context($1) v',[rid]);
 const peer=await sharedCall(U,id(80),'select public.read_shared_worker_facts($1,$2) v',[rid,W2]);
 assert.ok(peer.proposed_worker_facts,'Explicit category and selections are required');
 eq(peer.management_confirmation_available,false,'Ordinary coordinator has no administrative confirmation role');
 eq(peer.site_coordinator_confirmation_available,false,'Unbound pre-enrollment source does not claim coordinator readiness');
 eq(peer.source_blocked,true,'An unbound closed pair remains explicitly blocked before actual submission');
 const peerFacts={...peer.proposed_worker_facts};delete peerFacts.company_allowance_legacy_labels;
 let c=await context();
 const actualPayload=JSON.stringify([worker(reportWorker,[days[0]]),worker(W2,[])]);
 await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[docStart,c.report_updated_at,'保存済み手当を含む日報',actualPayload,'合成の実報告者',signature,c.signature_scope_fingerprint]);
 const peerAfterSubmit=await sharedCall(U,id(80),'select public.read_shared_worker_facts($1,$2) v',[rid,W2]);
 eq(peerAfterSubmit.site_coordinator_confirmation_available,true,'Actual ③ source validation enables only the fixed participant scope');
 eq(peerAfterSubmit.facts_current,true,'Same ③ payload confirms actual peer facts before another participant signs');
 await reject(()=>sharedCall(U,id(80),'select public.confirm_managed_shared_worker_facts($1,$2,$3::jsonb,$4,$5,$6,$7) v',[rid,W2,JSON.stringify(peerFacts),null,peer.revision,peer.scope_fingerprint,'管理者として偽装しない']),/shared_hours_audited_management_required/);
 eq(await q('select confirmation_kind v from checkout_shared_hours_private.confirmations where report_id=$1 and worker_id=$2 order by revision desc limit 1',[rid,reportWorker]),'self','Actual actor confirms own facts as self');
 eq(await q('select confirmation_kind v from checkout_shared_hours_private.confirmations where report_id=$1 and worker_id=$2 order by revision desc limit 1',[rid,W2]),'site_coordinator','Peer facts are not falsely called self or management');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.coordinator_events where report_id=$1 and worker_id=$2 and actor_id=$3 and role=\'site_coordinator\'',[rid,W2,U]),1,'Coordinator confirmation is separately audited once');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.coordinator_permits'),0,'No reusable coordinator permit after ③');
 const afterReporter=await snapshot();
 const coordinatorFacts={...peerAfterSubmit.worker_facts};delete coordinatorFacts.company_allowance_legacy_labels;
 await reject(()=>sharedCall(U,id(80),'select public.confirm_shared_site_report_facts($1,$2,$3::jsonb,$4,$5,$6,$7) v',[rid,W2,JSON.stringify({...coordinatorFacts,overtime_hours:1}),null,peerAfterSubmit.revision,peerAfterSubmit.scope_fingerprint,null]),/explicit_report_edit_before_facts_change/);
 eq(await snapshot(),afterReporter,'Coordinator cannot attach changed facts to an old reporter signature');
 await reject(()=>sharedCall(U,id(80),'select public.confirm_shared_site_report_facts($1,$2,$3::jsonb,$4,$5,$6,$7) v',[rid,W3,JSON.stringify(coordinatorFacts),null,peerAfterSubmit.revision,peerAfterSubmit.scope_fingerprint,null]),/explicit_report_site_coordinator_unavailable/);
 eq(await snapshot(),afterReporter,'An enrolled report cannot authorize another non-roster worker');
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

 phase='ordinary-open-peer-fourth-step-preparation';
 await client.query("update company_members set role='worker' where company_id=$1 and user_id in($2,$3)",[A,U,memberB]);
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const openDay='2026-10-24',openStart=id(9500),openPeerStart=id(9502);
 await mkShift(9500,reportWorker,openDay);await mkShift(9502,W2,openDay,false);
 const openPayload=JSON.stringify([worker(reportWorker,[days[0]]),worker(W2,[])]);
 const openRid=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,openDay,'同僚の退勤前に仮保存した合成作業',openPayload]);
 await client.query('insert into explicit_report_finalization_private.reports(company_id,report_id,enabled) values($1,$2,true)',[A,openRid]);
 const openContext=(actor=U,sid=id(80))=>sharedCall(actor,sid,'select public.read_shared_daily_report_context($1) v',[openRid]);
 let stage=await openContext();
 await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[openStart,stage.report_updated_at,'同僚の退勤前に仮保存した合成作業',openPayload,'退勤済み本人の実報告者サイン',signature,stage.signature_scope_fingerprint]);
 eq(await q('select count(*)::int v from attendance_verifications where source_clock_in_id=$1 and event_type=\'clock_out\'',[openPeerStart]),0,'③ never invents the open participant clock-out');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[openRid]),0,'Open-peer provisional report creates no financial attendance');
 const unclosed=await openContext(memberB,sidB);
 eq(unclosed.explicit_finalization_ready,false,'Open participant cannot be presented as finalized/zero');
 // Synthetic source evidence only; the actual immutable-chronology trigger runs.
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date,source_clock_in_id) values($1,$2,$3,$4,'clock_out',$5::date+time '17:00',$5,$6)",[id(9503),A,W2,SITE,openDay,openPeerStart]);
 await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[openPeerStart]);
 stage=await openContext(memberB,sidB);
 const stageRequest=[openRid,stage.report_updated_at,stage.signature_scope_fingerprint,openPayload];
 const prepared=await sharedCall(memberB,sidB,'select public.prepare_shared_report_provisional_facts($1,$2::timestamptz,$3,$4::jsonb) v',stageRequest);
 eq(prepared.hours_annex.ready,true,'Same ④ preparation confirms the now-closed whole roster');
 eq(prepared.supervisor_ready,true,'Fresh facts authorize actual responsible capture');
 eq(prepared.explicit_finalization_completed,false,'Preparation is not financial completion');
 const preparedSnapshot=await snapshot();
 const preparedAgain=await sharedCall(memberB,sidB,'select public.prepare_shared_report_provisional_facts($1,$2::timestamptz,$3,$4::jsonb) v',[openRid,prepared.report_updated_at,prepared.signature_scope_fingerprint,openPayload]);
 eq(await snapshot(),preparedSnapshot,'Fresh-scope preparation retry adds no audit/financial duplicates');
 await sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[openRid,openPeerStart,'同僚が取得した実責任者サイン',signature,preparedAgain.report_updated_at,preparedAgain.signature_scope_fingerprint]);
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[openRid]),0,'④ still creates no financial attendance');
 const beforeOpenDays=[];
 for(const wid of [reportWorker,W2])beforeOpenDays.push(Number(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,wid])));
 const beforeOpenInvoice=await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]);
 stage=await openContext(memberB,sidB);const openRequest=[openRid,stage.report_updated_at,stage.signature_scope_fingerprint];
 const finishOpen=()=>sharedCall(memberB,sidB,'select public.finalize_shared_daily_report($1,$2::timestamptz,$3) v',openRequest);
 eq((await finishOpen()).explicit_finalization_completed,true,'Open-peer handoff completes only at the final ⑤');
 for(let n=0;n<2;n++)eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,[reportWorker,W2][n]]),String(beforeOpenDays[n]+1),'Each newly confirmed participant adds exactly one actual salary day');
 eq(await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),beforeOpenInvoice+20000,'Actual invoice adds exactly two participant-days at explicit 10000');
 const afterOpen=await snapshot();await finishOpen();eq(await snapshot(),afterOpen,'Open-peer finalization retry does not add financial quantities');

 phase='ordinary-off-legacy-reporter-six-key-compatibility';
 await client.query("update company_members set role='worker' where company_id=$1 and user_id=$2",[A,U]);
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const offDay='2026-10-22',offStart=id(9700);
 await mkShift(9700,reportWorker,offDay);
 const legacySix={worker_id:reportWorker,overtime_hours:0,early_hours:0,night_hours:0,allowance_amount:0,allowance_label:''};
 const offPayload=JSON.stringify([legacySix]);
 const offRid=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,offDay,'対象外の従来6項目による合成作業',offPayload]);
 const offContext=await sharedCall(U,id(80),'select public.reuse_my_shared_daily_report($1) v',[offStart]);
 const offLegacyBefore=await snapshot();
 await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[offStart,offContext.report_updated_at,'対象外の従来6項目による合成作業',offPayload,'従来方式の実報告者',signature,offContext.signature_scope_fingerprint]);
 eq(await q("select representative_signer_name='従来方式の実報告者' and representative_signature_json is not null v from daily_reports where id=$1",[offRid]),true,'OFF legacy six-key reporter input retains actual signature capture');
 const offLegacyAfter=await snapshot();
 for(const key of ['explicit','permits','coordinator_events','coordinator_permits','source_bindings'])eq(offLegacyAfter[key],offLegacyBefore[key],'OFF legacy submit creates no new explicit evidence: '+key);
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[offRid]),0,'Legacy reporter-only capture creates no financial attendance');
 eq(offLegacyAfter.payroll,offLegacyBefore.payroll,'Legacy reporter-only capture leaves actual payroll unchanged');
 eq(offLegacyAfter.invoices,offLegacyBefore.invoices,'Legacy reporter-only capture leaves actual invoices unchanged');


 phase='ordinary-legacy-document-only-real-revision';
 // Reproduce the old administrator-created document-only shape through the
 // existing APIs, never by injecting signatures or a financial status.
 await client.query("update company_members set role='owner' where company_id=$1 and user_id=$2",[A,U]);
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const legacyPayrollBefore=Number(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,reportWorker]));
 const legacyInvoiceBefore=await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]);
 const oldDay='2026-10-25',oldStart=id(9400);
 await mkShift(9400,reportWorker,oldDay);
 const oldPayload=JSON.stringify([worker(reportWorker,[days[0]],{work_category:null})]);
 const oldRid=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,oldDay,'旧保存方式の合成作業',oldPayload]);
 await client.query("insert into shared_daily_report_private.document_rollout values($1,$2,'2026-10-01',true)",[A,oldRid]);
 const oldContext=()=>sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[oldRid]);
 let old=await oldContext();
 eq(old.document_only,true,'Old document-only mode is actual server state');
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[oldRid,'representative','旧25型の実報告者',signature,old.report_updated_at,old.signature_scope_fingerprint]);
 old=await oldContext();
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[oldRid,'supervisor','旧25型の実責任者',signature,old.report_updated_at,old.signature_scope_fingerprint]);
 eq(await q('select work_category v from daily_report_workers where report_id=$1 and worker_id=$2',[oldRid,reportWorker]),null,'Historical missing category is preserved, never inferred as day');
 eq(await q("select status='draft' and representative_signature_json is not null and supervisor_signature_json is not null v from daily_reports where id=$1",[oldRid]),true,'Old both-signatures draft is recreated using actual capture RPCs');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[oldRid]),0,'Old document-only signatures created no attendance');
 await sharedCall(U,id(80),'select public.reuse_my_shared_daily_report($1) v',[oldStart]);
 await client.query('insert into explicit_report_finalization_private.reports(company_id,report_id,enabled) values($1,$2,true)',[A,oldRid]);
 old=await oldContext();
 const oldSigned=await snapshot();
 await reject(()=>sharedCall(U,id(80),'select public.finalize_shared_daily_report($1,$2::timestamptz,$3) v',[oldRid,old.report_updated_at,old.signature_scope_fingerprint]),/explicit_report_finalization_not_ready|explicit_report_actual_revision_required/);
 eq(await snapshot(),oldSigned,'Old signatures cannot be silently reused as financial approval');
 old=await sharedCall(U,id(80),'select public.start_shared_report_finalization_edit($1,$2::timestamptz,$3,$4) v',[oldRid,old.report_updated_at,old.signature_scope_fingerprint,'実際の勤務区分を入力して改めてサインを取得']);
 eq(await q("select representative_signature_json is null and supervisor_signature_json is null and status='draft' v from daily_reports where id=$1",[oldRid]),true,'Audited edit clears both current signatures before input');
 eq(await q("select exists(select 1 from explicit_report_finalization_private.events where report_id=$1 and kind='edit' and before_state#>>'{report,representative_signer_name}'='旧25型の実報告者' and before_state#>>'{report,supervisor_signer_name}'='旧25型の実責任者') v",[oldRid]),true,'Actual old signature evidence remains in immutable edit history');
 eq(await q('select work_category v from daily_report_workers where report_id=$1 and worker_id=$2',[oldRid,reportWorker]),null,'Editing alone does not manufacture a category');
 const correctedPayload=JSON.stringify([worker(reportWorker,[days[0]],{work_category:'day'})]);
 await sharedCall(U,id(80),'select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb) v',[oldRid,SITE,oldDay,'実際の勤務区分を入力した合成作業',correctedPayload]);
 eq(await q('select work_category v from daily_report_workers where report_id=$1 and worker_id=$2',[oldRid,reportWorker]),'day','Category comes from explicit fresh input');
 old=await oldContext();
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[oldRid,'representative','新たな25型の実報告者',signature,old.report_updated_at,old.signature_scope_fingerprint]);
 old=await oldContext();
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[oldRid,'supervisor','新たな25型の実責任者',signature,old.report_updated_at,old.signature_scope_fingerprint]);
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[oldRid]),0,'Fresh historical signatures still wait for explicit ⑤');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,reportWorker]),String(legacyPayrollBefore),'Historical draft is excluded from existing payroll until ⑤');
 old=await oldContext();const oldRequest=[oldRid,old.report_updated_at,old.signature_scope_fingerprint];
 const oldFinish=()=>sharedCall(U,id(80),'select public.finalize_shared_daily_report($1,$2::timestamptz,$3) v',oldRequest);
 eq((await oldFinish()).explicit_finalization_completed,true,'Actual corrected historical record commits only at ⑤');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[oldRid]),1,'Historical record creates one real source entry');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,reportWorker]),String(legacyPayrollBefore+1),'Actual producer adds exactly one newly confirmed historical date');
 eq(await q("select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation",[A,customer]),legacyInvoiceBefore+10000,'Actual invoice adds exactly one newly confirmed historical participant-day');
 const afterLegacy=await snapshot();await oldFinish();eq(await snapshot(),afterLegacy,'Historical retry does not duplicate financial rows or audit');


 phase='ordinary-reversed-registered-choice-canonical-order';
 await client.query("update company_members set role='worker' where company_id=$1 and user_id in($2,$3)",[A,U,memberB]);
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const reverseDay='2026-10-23',reverseStart=id(9600),reversePeerStart=id(9602);
 await mkShift(9600,reportWorker,reverseDay);await mkShift(9602,W2,reverseDay);
 const reversed=[days[1],days[0]],canonical=[days[0],days[1]];
 const reverseRid=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,reverseDay,'入力順が逆でも同じ登録手当を保持する合成作業',JSON.stringify([worker(reportWorker,reversed),worker(W2,[])])]);
 const stored=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[reverseRid,reportWorker]);
 eq(stored.company_allowance_selections,choices(canonical),'Unsigned writer stores both original registered selections in canonical origin/id order');
 eq(stored.company_allowance_selections.items.map(x=>x.name_snapshot).sort(),reversed.map(x=>x.name_snapshot).sort(),'Names, IDs, generation, version and unit are not lost by canonical order');
 eq(stored.allowance_label.split('\n').filter(Boolean).sort(),reversed.map(x=>x.name_snapshot).sort(),'Displayed Japanese registered names remain exact');
 eq(stored.allowance_amount,0,'Canonical order does not manufacture an adjustment amount');
 const canonicalPayload=JSON.stringify([{...worker(reportWorker,canonical),allowance_label:stored.allowance_label},worker(W2,[])]);
 await client.query('insert into explicit_report_finalization_private.reports(company_id,report_id,enabled) values($1,$2,true)',[A,reverseRid]);
 const reverseContext=(actor=U,sid=id(80))=>sharedCall(actor,sid,'select public.read_shared_daily_report_context($1) v',[reverseRid]);
 let reversedContext=await reverseContext();
 await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[reverseStart,reversedContext.report_updated_at,'入力順が逆でも同じ登録手当を保持する合成作業',canonicalPayload,'登録手当順序の実報告者',signature,reversedContext.signature_scope_fingerprint]);
 reversedContext=await reverseContext(memberB,sidB);
 await sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[reverseRid,reversePeerStart,'登録手当順序の実責任者',signature,reversedContext.report_updated_at,reversedContext.signature_scope_fingerprint]);
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[reverseRid]),0,'Reordered choices also remain provisional until ⑤');
 const beforeReverseInvoice=await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]);
 reversedContext=await reverseContext(memberB,sidB);const reversedRequest=[reverseRid,reversedContext.report_updated_at,reversedContext.signature_scope_fingerprint];
 const finishReversed=()=>sharedCall(memberB,sidB,'select public.finalize_shared_daily_report($1,$2::timestamptz,$3) v',reversedRequest);
 eq((await finishReversed()).explicit_finalization_completed,true,'Canonical raw facts materialize without changing the actual signed worker rows');
 eq(await q('select count(*)::int v from company_checkout_allowance_private.receipts where report_id=$1 and worker_id=$2',[reverseRid,reportWorker]),1,'One immutable allowance receipt per actual source');
 const actualReceipt=await q('select snapshot v from company_checkout_allowance_private.receipts where report_id=$1 and worker_id=$2',[reverseRid,reportWorker]);
 eq(actualReceipt.items.map(x=>({id:x.id,name:x.name,rate_yen:x.rate_yen})).sort((a,b)=>a.id.localeCompare(b.id)),[{id:days[0].id,name:days[0].name_snapshot,rate_yen:100},{id:days[1].id,name:days[1].name_snapshot,rate_yen:200}],'Server resolves both actual registration values, without dropping/repricing either choice');
 eq(await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),beforeReverseInvoice+20000,'Reordered allowance input still adds both actual participant-days once');
 const afterReverse=await snapshot();await finishReversed();eq(await snapshot(),afterReverse,'Canonical-order retry duplicates neither allowance receipts nor finance');


 phase='ordinary-finalized-approved-reset-held-atomically';
 // Exact observed public request/decision bodies; notification delivery uses
 // the inherited synthetic notification outbox, never external delivery.
 await exec("alter table public.daily_report_edit_requests add column if not exists reason text,add column if not exists approvals_required integer,add column if not exists created_at timestamptz default now(),add column if not exists resolved_at timestamptz;alter table public.daily_report_edit_requests alter column id set default gen_random_uuid();alter table public.daily_report_edit_requests alter column status set default 'pending';create table if not exists public.company_approval_assignees(company_id uuid,user_id uuid);create table public.daily_report_edit_approvals(request_id uuid,approver_user_id uuid,decision text,decided_at timestamptz default now(),primary key(request_id,approver_user_id));");
 const actualReportEdits=JSON.parse(await readFile('tool/fixtures/checkout_daily_report_edit_sources.json','utf8'));
 for(const f of actualReportEdits.functions){eq(md5(dbBody(f.definition)),f.source_md5,'Exact observed canonical request/approval source');await exec(f.definition);}
 await client.query('insert into company_approval_assignees(company_id,user_id) values($1,$2)',[A,memberB]);
 await client.query("update company_members set role='worker' where company_id=$1 and user_id in($2,$3)",[A,memberB,memberC]);
 const guardedRequest=await sharedCall(memberC,sidC,"select public.request_daily_report_edit($1,'確定後に本人が正規の修正申請を行う合成検証') v",[rid]);
 eq(await sharedCall(memberB,sidB,"select public.decide_daily_report_edit($1,'approve') v",[guardedRequest]),'approved','Different configured approver legitimately approves actual request');
 const approvedResetBefore=await snapshot();
 const untouchedFinalRoster=await q('select jsonb_agg(to_jsonb(w)-\'report_id\' order by worker_id) v from daily_report_workers w where report_id=$1',[rid]);
 await reject(()=>sharedCall(memberC,sidC,'select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb) v',[rid,SITE,docDay,'一般承認からの確定後resetは安全未達のため保留',JSON.stringify(untouchedFinalRoster)]),/explicit_report_finalized_edit_requires_attendance_management/);
 eq(await snapshot(),approvedResetBefore,'Refused finalized reset preserves all signatures, attendance, actual payroll/invoice, receipts and request consumption');
 eq(await q('select status v from daily_report_edit_requests where id=$1',[guardedRequest]),'approved','Safe refusal does not consume legitimate approval');



 phase='ordinary-legacy-freeform-nonzero-cash-safe-hold';
 // Construct historical pre-rollout input only via its real old public writer.
 // Temporarily changing a synthetic rollout models that earlier state; no
 // signature, status, attendance projection or money is injected directly.
 await client.query("update shared_daily_report_private.rollout set enabled=false where company_id=$1",[A]);
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[memberC,sidC]);
 const cashDay='2026-10-20',cashStart=id(9800),cashNames='旧自由手当\n旧追加手当',cashAmount=1375;
 await mkShift(9800,W3,cashDay);
 const oldCashWorker={worker_id:W3,overtime_hours:0,early_hours:0,night_hours:0,allowance_amount:cashAmount,allowance_label:cashNames};
 const cashRid=await sharedCall(memberC,sidC,'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,cashDay,'旧方式から保持する調整額つき合成記録',JSON.stringify([oldCashWorker])]);
 eq(await q('select company_allowance_selections v from daily_report_workers where report_id=$1 and worker_id=$2',[cashRid,W3]),null,'Actual legacy omitted choice key starts as NULL');
 const typedCashWorker=worker(W3,[],{allowance_amount:cashAmount,allowance_label:cashNames,company_allowance_legacy_labels:cashNames});
 await sharedCall(memberC,sidC,'select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb) v',[cashRid,SITE,cashDay,'旧方式から保持する調整額つき合成記録',JSON.stringify([typedCashWorker])]);
 const preservedCash=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[cashRid,W3]);
 eq(preservedCash.company_allowance_selections,choices([]),'Actual unsigned old NULL upgrades to explicitly validated empty registered choices');
 eq(preservedCash.allowance_amount,cashAmount,'NULL-to-empty upgrade never zeroes an existing nonzero adjustment');
 eq(preservedCash.allowance_label,cashNames,'NULL-to-empty upgrade retains every displayed freeform legacy name');
 eq(preservedCash.company_allowance_legacy_labels,cashNames,'Legacy names remain separate from registered identities');
 await client.query("update shared_daily_report_private.rollout set enabled=true where company_id=$1",[A]);
 await client.query('insert into explicit_report_finalization_private.reports(company_id,report_id,enabled) values($1,$2,true)',[A,cashRid]);
 const cashContext=await sharedCall(memberC,sidC,'select public.reuse_my_shared_daily_report($1) v',[cashStart]);
 const cashBefore=await snapshot();
 await reject(()=>sharedCall(memberC,sidC,'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[cashStart,cashContext.report_updated_at,'旧方式から保持する調整額つき合成記録',JSON.stringify([typedCashWorker]),'調整額を消して進めない',signature,cashContext.signature_scope_fingerprint]),/shared_report_manual_cash_requires_trusted_source/);
 eq(await snapshot(),cashBefore,'Unsupported nonzero adjustment is held atomically with every label/value/source/financial row unchanged');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[cashRid]),0,'Unsupported legacy adjustment is never reported as finalized finance');

 phase='ordinary-highest-management-real-03-04-05-install';
 await exec('alter table company_common_allowance_private.items add column if not exists position integer default 0');
 const managementRoot=candidateRoot+'/../management-registered-allowances-candidate';
 for(const row of JSON.parse(await readFile(managementRoot+'/native-reader-sources.json','utf8'))){eq(md5(dbBody(row.definition)),row.source_md5,'Exact observed management options reader');await exec(row.definition);}
 await exec("create function public.read_company_registered_allowance_labels(p_company_id uuid) returns jsonb language sql stable set search_path='' as $$select company_common_allowance_private.registered_labels(p_company_id)$$");
 await exec(await readFile(managementRoot+'/management-registered-allowances.sql.review-only','utf8'));
 await exec('create schema extensions;create extension pgcrypto with schema extensions;alter table auth.users add column encrypted_password text');
 await exec("create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;create or replace function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role',coalesce(nullif(current_setting('fixture.role',true),''),'authenticated'),'sub',current_setting('fixture.actor',true),'session_id',coalesce(nullif(current_setting('fixture.sid',true),''),'00000000-0000-0000-0000-000000000080'),'is_anonymous',false)$$;");
 await exec("create table private.account_deletion_access_restrictions(user_id uuid primary key);create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;create table private.master_admins(user_id uuid primary key,enabled boolean);create function public.is_current_user_master_admin() returns boolean language sql security definer set search_path='' as $$select exists(select 1 from private.master_admins where user_id=auth.uid() and enabled)$$;create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts integer not null default 0,locked_until timestamptz,updated_at timestamptz);alter table public.user_secondary_credentials enable row level security;revoke all on public.user_secondary_credentials from public,anon,authenticated;create table private.master_feature_settings(feature_key text primary key,enabled boolean,updated_at timestamptz,updated_by uuid);create function public.current_master_feature_flags() returns jsonb language sql as $$select '{}'::jsonb$$;");
 await exec(await readFile('supabase/tests/fixtures/secondary_reset_before.sql','utf8'));
 await exec(await readFile('supabase/tests/fixtures/reauthentication_master_before.sql','utf8'));
 await exec(await readFile('tool/staged/reauthentication_proofs.sql','utf8'));
 await exec(await readFile('docs/review/security-server-stepup-candidate/verify_secondary_password.source.sql','utf8'));
 await exec('revoke all on function public.verify_secondary_password(text) from public,anon;grant execute on function public.verify_secondary_password(text) to authenticated');
 const beforeProofForceOid=await q("select 'public.force_manage_attendance(text,jsonb)'::regprocedure::oid v");
 await exec(await readFile('tool/staged/attendance_reauthentication.sql','utf8'));
 eq(await q("select 'public.force_manage_attendance(text,jsonb)'::regprocedure::oid v"),beforeProofForceOid,'05 retains public force OID after 03 and explicit candidate');
 eq(await q("select count(*)::int v from private.reauthentication_rollout where enabled"),0,'04 and 05 install with no proof activation');
 const managementUser=id(9850),managementSid=id(9851);
 await client.query('insert into auth.users(id) values($1)',[managementUser]);
 await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[managementSid,managementUser]);
 await client.query("insert into company_members(company_id,user_id,role) values($1,$2,'owner')",[A,managementUser]);
 await sharedCall(managementUser,managementSid,"select public.set_secondary_password('synthetic-highest-management-known') v");
 await client.query('insert into attendance_admin_override_private.rollout values($1,true)',[A]);
 await client.query('insert into management_registered_allowance_private.rollout values($1,true)',[A]);
 await client.query("update private.reauthentication_rollout set enabled=true where scope in('attendance_management','secondary_password')");
 await exec("select set_config('fixture.manager','on',false)");
 await client.query("insert into explicit_report_finalization_private.rollout(company_id,starts_on,new_report_from,enabled) values($1,'2026-10-01','2026-10-01',true)",[A]);
 const managementCell=(wid,day,extra={})=>({worker_id:wid,date:day,mode:'work',site_id:SITE,man_days:1,overtime_hours:0,early_hours:0,night_hours:0,allowance_names:[],work_description:'最高管理権限による実入力',clock_in:'08:00',clock_out:'17:00',...extra});
 const targetFor=(actor,sid,action,items)=>sharedCall(actor,sid,'select public.attendance_management_reauthentication_target($1,$2::jsonb) v',[action,JSON.stringify(items)]);
 const withManagementProof=async(action,items)=>{
  const target=await targetFor(managementUser,managementSid,action,items);
  const nonce=createHash('sha256').update('management-'+Math.random()).digest('hex');
  assert.ok(await sharedCall(managementUser,managementSid,'select public.issue_secondary_reauthentication_proof($1,$2::jsonb,$3,$4) v',['attendance.manage',JSON.stringify(target),createHash('sha256').update(nonce).digest('hex'),'synthetic-highest-management-known']));
  return sharedCall(managementUser,managementSid,'select public.force_manage_attendance_with_proof($1,$2::jsonb,$3) v',[action,JSON.stringify(items),nonce]);
 };
 const noManagerBefore=await snapshot();
 await reject(()=>targetFor(memberB,sidB,'delete',[managementCell(reportWorker,docDay,{mode:'off'})]),/attendance management permission required|attendance_admin_current_management_required|attendance_reauthentication_/);
 eq(await snapshot(),noManagerBefore,'Ordinary participant cannot impersonate highest management through a client-side permission hint');
 await reject(()=>sharedCall(managementUser,managementSid,'select public.force_manage_attendance($1,$2::jsonb) v',['upsert',JSON.stringify([managementCell(reportWorker,docDay)])]),/reauthentication_required/);
 phase='ordinary-highest-management-finalized-edit-delete-and-new';
 const originalAdminReport=await q('select to_jsonb(r) v from daily_reports r where id=$1',[rid]);
 const originalAdminReceipt=await q('select to_jsonb(r) v from attendance_entries a join company_checkout_allowance_private.receipts r on r.id=a.company_allowance_receipt_id where a.source_report_id=$1 and a.worker_id=$2',[rid,reportWorker]);
 const beforeAdminPayroll=[];for(const wid of [reportWorker,W2])beforeAdminPayroll.push(Number(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,wid])));
 const beforeAdminInvoice=await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]);
 const originalPeerRow=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[rid,W2]);
 eq(await withManagementProof('upsert',[managementCell(reportWorker,docDay,{work_description:'確定済みを正規最高管理権限で修正',company_allowance_selections:choices([days[1]]),company_allowance_legacy_labels:''})]),1,'Actual highest management edits finalized report through 03+05');
 eq(await q("select representative_signature_json is null and supervisor_signature_json is null and status='draft' v from daily_reports where id=$1",[rid]),true,'Management revision does not forge/reuse old signatures');
 eq(await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[rid,W2]),originalPeerRow,'Management edits only selected worker');
 eq(await q("select exists(select 1 from attendance_admin_override_private.operations o where state='committed' and exists(select 1 from jsonb_array_elements(o.before_state->'reports') d where d->'report'=$1::jsonb)) v",[JSON.stringify(originalAdminReport)]),true,'Management audit preserves actual old final signature report');
 const adminSourceReceipt=await q('select r.snapshot v from attendance_entries a join company_checkout_allowance_private.receipts r on r.id=a.company_allowance_receipt_id where a.source_report_id=$1 and a.worker_id=$2',[rid,reportWorker]);
 eq(adminSourceReceipt.authority.kind,'attendance_management','03 registered receipt declares management authority honestly');
 eq(adminSourceReceipt.authority.actor_id,managementUser,'03 receipt carries actual highest management identity');
 eq(adminSourceReceipt.items[0].id,days[1].id,'Highest edit explicitly changes registered identity to the other valid item');
 eq(adminSourceReceipt.items[0].rate_yen,200,'Changed choice captures actual trusted registered price 200');
 eq(await q('select to_jsonb(r) v from company_checkout_allowance_private.receipts r where id=$1',[originalAdminReceipt.id]),originalAdminReceipt,'Highest edit preserves original 100-yen receipt history exactly');
 eq(await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),beforeAdminInvoice,'Editing a confirmed cell once does not duplicate invoice participant-days');
 eq(await withManagementProof('delete',[managementCell(reportWorker,docDay,{mode:'off'})]),1,'Actual highest management deletes selected finalized attendance after proof');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1 and worker_id=$2',[rid,reportWorker]),0,'Selected attendance removed');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1 and worker_id=$2',[rid,W2]),1,'Unselected peer attendance retained');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,reportWorker]),String(beforeAdminPayroll[0]-1),'Actual highest deletion removes only selected salary day');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,W2]),String(beforeAdminPayroll[1]),'Actual highest deletion preserves peer salary days');
 eq(await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),beforeAdminInvoice-10000,'Actual highest deletion removes exactly selected invoice participant-day');
 const createDay='2026-10-21';
 eq(await withManagementProof('upsert',[managementCell(W3,createDay,{company_allowance_selections:choices([days[0]]),company_allowance_legacy_labels:'正規管理入力の自由記録'})]),1,'Highest management creates new actual attendance with registered ID plus free label');
 const createdAdminRid=await q('select source_report_id v from attendance_entries where company_id=$1 and worker_id=$2 and work_date=$3',[A,W3,createDay]);
 eq(await q('select representative_signature_json is null and supervisor_signature_json is null v from daily_reports where id=$1',[createdAdminRid]),true,'New management source does not manufacture handwritten signatures');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,W3]),'1','Actual highest new source creates exactly one salary day');
 eq(await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),beforeAdminInvoice,'Actual highest new source adds exactly one invoice participant-day');
 eq(await q('select count(*)::int v from attendance_admin_override_private.contexts'),0,'Highest operations leave no reusable management permit');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.management_reports where report_id in($1,$2)',[rid,createdAdminRid]),2,'Explicit module records truthful management-only exceptions for changed and new report');
 phase='ordinary-highest-management-last-enrolled-worker-cancellation';
 eq(await q('select count(*)::int v from daily_report_workers where report_id=$1',[rid]),1,'Last-worker case starts from the actually enrolled report with only the preserved peer');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.states where report_id=$1',[rid]),1,'Last-worker case exercises a real explicit state FK');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.reports where report_id=$1',[rid]),1,'Last-worker case exercises an actual explicit report enrollment FK');
 eq(await q('select count(*)::int v from explicit_report_finalization_private.management_reports where report_id=$1',[rid]),1,'Last-worker case exercises an actual management marker FK');
 const lastReportBefore=await q('select to_jsonb(r) v from daily_reports r where id=$1',[rid]);
 const lastWorkerBefore=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1',[rid]);
 const priorLastAudit=await q("select jsonb_agg(to_jsonb(o) order by id) v from attendance_admin_override_private.operations o where exists(select 1 from jsonb_array_elements(o.before_state->'reports') d where d#>>'{report,id}'=$1::text)",[rid]);
 const priorLastEvents=await q('select jsonb_agg(to_jsonb(e) order by id) v from explicit_report_finalization_private.events e where report_id=$1',[rid]);
 const otherLastSources=()=>q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r where id<>$1),'workers',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w where report_id<>$1),'entries',(select jsonb_agg(to_jsonb(e) order by id) from attendance_entries e where source_report_id is distinct from $1),'other_salary',(select jsonb_agg(to_jsonb(p) order by worker_id,period_start) from payroll_statements p where worker_id<>$2)) v",[rid,W2]);
 const lastOtherBefore=await otherLastSources();
 const beforeLastDays=Number(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,W2]));
 const beforeLastInvoice=await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]);
 eq(await withManagementProof('delete',[managementCell(W2,docDay,{mode:'off'})]),1,'Actual 03+05 proof deletes the last worker of a real explicitly enrolled report');
 eq(await q('select count(*)::int v from daily_reports where id=$1',[rid]),1,'Audited last-worker deletion preserves its historical parent report');
 eq(await q('select count(*)::int v from daily_report_workers where report_id=$1',[rid]),0,'Audited cancellation removes the last current worker');
 eq(await q('select active v from attendance_admin_override_private.cancellations where report_id=$1',[rid]),true,'Last-worker report is explicitly cancelled by the genuine audited writer');
 eq(await sharedCall(memberB,sidB,'select count(*)::int v from public.daily_reports where id=$1',[rid]),0,'Cancelled historical report is hidden from the ordinary participant list');
 await reject(()=>sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[rid]),/shared_report_member_required|shared_report_unavailable|cancelled/);
 for(const table of ['states','reports','management_reports'])eq(await q('select count(*)::int v from explicit_report_finalization_private.'+table+' where report_id=$1',[rid]),1,'Audited parent preservation also retains its valid explicit FK row: '+table);
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[rid]),0,'Last-worker deletion removes its last attendance projection');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,W2]),String(beforeLastDays-1),'Actual payroll loses exactly the final selected participant-day');
 eq(await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),beforeLastInvoice-10000,'Actual invoice loses exactly the final selected participant-day');
 eq(await otherLastSources(),lastOtherBefore,'Last-worker deletion preserves every other report/day/employee source and other employee payroll');
 for(const oldAudit of priorLastAudit??[])eq(await q('select to_jsonb(o) v from attendance_admin_override_private.operations o where id=$1',[oldAudit.id]),oldAudit,'Last-worker deletion retains earlier original-signature management audits byte-identically');
 for(const oldEvent of priorLastEvents??[])eq(await q('select to_jsonb(e) v from explicit_report_finalization_private.events e where id=$1',[oldEvent.id]),oldEvent,'Last-worker deletion retains original signing/finalization evidence byte-identically');
 eq(await q("select exists(select 1 from attendance_admin_override_private.operations o where state='committed' and action='delete' and exists(select 1 from jsonb_array_elements(o.before_state->'reports') d where d->'report'=$1::jsonb and d->'roster' @> jsonb_build_array($2::jsonb))) v",[JSON.stringify(lastReportBefore),JSON.stringify(lastWorkerBefore)]),true,'Last-worker committed cancellation audit preserves the actual historical report and removed final roster row');
 eq(await q('select count(*)::int v from attendance_admin_override_private.contexts'),0,'Last-worker delete leaves no live reusable management context');

 phase='ordinary-used-restore-refused-atomically';
 const usedOrdinaryCatalogue=await ordinaryCatalogue(),usedOrdinaryConstraints=await ordinaryConstraints(),usedOrdinarySnapshot=await snapshot();
 await reject(()=>exec(ordinaryRestoreSql),/explicit_finalization_restore_used_module|explicit_finalization_restore_enabled_module/);await exec('rollback');
 eq(await ordinaryCatalogue(),usedOrdinaryCatalogue,'Used restore refuses without changing any active original function');
 eq(await ordinaryConstraints(),usedOrdinaryConstraints,'Used restore refuses without changing active confirmation constraints');
 eq(await snapshot(),usedOrdinarySnapshot,'Used restore preserves every original signature, financial row, module receipt, proof and audit');

 console.log(JSON.stringify({pass:true,checks,native_pg17:true,signature_capture_deferred:true,actual_four_financial_producers:true,ordinary_site_coordinator_and_peer_handoff:true,actual_invoice_non_route_dependencies:true,actual_payroll_one_day_per_participant:true,invoice_one_customer_month:true,error_and_early_return_atomic_rollback:true,exact_retry_idempotent:true,synthetic_auth_and_neutral_tax_leave:true,open_peer_same_fourth_step_preparation:true,off_legacy_six_keys_reporter:true,legacy_document_audited_revision:true,reversed_registered_choices_preserved:true,finalized_general_approved_reset_held_atomically:true,highest_crud_with_actual_03_04_05:true,last_enrolled_worker_audited_cancellation:true,physical_report_delete_branch_covered:false,legacy_freeform_and_nonzero_amount_preserved_then_held:true,legacy_cash_positive_finance_covered:false,production_changed:false}));
`;
 const proof=join(folder,'proof.mjs'),generated=setup+unit+tail;await writeFile(proof,generated);
 if(process.env.SKO_ORDINARY_EXPLICIT_EMIT_ONLY)await writeFile(process.env.SKO_ORDINARY_EXPLICIT_EMIT_ONLY,generated);
 else{const result=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve(documentFolder,'document-signature-and-edit.sql.review-only'),SKO_DOCUMENT_TRIGGER_PINS:resolve(documentFolder,'trigger-source-pins.json'),SKO_ADMIN_CANDIDATE:resolve(adminFolder,'attendance-admin-override.sql.review-only'),SKO_ADMIN_ORIGINALS:resolve(adminFolder,'native-original-sources.sql'),SKO_ORDINARY_EXPLICIT_ROOT:here}});if(result.error)throw result.error;process.exitCode=result.status??1;}
}finally{await rm(folder,{recursive:true,force:true});}
