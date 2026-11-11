// Disposable fixture only. Original common saver + actual payroll refresh/finalization.
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
let db;let pg;
if(process.argv[3]==='postgres') {
 pg=(await import(process.argv[2])).default;const url=new URL(process.env.SKO_COMMON_LEGACY_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_common_legacy_fixture') throw Error('disposable loopback legacy fixture required');
 pg.types.setTypeParser(20,Number);pg.types.setTypeParser(1700,Number);const client=new pg.Client({connectionString:url.href});await client.connect();
 db={query:(...a)=>client.query(...a),exec:sql=>client.query(sql),close:()=>client.end()};
} else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const base=fileURLToPath(new URL('../',import.meta.url));
const read=p=>fs.readFileSync(new URL(p,new URL('../',import.meta.url)),'utf8');
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001',owner='00000000-0000-0000-0000-000000000001',viewer='00000000-0000-0000-0000-000000000003';
const sid=id=>id.replace(/^0/,'7');const rid=n=>`80000000-0000-0000-0000-${String(n).padStart(12,'0')}`;let n=0;
const actor=async(id=owner)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,role:'authenticated',session_id:sid(id)})]);await db.exec('set role authenticated');};
const common=async()=>(await db.query('select public.read_company_common_allowances_admin($1) value',[cid])).rows[0].value;
const legacy=s=>s.legacy_refs.map(({slot,id,generation,name,source_unit,amount_yen})=>({slot,id,generation,name,source_unit,amount_yen}));
const save=async(s,items)=>(await db.query('select public.save_company_common_allowances($1,$2,$3,$4::jsonb,$5,$6::jsonb,$7::jsonb,true) value',[cid,'monthly',s.version,JSON.stringify(s.expected_source),rid(++n),JSON.stringify(items),JSON.stringify(legacy(s))])).rows[0].value;
const statement=async(month)=>{await db.exec('reset role');return(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,month])).rows[0];};
try {
 process.chdir(base);await setupPayrollScopeFixture(db);
 for(const p of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql'])await db.exec(read('supabase/migrations/'+p));
 await db.exec(`reset role;create role service_role nologin;delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,custom_earnings='[]',custom_deductions='[]',family_monthly=0,transport_monthly=0,income_tax_monthly=0,social_insurance_monthly=0,resident_tax_monthly=0 where worker_id='${wid}';
 alter table public.companies add column if not exists default_welfare_rate numeric default 0,add column if not exists tax_rate numeric default 10,add column if not exists updated_at timestamptz;
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;`);
 const fixture=read('supabase/tests/company_allowance_identity_access_fixture.sql');
 await db.exec(fixture.slice(fixture.indexOf('create table public.company_rate_settings('),fixture.indexOf('create table public.payroll_statements')));
 await db.query('insert into public.company_rate_settings(company_id) values($1)',[cid]);
 await db.query("update public.company_members set role='viewer' where company_id=$1 and user_id=$2",[cid,viewer]);
 for(const id of [owner,viewer])await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid(id),id]);
 for(const p of ['20260922020000_add_company_rate_settings_management.sql','20261003002700_add_attendance_allowance_display_units.sql','20261008043823_atomic_company_rate_and_allowance_units_save.sql','20261009201229_company_allowance_identity_lifecycle.sql'])await db.exec(read('supabase/migrations/'+p));
 await db.exec(read('tool/staged_company_common_allowances.sql.review-only'));
 await db.exec(read('docs/candidates/company_common_payroll_bridge_20261020.sql.review-only'));
 await db.exec(read('docs/candidates/company_common_payroll_effective_20261020.sql.review-only'));
 await db.exec(fs.readFileSync(new URL('../docs/candidates/company_common_legacy_publication_20261021.sql.review-only',import.meta.url),'utf8'));

 const privatePath=process.env.SKO_COMMON_LEGACY_PRIVATE_FIXTURE;
 const input=privatePath?JSON.parse(fs.readFileSync(privatePath,'utf8')):{company_rates:{allowance_1_name:'Synthetic travel',allowance_1_amount_yen:1200,allowance_1_unit:'day',allowance_2_name:'Synthetic work',allowance_2_amount_yen:800,allowance_2_unit:'day'},worker_settings:{pay_type:'daily',day_daily:10000,allowance_name_1:'Synthetic travel',allowance_1:1200,custom_earnings:[],custom_deductions:[]}};
 await db.exec(`alter table public.worker_payroll_settings add column if not exists allowance_name_2 text,add column if not exists allowance_2 numeric default 0,add column if not exists allowance_name_3 text,add column if not exists allowance_3 numeric default 0`);
 // Input is external and never written to this repository. Known columns only.
 async function overlay(table,obj,where,args){
  const columns=(await db.query("select column_name from information_schema.columns where table_schema='public' and table_name=$1",[table])).rows.map(x=>x.column_name);
  const entries=Object.entries(obj).filter(([k])=>columns.includes(k)&&!['company_id','worker_id','updated_at','updated_by'].includes(k));
  await db.query(`update public.${table} set `+entries.map(([k],i)=>`"${k}"=$${i+1}`).join(',')+' where '+where.replace(/\$(\d+)/g,(_,n)=>'$'+(entries.length+Number(n))),[...entries.map(([,v])=>v!==null&&typeof v==='object'?JSON.stringify(v):v),...args]);
 }
 await overlay('company_rate_settings',input.company_rates,'company_id=$1',[cid]);
 await overlay('worker_payroll_settings',input.worker_settings,'company_id=$1 and worker_id=$2',[cid,wid]);
 await actor();let s=await common();s=await save(s,[]);await db.exec('reset role');
 const month=(await db.query("select date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date::text m")).rows[0].m;
 const typ=input.worker_settings.pay_type;
 const cp=async()=>(await db.query('select common_payroll_legacy_review_private.company_plan($1,$2) v',[cid,typ])).rows[0].v;
 const wp=async(plan,bind=null,hash=null)=>(await db.query('select common_payroll_legacy_review_private.worker_plan($1,$2,$3,$4::jsonb,$5::jsonb,$6) v',[cid,wid,month,JSON.stringify(plan),bind===null?null:JSON.stringify(bind),hash])).rows[0].v;
 let plan=await cp();assert.equal(plan.ready,true);assert.equal(plan.snapshot_items.filter(x=>x.origin==='company_legacy').length,2);
 let preview=await wp(plan);assert.equal(preview.ready,false);assert(preview.reasons.some(x=>x.code==='explicit_identity_bindings_required'));
 const bindings=preview.suggested_bindings.map(({legacy_selected_days,...b})=>b);
 let worker=await wp(plan,bindings,preview.worker_settings_md5);assert.equal(worker.ready,true,'observed exact-rate legacy match requires explicit identity plan');
 const raw=await db.query('select to_jsonb(s) v from public.worker_payroll_settings s where company_id=$1 and worker_id=$2',[cid,wid]);
 const original=raw.rows[0].v;
 // Read-only candidate may propose effective zero for inherited slot, never mutate original.
 for(const b of bindings)if(b.worker_slot!==null)assert.equal(worker.effective_worker_settings['allowance_'+b.worker_slot],0);
 await db.exec(read('docs/candidates/company_common_legacy_integration_20261022.sql.review-only'));
 const workers=[{worker_id:wid,bindings,worker_settings_md5:preview.worker_settings_md5}];
 const apply=async(id,version=0,ws=workers)=>(await db.query('select common_payroll_legacy_review_private.apply_plan($1,$2,$3::jsonb,$4::jsonb,$5,$6) v',[cid,month,JSON.stringify(plan),JSON.stringify(ws),id,version])).rows[0].v;
 const request=rid(++n);let applied=await apply(request);assert.equal(applied.included_workers,1);
 assert.deepEqual(await apply(request),applied,'unknown-commit retry returns same receipt without duplicate publication');
 await assert.rejects(apply(request,1),/request conflict/);
 assert.equal((await db.query('select count(*)::int n from common_payroll_legacy_review_private.publications')).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from common_payroll_legacy_review_private.activations')).rows[0].n,1);
 const resolve=async()=>(await db.query('select common_payroll_legacy_review_private.resolve($1,$2,$3) v',[cid,wid,month])).rows[0].v;
 let inherited=await resolve();assert.equal(inherited.blocked,false);assert.equal(inherited.items.length,2);assert(inherited.items.every(x=>x.readonly&&x.inherited));
 // Disposable wiring only: invoke candidate from the actual refresh/sync callers.
 // Existing product SQL files/functions in source remain unchanged.
 const callers=(await db.query("select pg_get_functiondef(oid) def from pg_proc where pronamespace='private'::regnamespace and prosrc like '%payroll_unit_private.augment_settings(%'")).rows;
 assert(callers.length>=2);
 for(const {def} of callers)await db.exec(def.replaceAll('payroll_unit_private.augment_settings(','common_payroll_legacy_review_private.augment_candidate('));
 const sum=plan.snapshot_items.reduce((a,x)=>a+Number(x.amount_yen),0);
 const insertDay=async(id,offset,names=[])=>db.query("insert into public.attendance_entries(id,company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,$4::date+$5::int,'day',1,0,0,$6)",[rid(id),cid,wid,month,offset,names]);
 await insertDay(200,0);let one=await statement(month);assert.equal(one.calculation_blocked,false);assert.equal((await resolve()).items.reduce((a,x)=>a+Number(x.amount_yen),0),sum);assert.equal(one.net_pay,one.gross_pay-one.deductions);
 await insertDay(201,1,[plan.snapshot_items[0].name]);let selected=await statement(month);
 await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(201),[]]);assert.equal((await statement(month)).gross_pay,selected.gross_pay,'inherited individual slot not duplicated');
 await db.query('update public.attendance_entries set base_man_days=0 where id=$1',[rid(201)]);assert.equal((await resolve()).items.reduce((a,x)=>a+Number(x.amount_yen),0),sum);
 assert.deepEqual((await db.query('select to_jsonb(s) v from public.worker_payroll_settings s where company_id=$1 and worker_id=$2',[cid,wid])).rows[0].v,original);
 // Unresolved update must roll back atomically with no added activation/publication.
 await assert.rejects(apply(rid(++n),1,[{...workers[0],worker_settings_md5:'wrong'}]),/worker source/);
 assert.equal((await db.query('select count(*)::int n from common_payroll_legacy_review_private.publications')).rows[0].n,1);
 // New individual changes invalidate inherited snapshot instead of erasing edits.
 await db.query('update public.worker_payroll_settings set day_daily=day_daily+1 where company_id=$1 and worker_id=$2',[cid,wid]);
 assert.equal((await resolve()).blocked,true);assert.equal((await statement(month)).calculation_blocked,true);
 console.log(JSON.stringify({review_only:true,private_rates:!!privatePath,persisted_bindings:true,atomic_activation:true,receipt_retry:true,readonly_inheritance_payload:true,actual_refresh_edit:true,duplicate_avoided:true,raw_preserved:true,stale_worker_blocked:true,production_changed:false}));
}finally {await db.close();}
