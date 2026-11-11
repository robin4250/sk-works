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
 await db.exec(read('docs/candidates/company_common_legacy_bounded_20261022.sql.review-only'));
 await db.exec(read('docs/candidates/company_common_future_policy_20261022.sql.review-only'));
 const rawFor=async(id)=>(await db.query('select to_jsonb(s) v from public.worker_payroll_settings s where company_id=$1 and worker_id=$2',[cid,id])).rows[0].v;
 const lastDay=async(m)=>(await db.query("select ($1::date+interval '1 month - 1 day')::date::text d",[m])).rows[0].d;
 const resolvePolicy=async(id=wid,m=month)=>(await db.query('select common_payroll_future_review_private.resolve_internal($1,$2,$3,$4,$5::jsonb) v',[cid,id,m,await lastDay(m),JSON.stringify(await rawFor(id))])).rows[0].v;
 assert.equal((await resolvePolicy()).active,false,'no policy implies no future inheritance');
 const quantityContracts=plan.snapshot_items.map(x=>({id:x.id,generation:x.legacy_generation,source_unit:x.legacy_source_unit,basis:'attendance_selected_distinct_dates',aliases:[x.name]}));
 const workers=[{worker_id:wid,bindings,worker_settings_md5:preview.worker_settings_md5}];
 await db.query('select common_payroll_legacy_review_private.apply_month_selected($1,$2,$3::jsonb,$4::jsonb,$5,0,$6::jsonb)',[cid,month,JSON.stringify(plan),JSON.stringify(workers),rid(++n),JSON.stringify(quantityContracts)]);
 const savePolicy=async(enabled,start,version,id)=>(await db.query('select common_payroll_future_review_private.save_policy($1,$2,$3,$4,1,$5,$6,$7,$8) v',[cid,typ,start,month,enabled,version,id,'inherit_absent_or_same_rate_preserve_individual_exception'])).rows[0].v;
 const req=rid(++n),approved=await savePolicy(true,month,0,req);assert.deepEqual(await savePolicy(true,month,0,req),approved);
 let inherited=await resolvePolicy();assert.equal(inherited.active,true);assert.equal(inherited.blocked,false);
 const next=(await db.query("select ($1::date+interval '1 month')::date::text m",[month])).rows[0].m;
 assert.equal((await resolvePolicy(wid,next)).active,true,'later not-yet-generated month inherits latest approved policy');
 // Source classification negative controls. All fixture changes roll back;
 // known names remain attached to their real source, never aliases of policy.
 await db.exec('begin');
 await db.query("update public.worker_payroll_settings set custom_earnings=custom_earnings||$3::jsonb where company_id=$1 and worker_id=$2",[cid,wid,JSON.stringify([{name:'Synthetic individual custom',amount_yen:17}])]);
 await db.query('insert into payroll_unit_private.conditions(company_id,worker_id,starts_on,version,items) values($1,$2,$3,1,$4::jsonb)',[cid,wid,month,JSON.stringify([{id:rid(460),section:'earning',unit:'day',name:'Synthetic unit selection',rate_yen:19}])]);
 await db.query('insert into company_common_allowance_private.payroll_activation values($1,$2)',[cid,month]);
 await db.query('insert into company_common_allowance_private.payroll_publications(company_id,version,payroll_type,starts_on,common_version,items,request_id,actor_id) values($1,1,$2,$3,1,$4::jsonb,$5,$6)',[cid,typ,month,JSON.stringify([{id:rid(461),section:'earning',unit:'month',name:'Synthetic product common',amount_yen:23}]),rid(462),owner]);
 await db.query("insert into public.attendance_entries(id,company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,$4,'day',1,0,0,$5)",[rid(463),cid,wid,month,['Synthetic individual custom','Synthetic unit selection','Synthetic product common']]);
 let classified=await resolvePolicy();assert.equal(classified.blocked,false);assert(classified.items.every(x=>x.quantity===0),'known other-source selection is never rebound to policy quantity');
 for(const [name,kind] of [['Synthetic individual custom','individual_custom'],['Synthetic unit selection','individual_unit'],['Synthetic product common','company_publication']]){const row=classified.selection_classification.find(x=>x.name===name);assert.equal(row.state,'known_source');assert.equal(row.sources[0].kind,kind);}
 await db.query("update public.worker_payroll_settings set custom_earnings=custom_earnings||$3::jsonb where company_id=$1 and worker_id=$2",[cid,wid,JSON.stringify([{name:'Synthetic unit selection',amount_yen:29}])]);
 classified=await resolvePolicy();assert(classified.reasons.some(x=>x.code==='attendance_source_collision'));assert.equal(classified.selection_classification.find(x=>x.name==='Synthetic unit selection').sources.length,2);
 await db.query('insert into company_common_allowance_private.payroll_publications(company_id,version,payroll_type,starts_on,common_version,items,request_id,actor_id) values($1,2,$2,$3,1,$4::jsonb,$5,$6)',[cid,typ,month,JSON.stringify([{id:rid(464),section:'earning',unit:'month',name:plan.snapshot_items[0].name,amount_yen:31}]),rid(465),owner]);
 await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(463),[plan.snapshot_items[0].name]]);
 classified=await resolvePolicy();assert(classified.reasons.some(x=>x.code==='attendance_source_collision'));assert(classified.selection_classification[0].sources.some(x=>x.kind==='company_publication'));assert(classified.selection_classification[0].sources.some(x=>x.kind==='company_policy'));assert.equal(classified.selection_classification[0].sources.find(x=>x.kind==='company_publication').id,rid(464));assert.equal(classified.selection_classification[0].sources.find(x=>x.kind==='company_policy').id,plan.snapshot_items[0].id);
 await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(463),['Synthetic unknown historic alias']]);
 classified=await resolvePolicy();assert(classified.reasons.some(x=>x.code==='attendance_interpretation_unconfirmed'));assert.equal(classified.selection_classification[0].sources.length,0);
 await db.exec('rollback');
 // Resolver is actor-independent, not a salary reader. Simulate only the trusted
 // caller input boundary, without granting a proxy attendance or salary role.
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",['00000000-0000-0000-0000-000000000004',JSON.stringify({sub:'00000000-0000-0000-0000-000000000004',role:'authenticated'})]);
 assert.equal((await db.query("select coalesce(private.payroll_settings_allowed($1,$2,'view'),false) ok",[cid,wid])).rows[0].ok,false);
 assert.equal((await resolvePolicy()).blocked,false,'internal calculation does not require actor salary view');
 await assert.rejects(db.query('select common_payroll_future_review_private.read_display($1,$2,$3)',[cid,wid,month]),/salary view required/);
 await actor();await db.exec('reset role');
 // Unrelated fresh base/tax changes are preserved, not blocked by an old whole-row hash.
 await db.query('update public.worker_payroll_settings set day_daily=day_daily+17,resident_tax_monthly=resident_tax_monthly+23 where company_id=$1 and worker_id=$2',[cid,wid]);
 const fresh=await rawFor(wid);inherited=await resolvePolicy();assert.equal(inherited.blocked,false);assert.equal(inherited.effective_settings.day_daily,fresh.day_daily);assert.equal(inherited.effective_settings.resident_tax_monthly,fresh.resident_tax_monthly);
 // A worker created after approval has no saved effective-settings blob to reuse.
 const newWid='40000000-0000-0000-0000-000000000099';
 await db.query("insert into public.workers(id,company_id,user_id,name,status,affiliation) values($1,$2,$3,'Synthetic new employee','active','employee')",[newWid,cid,viewer]);
 const newRaw={...fresh,worker_id:newWid};await db.query('insert into public.worker_payroll_settings select (jsonb_populate_record(null::public.worker_payroll_settings,$1::jsonb)).*',[JSON.stringify(newRaw)]);
 assert.equal((await resolvePolicy(newWid)).blocked,false,'approved same-rate/absent policy covers a new employee');
 const first=plan.snapshot_items[0];await db.query('update public.worker_payroll_settings set allowance_name_1=$3,allowance_1=$4 where company_id=$1 and worker_id=$2',[cid,newWid,first.name,Number(first.amount_yen)+7]);
 assert((await resolvePolicy(newWid)).reasons.some(x=>x.code==='individual_override_unresolved'));
 await db.query('select common_payroll_future_review_private.prefer_individual($1,$2,$3,1,$4,$5)',[cid,newWid,typ,first.id,first.legacy_generation]);
 let exception=await resolvePolicy(newWid);assert.equal(exception.blocked,false);assert(exception.exceptions.some(x=>x.status==='explicit_individual_priority'));assert.equal(exception.effective_settings.allowance_1,Number(first.amount_yen)+7);
 // Renaming an approved individual exception does not silently reclassify its
 // original name as common or successfully drop its old selections.
 await db.query('update public.worker_payroll_settings set allowance_name_1=$3 where company_id=$1 and worker_id=$2',[cid,newWid,'Synthetic renamed individual']);
 assert((await resolvePolicy(newWid)).reasons.some(x=>x.code==='preferred_individual_name_changed'));
 await db.query('update public.worker_payroll_settings set allowance_name_1=$3 where company_id=$1 and worker_id=$2',[cid,newWid,first.name]);
 // Unknown historical names are reported as interpretation-unconfirmed, never aliased.
 await db.query("insert into public.attendance_entries(id,company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,$4,'day',1,0,0,ARRAY['Synthetic historical unknown'])",[rid(400),cid,newWid,month]);
 assert((await resolvePolicy(newWid)).reasons.some(x=>x.code==='attendance_interpretation_unconfirmed'));
 // Future disable wins for its effective month; current policy remains intact.
 await savePolicy(false,next,1,rid(++n));assert.equal((await resolvePolicy(wid,next)).active,false);assert.equal((await resolvePolicy(wid,month)).active,true);
 console.log(JSON.stringify({review_only:true,private_rates:!!privatePath,explicit_future_policy:true,later_month:true,new_employee:true,fresh_unrelated_settings_preserved:true,individual_priority:true,renamed_individual_unconfirmed:true,no_salary_view_internal_contract:true,public_view_enforced:true,known_sources_classified:true,source_collision_unresolved:true,unknown_alias_unconfirmed:true,production_changed:false}));
}catch(error){console.error(error.name==='AssertionError'?error.stack:error.message);process.exitCode=1;}finally {await db.close();}
