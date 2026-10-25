// Disposable PG17 module proof. Original sign/lock sources, synthetic auth and
// payroll-refresh surroundings. Full production refresh integration is separate.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const url=new URL(process.env.SKO_SHARED_MANAGED_FIXTURE_URL??'');
assert.equal(process.env.CI,'true');assert.equal(process.platform,'linux');
assert.ok(['127.0.0.1','localhost'].includes(url.hostname));
assert.equal(url.username,'postgres');assert.equal(url.password,'fixture-only');
assert.equal(url.pathname,'/sko_shared_managed_fixture');
for(const key of ['DATABASE_URL','SUPABASE_URL','SUPABASE_DB_URL','SUPABASE_SERVICE_ROLE_KEY'])assert.equal(process.env[key],undefined);
const pg=(await import(process.argv[2])).default;
const db=new pg.Client({connectionString:url.toString()});await db.connect();
let checks=0;const eq=(a,b,m)=>{assert.deepEqual(a,b,m);checks++;};
const q=async(sql,args=[])=>{const r=await db.query(sql,args);return r.rows[0]?.v;};
const reject=async(operation,pattern)=>{await assert.rejects(operation,pattern);checks++;};
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const C=id(1),MANAGER=id(2),MEMBER=id(3),W=id(4),W2=id(5),SITE=id(6);
try{
 for(const name of ['anon','authenticated','service_role']){
  await db.query(`do $$begin if not exists(select 1 from pg_roles where rolname='${name}') then create role ${name};end if;end $$`);
 }
 await db.query(`
 create schema auth;create schema private;create schema payroll_scope_private;
 create schema company_checkout_allowance_private;create schema checkout_report_registration_private;
 create schema checkout_shared_hours_private;create schema shared_worker_facts_private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function checkout_report_registration_private.current_actor() returns uuid language plpgsql stable as $$begin
  if auth.uid() is null then raise exception 'fixture actor missing';end if;return auth.uid();end$$;
 create table companies(id uuid primary key);
 create table workers(id uuid primary key,company_id uuid,user_id uuid);
 create table company_members(company_id uuid,user_id uuid,can_manage boolean);
 create function private.has_company_feature(cid uuid,feature text) returns boolean language sql stable as $$
  select exists(select 1 from company_members where company_id=cid and user_id=auth.uid() and can_manage and feature='can_manage_attendance')$$;
 create table daily_reports(id uuid primary key,company_id uuid,site_id uuid,route_assignment_id uuid,report_date date,
  status text default 'draft',signer_name text,signature_json jsonb,signed_at timestamptz,updated_by uuid,
  updated_at timestamptz default clock_timestamp(),representative_signer_name text,representative_signature_json jsonb,
  supervisor_signer_name text,supervisor_signature_json jsonb);
 create table daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric default 0,early_hours numeric default 0,
  night_hours numeric default 0,allowance_amount integer default 0,allowance_label text,work_category text default 'day',
  company_allowance_selections jsonb default '{"contract_version":1,"items":[]}',vehicle_id uuid,route_assignment_id uuid,odometer_km numeric);
 create table attendance_entries(id uuid primary key default gen_random_uuid(),company_id uuid,worker_id uuid,work_date date,
  site_id uuid,route_assignment_id uuid,base_man_days numeric default 1,overtime_hours numeric default 0,early_hours numeric default 0,
  night_hours numeric default 0,allowance_amount integer default 0,notes text,work_category text default 'day',allowance_names text[] default '{}',
  source_report_id uuid,company_allowance_receipt_id uuid,created_by uuid,updated_by uuid,
  created_at timestamptz default clock_timestamp(),updated_at timestamptz default clock_timestamp());
 create table attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,work_date date,
  site_id uuid,route_assignment_id uuid,event_type text,source_clock_in_id uuid,confirmed_at timestamptz);
 create table payroll_statements(id uuid primary key,company_id uuid,worker_id uuid,period_start date,
  gross_pay integer,deductions integer,net_pay integer,detail jsonb,automatic_calculation boolean default true,
  workflow_state text default 'draft',approved_ids uuid[] default '{}',finalized_at timestamptz,finalized_by uuid,
  retained_finalized_by uuid,updated_at timestamptz default clock_timestamp());
 create table checkout_shared_hours_private.work_protocol(report_id uuid primary key);
 create function checkout_shared_hours_private.uses_contract(rid uuid) returns boolean language sql stable as $$
  select exists(select 1 from checkout_shared_hours_private.work_protocol where report_id=rid)$$;
 create table checkout_shared_hours_private.confirmations(id bigint generated always as identity primary key,
  report_id uuid,worker_id uuid,company_id uuid,work_date date,revision bigint,source_kind text,
  worker_facts jsonb,source_fingerprint text,confirmed_by uuid,confirmation_kind text,management_reason text);
 create table checkout_shared_hours_private.supervisor_contexts(id bigint generated always as identity primary key,
  report_id uuid,transaction_id bigint,actor_id uuid);
 create table checkout_shared_hours_private.materialization_permits(report_id uuid,worker_id uuid,transaction_id bigint,
  actor_id uuid,supervisor_context_id bigint,expected_facts jsonb,expected_facts_sha256 text);
 create table invalidation_log(cid uuid,wid uuid,day_value date);
 create function checkout_shared_hours_private.invalidate_worker_day(cid uuid,wid uuid,day_value date)
  returns void language plpgsql as $$declare d record;begin
   insert into invalidation_log values(cid,wid,day_value);
   for d in select * from checkout_shared_managed_private.adoptions a where a.company_id=cid and a.worker_id=wid
    and a.work_date=day_value and a.transaction_id=txid_current() and a.actor_id=auth.uid() loop
    if checkout_shared_managed_private.managed_source_scope(d.report_id,wid)->>'source_fingerprint' is distinct from d.source_fingerprint then
     raise exception 'fixture_inflight_source_alias_missing';end if;
   end loop;
  end$$;
 create function company_checkout_allowance_private.capture_report(rid uuid) returns jsonb language sql as $$select '{}'::jsonb$$;
 create table company_checkout_allowance_private.receipts(id uuid primary key,company_id uuid,worker_id uuid,work_date date,report_id uuid);
 create function payroll_scope_private.report_sources(rid uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('scopes',coalesce(jsonb_agg(jsonb_build_object('cid',r.company_id,'wid',w.worker_id,'day',r.report_date) order by w.worker_id),'[]'))
  from daily_reports r join daily_report_workers w on w.report_id=r.id where r.id=rid$$;
 `);
 const sources=JSON.parse(await readFile('tool/fixtures/shared_managed_actual_writers.json','utf8'));
 for(const f of sources.functions){await db.query(f.definition);eq(await q('select md5(prosrc) v from pg_proc where oid=to_regprocedure($1)',[f.signature]),f.source_md5,'Exact observed deployed writer body');}
 await db.query(await readFile('docs/candidates/checkout_shared_managed_source.sql.review-only','utf8'));
 await db.query('insert into companies values($1)',[C]);
 await db.query('insert into workers values($1,$2,null),($3,$2,null)',[W,C,W2]);
 await db.query('insert into company_members values($1,$2,true),($1,$3,false)',[C,MANAGER,MEMBER]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[MANAGER]);
 const facts={schema:1,overtime_hours:0,early_hours:0,night_hours:0,work_category:'day',allowance_amount:0,
  allowance_label:null,company_allowance_selections:{contract_version:1,items:[]},company_allowance_legacy_labels:null,
  vehicle_id:null,route_assignment_id:null,odometer_km:null};
 const setup=async(n,day)=>{
  const rid=id(n),ae=id(n+1);
  await db.query('insert into daily_reports(id,company_id,site_id,report_date,representative_signer_name,representative_signature_json) values($1,$2,$3,$4,\'reporter\',\'{"strokes":[[1]]}\')',[rid,C,SITE,day]);
  await db.query('insert into daily_report_workers(report_id,worker_id) values($1,$2)',[rid,W]);
  await db.query('insert into attendance_entries(id,company_id,worker_id,work_date,site_id,created_by) values($1,$2,$3,$4,$5,$6)',[ae,C,W,day,SITE,MANAGER]);
  await db.query('insert into checkout_shared_hours_private.work_protocol values($1)',[rid]);
  const source=await q('select checkout_shared_managed_private.managed_source_scope($1,$2) v',[rid,W]);
  const cid=await q("insert into checkout_shared_hours_private.confirmations(report_id,worker_id,company_id,work_date,revision,source_kind,worker_facts,source_fingerprint,confirmed_by,confirmation_kind,management_reason) values($1,$2,$3,$4,1,'managed_attendance',$5,$6,$7,'management','既存手入力の原本確認') returning id v",[rid,W,C,day,JSON.stringify(facts),source.source_fingerprint,MANAGER]);
  await db.query('select checkout_shared_managed_private.record_manager_confirmation($1,$2,$3,$4,$5)',[rid,W,cid,source.source_fingerprint,JSON.stringify(facts)]);
  return{rid,ae,source,cid};
 };
 await db.query("insert into payroll_statements(id,company_id,worker_id,period_start,gross_pay,deductions,net_pay,detail) values($1,$2,$3,'2026-10-01',20000,0,20000,'{\"基本給\":20000,\"出勤日数\":1,\"unit_resolution\":{\"items\":[]}}')",[id(10),C,W]);
 const first=await setup(100,'2026-10-21');
 eq(first.source.blocked,false,'A genuine manager manual entry without GPS or employee auth UID is eligible');
 eq(await q('select count(*)::int v from attendance_verifications'),0,'No fabricated AV');
 await reject(()=>db.query('select checkout_shared_managed_private.validate_managed_facts($1,$2,$3)',[first.rid,W,JSON.stringify({...facts,overtime_hours:1})]),/confirmed_facts_differ/);
 await reject(()=>db.query('select checkout_shared_managed_private.prepare_managed_adoption($1,$2,$3,$4)',[first.rid,W,first.source.source_fingerprint,JSON.stringify(facts)]),/permit_required/);
 const prepare=async(item)=>{
  const context=await q('insert into checkout_shared_hours_private.supervisor_contexts(report_id,transaction_id,actor_id) values($1,txid_current(),auth.uid()) returning id v',[item.rid]);
  await db.query('insert into checkout_shared_hours_private.materialization_permits values($1,$2,txid_current(),auth.uid(),$3,$4,checkout_shared_managed_private.row_sha256($4))',[item.rid,W,context,JSON.stringify(facts)]);
  await db.query('select checkout_shared_managed_private.prepare_managed_adoption($1,$2,$3,$4)',[item.rid,W,item.source.source_fingerprint,JSON.stringify(facts)]);
 };
 const originalSign=async(item)=>{
  await db.query("update daily_reports set supervisor_signer_name='actual supervisor',supervisor_signature_json='{\"strokes\":[[2]]}' where id=$1",[item.rid]);
  await db.query("select public.sign_daily_report($1,'actual supervisor',jsonb_build_object('version',3,'representative',r.representative_signature_json,'supervisor',r.supervisor_signature_json)) from daily_reports r where r.id=$1",[item.rid]);
 };
 const originalPayroll=await q('select checkout_shared_managed_private.payroll_vector($1,$2,$3) v',[C,W,'2026-10-21']);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[MEMBER]);
 await db.query('begin');await prepare(first);
 eq((await q('select checkout_shared_managed_private.managed_source_scope($1,$2) v',[first.rid,W])).source_fingerprint,first.source.source_fingerprint,'Only exact audited NULL-to-report binding preserves basis');
 await originalSign(first);
 await db.query('select checkout_shared_managed_private.assert_managed_adoption_unchanged($1)',[first.rid]);await db.query('commit');
 eq(await q('select id v from attendance_entries where source_report_id=$1',[first.rid]),first.ae,'Original sign reuses original AE identity');
 eq(await q('select checkout_shared_managed_private.payroll_vector($1,$2,$3) v',[C,W,'2026-10-21']),originalPayroll,'Currency components remain byte-equal');
 eq((await q('select checkout_shared_managed_private.managed_source_scope($1,$2) v',[first.rid,W])).source_fingerprint,first.source.source_fingerprint,'Verified exact stamp alias remains source-stable');
 eq(await q('select count(*)::int v from checkout_shared_managed_private.adoptions'),1,'Immutable original AE audit retained');
 await reject(()=>db.query("update checkout_shared_managed_private.adoptions set before_entry='{}'"),/audit_is_immutable/);
 await db.query("update payroll_statements set workflow_state='finalized' where id=$1",[id(10)]);
 eq((await q('select checkout_shared_managed_private.managed_source_scope($1,$2) v',[first.rid,W])).blocked,false,'Later salary finalization does not invalidate verified source history');
 await db.query("update payroll_statements set workflow_state='draft' where id=$1",[id(10)]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[MANAGER]);
 const drift=await setup(200,'2026-10-22');
 const beforeDrift=await q("select jsonb_build_object('entry',(select to_jsonb(a) from attendance_entries a where id=$1),'report',(select to_jsonb(r) from daily_reports r where id=$2),'payroll',(select to_jsonb(p) from payroll_statements p where id=$3)) v",[drift.ae,drift.rid,id(10)]);
 await db.query('begin');await prepare(drift);
 await reject(()=>db.query('update attendance_entries set overtime_hours=1 where id=$1',[drift.ae]),/inflight_row_changed/);await db.query('rollback');
 eq(await q('select source_report_id v from attendance_entries where id=$1',[drift.ae]),null,'Private transaction context cannot bless changed factual or numeric fields');
 await db.query('begin');await prepare(drift);await originalSign(drift);
 await reject(()=>db.query('commit'),/unverified_commit_forbidden/);await db.query('rollback');
 eq(await q('select source_report_id v from attendance_entries where id=$1',[drift.ae]),null,'Omitted post-sign proof cannot commit adoption');
 await db.query('begin');await prepare(drift);await originalSign(drift);
 // Explicit synthetic drift models a downstream recalculator changing money;
 // the module must abort, never silently repair or declare adoption complete.
 await db.query('update payroll_statements set gross_pay=21000,net_pay=21000 where id=$1',[id(10)]);
 await reject(()=>db.query('select checkout_shared_managed_private.assert_managed_adoption_unchanged($1)',[drift.rid]),/financial_vector_changed_pending/);await db.query('rollback');
 eq(await q("select jsonb_build_object('entry',(select to_jsonb(a) from attendance_entries a where id=$1),'report',(select to_jsonb(r) from daily_reports r where id=$2),'payroll',(select to_jsonb(p) from payroll_statements p where id=$3)) v",[drift.ae,drift.rid,id(10)]),beforeDrift,'Financial drift rolls back pointer, signature, money and audit together');
 await db.query('begin');await prepare(drift);await originalSign(drift);
 await db.query('select checkout_shared_managed_private.assert_managed_adoption_unchanged($1)',[drift.rid]);
 await db.query('update payroll_statements set gross_pay=21000,net_pay=21000 where id=$1',[id(10)]);
 await reject(()=>db.query('commit'),/financial_vector_changed_pending/);await db.query('rollback');
 eq(await q('select source_report_id v from attendance_entries where id=$1',[drift.ae]),null,'Later same-transaction money drift cannot bypass a previously successful assertion');
 await db.query("update payroll_statements set workflow_state='approval_pending' where id=$1",[id(10)]);
 await db.query('begin');await reject(()=>prepare(drift),/source_or_financial_scope_changed/);await db.query('rollback');
 eq(await q('select source_report_id v from attendance_entries where id=$1',[drift.ae]),null,'Approval-protected salary never adopts a manual AE');
 await db.query("update payroll_statements set workflow_state='draft' where id=$1",[id(10)]);
 await db.query('update attendance_entries set source_report_id=$2 where id=$1',[drift.ae,id(999)]);
 eq((await q('select checkout_shared_managed_private.managed_source_scope($1,$2) v',[drift.rid,W])).blocked,true,'Another report pointer is never overwritten');
 await db.query('update attendance_entries set source_report_id=null,base_man_days=0.5 where id=$1',[drift.ae]);
 eq((await q('select checkout_shared_managed_private.managed_source_scope($1,$2) v',[drift.rid,W])).blocked,true,'Fractional original day cannot be silently converted to one day');
 await db.query('update attendance_entries set base_man_days=1 where id=$1',[drift.ae]);
 await db.query('delete from invalidation_log');
 await db.query("update attendance_entries set work_date='2026-10-24',worker_id=$2 where id=$1",[drift.ae,W2]);
 eq(await q('select jsonb_agg(jsonb_build_array(wid,day_value) order by wid,day_value) v from invalidation_log'),[[W,'2026-10-22'],[W2,'2026-10-24']],'OLD and NEW canonical scopes both invalidate');
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[MEMBER]);
 await reject(()=>db.query('select checkout_shared_managed_private.record_manager_confirmation($1,$2,$3,$4,$5)',[drift.rid,W,drift.cid,drift.source.source_fingerprint,JSON.stringify(facts)]),/manager_receipt_required/);
 for(const name of ['managed_source_scope(uuid,uuid)','prepare_managed_adoption(uuid,uuid,text,jsonb)','record_manager_confirmation(uuid,uuid,bigint,text,jsonb)','assert_managed_adoption_unchanged(uuid)']){
  for(const role of ['anon','authenticated','service_role'])eq(await q('select has_function_privilege($1,$2,\'execute\') v',[role,'checkout_shared_managed_private.'+name]),false,'No caller may mint private adoption authority');
 }
 for(const f of sources.functions)eq(await q('select md5(prosrc) v from pg_proc where oid=to_regprocedure($1)',[f.signature]),f.source_md5,'All existing writer definitions unchanged');
 console.log(JSON.stringify({pass:true,checks,original_sign_source_unchanged:true,manual_ae_id_preserved:true,no_fake_clock:true,financial_drift_rolls_back:true,old_new_invalidation:true,full_payroll_refresh_integration:false,real_gotrue:false,production_changed:false}));
}finally{await db.end();}
