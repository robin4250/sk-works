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
 // Disposable adapter only: persists plan in an ungranted fixture schema, wraps actual
 // augmenter. This is evidence for the missing integration, not a product patch.
 await db.exec('create schema legacy_fixture;create table legacy_fixture.plan(company_id uuid,worker_id uuid,starts_on date,effective_settings jsonb);alter function payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb) rename to augment_settings_original');
 await db.query('insert into legacy_fixture.plan values($1,$2,$3,$4::jsonb)',[cid,wid,month,JSON.stringify(worker.effective_worker_settings)]);
 await db.exec(`create function payroll_unit_private.augment_settings(cid uuid,wid uuid,p_start date,p_end date,settings jsonb) returns jsonb language sql stable security definer set search_path='' as $$select payroll_unit_private.augment_settings_original(cid,wid,p_start,p_end,coalesce((select effective_settings from legacy_fixture.plan where company_id=cid and worker_id=wid and starts_on=p_start),settings))$$`);
 await db.query('insert into company_common_allowance_private.payroll_activation values($1,$2)',[cid,month]);
 await db.query('insert into company_common_allowance_private.payroll_publications(company_id,version,payroll_type,starts_on,common_version,items,request_id,actor_id) values($1,1,$2,$3,$4,$5::jsonb,$6,$7)',[cid,typ,month,plan.common_version,JSON.stringify(plan.snapshot_items),rid(++n),owner]);
 const refresh=async()=>{await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);return statement(month);};
 let baseline=await refresh();
 const insertDay=async(id,offset,names=[])=>db.query("insert into public.attendance_entries(id,company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,$4::date+$5::int,'day',1,0,0,$6)",[rid(id),cid,wid,month,offset,names]);
 const sum=plan.snapshot_items.reduce((v,x)=>v+Number(x.amount_yen),0);
 await insertDay(100,0);let one=await statement(month);let resolved=one.detail.unit_resolution;
 assert.equal(resolved.items.filter(x=>x.origin==='company_common').reduce((a,x)=>a+Number(x.amount_yen),0),sum);
 assert.equal(one.net_pay,one.gross_pay-one.deductions);
 await insertDay(101,1,[plan.snapshot_items[0].name]);let two=await statement(month);
 await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(101),[]]);let unselected=await statement(month);assert.equal(unselected.gross_pay,two.gross_pay,'legacy selection cannot double add inherited company rate');
 const repeated=await refresh();assert.equal(repeated.gross_pay,two.gross_pay,'recalculation idempotent');
 assert.equal(two.detail.unit_resolution.items.filter(x=>x.origin==='company_common').reduce((a,x)=>a+Number(x.amount_yen),0),sum*2,'selected legacy date does not double count inherited slot');
 await db.query('update public.attendance_entries set base_man_days=0 where id=$1',[rid(101)]);let edited=await statement(month);
 assert.equal(edited.detail.unit_resolution.items.filter(x=>x.origin==='company_common').reduce((a,x)=>a+Number(x.amount_yen),0),sum,'attendance-edit trigger recomputes common days');
 assert.deepEqual((await db.query('select to_jsonb(s) v from public.worker_payroll_settings s where company_id=$1 and worker_id=$2',[cid,wid])).rows[0].v,original);
 // Snapshot/ambiguity guards, using only disposable synthetic modifications.
 await db.query("update public.worker_payroll_settings set allowance_name_1=$3,allowance_1=$4,allowance_name_2=$3,allowance_2=$4 where company_id=$1 and worker_id=$2",[cid,wid,plan.snapshot_items[0].name,plan.snapshot_items[0].amount_yen]);
 let ambiguous=await wp(plan);assert(ambiguous.reasons.some(x=>x.code==='ambiguous_worker_legacy_name'));
 await overlay('worker_payroll_settings',original,'company_id=$1 and worker_id=$2',[cid,wid]);
 await db.query("update public.worker_payroll_settings set custom_earnings=$3::jsonb where company_id=$1 and worker_id=$2",[cid,wid,JSON.stringify([{name:plan.snapshot_items[0].name,amount_yen:17}])]);
 assert((await wp(plan)).reasons.some(x=>x.code==='individual_item_overlap_unresolved'));
 await overlay('worker_payroll_settings',original,'company_id=$1 and worker_id=$2',[cid,wid]);
 // Finalized and manual scopes are rejected without proposing an effective overlay.
 let current=await statement(month);await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[current.id,owner,current.revision]);
 await actor();await db.query('select public.finalize_payroll_statement($1,$2,true)',[current.id,current.revision]);await db.exec('reset role');
 const frozen=await statement(month);let frozenPlan=await wp(plan);assert(frozenPlan.reasons.some(x=>x.code==='finalized_or_manual_statement'));assert.equal(frozenPlan.effective_worker_settings,null);
 await refresh();assert.deepEqual(await statement(month),frozen);
 // Planner rejects source changes and unresolved individual overrides.
 const matching=bindings.find(x=>x.worker_slot!==null);
 if(matching){await db.query('update public.worker_payroll_settings set allowance_'+matching.worker_slot+'=allowance_'+matching.worker_slot+'+1 where company_id=$1 and worker_id=$2',[cid,wid]);let bad=await wp(plan);assert(bad.reasons.some(x=>x.code==='individual_rate_override_unresolved'));}
 await assert.rejects(wp(plan,bindings,'stale'),/worker source/);
 console.log(JSON.stringify({review_only:true,fixture_adapter_only:true,private_rates:!!privatePath,legacy_items:2,explicit_binding_required:true,raw_settings_preserved:true,checkout_edit_recalculated:true,net_consistent:true,unresolved_override_blocked:true,production_changed:false}));
}finally {await db.close();}
