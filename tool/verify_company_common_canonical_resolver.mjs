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
 await db.exec(read('docs/candidates/company_common_canonical_snapshot_20261022.sql.review-only'));
 const state=await common();const positive=state.legacy_refs.filter(x=>x.name&&Number(x.amount_yen)>0);
 const quantities=positive.map(x=>({id:x.id,generation:x.generation,source_unit:x.source_unit,basis:'attendance_selected_distinct_dates',aliases:[x.name]}));
 const rule='inherit_absent_or_same_rate_otherwise_unresolved';
 const snapshot=async(q=quantities,version=state.version)=>(await db.query('select company_common_canonical_review_private.snapshot_plan($1,$2,$3,$4::jsonb,$5::jsonb,$6) v',[cid,input.worker_settings.pay_type,version,JSON.stringify(state.expected_source),JSON.stringify(q),rule])).rows[0].v;
 const financialState=async()=>(await db.query("select jsonb_build_object('statements',(select coalesce(jsonb_agg(to_jsonb(s) order by s.id),'[]') from public.payroll_statements s),'worker',(select to_jsonb(s) from public.worker_payroll_settings s where company_id=$1 and worker_id=$2),'company',(select to_jsonb(s) from public.company_rate_settings s where company_id=$1),'activation',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from company_common_allowance_private.payroll_activation a),'publications',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from company_common_allowance_private.payroll_publications p)) v",[cid,wid])).rows[0].v;
 const before=await financialState();const built=await snapshot();assert.equal(built.legacy_count,2);assert.equal(built.ready_for_calculation,false);assert.deepEqual(built.items.filter(x=>x.origin==='company_legacy').map(x=>[x.id,x.generation,x.amount_yen,x.source_unit]),positive.map(x=>[x.id,x.generation,x.amount_yen,x.source_unit]));
 await assert.rejects(snapshot([]),/quantity decision/);await assert.rejects(snapshot([...quantities,quantities[0]]),/missing or duplicated/);
 await assert.rejects(snapshot(quantities.map((x,i)=>i===0?{...x,basis:'arbitrary_count_1_or_2'}:x)),/interpretation requires review/);
 await assert.rejects(snapshot(quantities,state.version+1),/source changed/);
 const timeline=(await db.query('select public.read_company_common_payroll_publications($1) v',[cid])).rows[0].v;
 const request=rid(++n),monthStart=(await db.query("select date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date::text m")).rows[0].m;
 const previewPlan=(await db.query('select company_common_canonical_review_private.publication_preview($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9) v',[cid,input.worker_settings.pay_type,monthStart,state.version,JSON.stringify(state.expected_source),timeline.timeline_version,JSON.stringify(quantities),rule,request])).rows[0].v;
 assert.equal(previewPlan.activation_required,true);assert.equal(previewPlan.activation_change_performed,false);assert.equal(previewPlan.ready_to_publish,false);assert(previewPlan.target_count>=1);assert.equal(previewPlan.operation_kind,'publish_common_legacy');
 assert.deepEqual(await financialState(),before,'prepare-only canonical snapshot never changes financial/activation/publication originals');

 const canonicalSql=read('docs/candidates/company_common_canonical_resolver_20261022.sql.review-only');
 const callerSignatures=['private.refresh_automatic_payroll_internal(uuid,uuid,date)','private.apply_payroll_custom_money()','payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)','private.attendance_refresh_payroll()','private.attendance_sync_payroll_detail()'];
 const callerHashes=async()=>(await db.query("select p.oid::regprocedure::text signature,md5(p.prosrc) hash,to_jsonb(p)-'prosrc' attributes from pg_proc p where p.oid=any($1::regprocedure[]) order by p.oid::regprocedure::text",[callerSignatures])).rows;
 const callersBefore=await callerHashes();
 const settingsBefore=(await db.query('select to_jsonb(s) v from public.worker_payroll_settings s where company_id=$1 and worker_id=$2',[cid,wid])).rows[0].v;
 assert.equal((await db.query("select to_regnamespace('common_payroll_future_review_private') exists")).rows[0].exists,null,'canonical connection has no alternative future-policy dependency');
 await db.query('insert into company_common_allowance_private.payroll_activation(company_id,starts_on) values($1,$2)',[cid,month]);
 const ordinary=[{id:rid(701),origin:'company_common',payroll_type:typ,section:'earning',unit:'day',name:'Synthetic regular day',amount_yen:17},{id:rid(702),origin:'company_common',payroll_type:typ,section:'earning',unit:'month',name:'Synthetic regular month',amount_yen:19}];
 const pub=async(version,start,items)=>db.query('insert into company_common_allowance_private.payroll_publications(company_id,version,payroll_type,starts_on,common_version,items,request_id,actor_id) values($1,$2,$3,$4,$5,$6::jsonb,$7,$8)',[cid,version,typ,start,state.version,JSON.stringify(items),rid(710+version),owner]);
 const resolve=async(worker=wid,start=month)=>(await db.query("select payroll_unit_private.resolve_company_common($1,$2,$3::date,($3::date+interval '1 month - 1 day')::date) v",[cid,worker,start])).rows[0].v;
 await pub(1,month,ordinary);const normalBefore=await resolve();
 const guardMutations=[
  "grant execute on function payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb) to authenticated",
  "alter function payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb) volatile",
  "alter function payroll_unit_private.resolve_company_common(uuid,uuid,date,date) set search_path=public",
  "alter function payroll_unit_private.resolve_company_common(uuid,uuid,date,date) security invoker",
  "grant create on schema company_common_canonical_review_private to authenticated"
 ];
 for(const mutation of guardMutations){await db.exec('begin');await db.exec(mutation);await assert.rejects(db.exec(canonicalSql),/canonical payroll resolver prerequisite differs/);await db.exec('rollback');}
 await db.exec(canonicalSql);assert.deepEqual(await resolve(),normalBefore,'ordinary-only canonical publications retain exact resolver shape/quantities');
 assert.deepEqual(await callerHashes(),callersBefore,'five canonical attendance/payroll callers and ACLs remain unchanged');
 await pub(2,month,[...ordinary,...built.items]);
 const insertSelected=async(id,worker,date,names,days=1)=>db.query("insert into public.attendance_entries(id,company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,$4,'day',$6,0,0,$5)",[rid(id),cid,worker,date,names,days]);
 const first=built.items.find(x=>x.origin==='company_legacy'),second=built.items.filter(x=>x.origin==='company_legacy')[1];
 const duplicate=(await db.query("select company_common_canonical_review_private.resolve_legacy($1,$2,$3::date,($3::date+interval '1 month - 1 day')::date,$4::jsonb,2,$3::date) v",[cid,wid,month,JSON.stringify([first,first])])).rows[0].v;assert.equal(duplicate.blocked,true);assert(duplicate.reasons.some(x=>x.code==='publication_source_collision'));
 await insertSelected(750,wid,month,[first.name]);let actual=await statement(month);assert.equal(actual.calculation_blocked,false);
 const rows=actual.detail.unit_resolution.items;const selected=rows.find(x=>x.id===first.id);assert.equal(selected.origin,'company_common');assert.equal(selected.source_origin,'company_legacy');assert.equal(selected.quantity,1);assert.equal(rows.find(x=>x.id===second.id).quantity,0);
 const selectedGross=actual.gross_pay;
 await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(750),[]]);assert.equal((await statement(month)).gross_pay,selectedGross-Number(first.amount_yen),'editing selection removes one inherited amount');
 await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(750),[first.name]]);assert.equal((await statement(month)).gross_pay,selectedGross,'restoring selection adds once');
 await insertSelected(751,wid,month,[first.name]);assert.equal((await resolve()).items.find(x=>x.id===first.id).quantity,1,'same-day duplicate does not double allowance');
 const day2=month.slice(0,8)+'02';await insertSelected(752,wid,day2,[]);let resolved=await resolve();assert.equal(resolved.items.find(x=>x.id===first.id).quantity,1,'unselected ordinary working date adds no legacy allowance');assert.equal(resolved.items.find(x=>x.id===rid(701)).quantity,2,'ordinary day item retains positive workdate count');assert.equal(resolved.items.find(x=>x.id===rid(702)).quantity,1,'ordinary monthly item remains one');
 const day3=month.slice(0,8)+'03';await insertSelected(753,wid,day3,[first.name],0);resolved=await resolve();assert.equal(resolved.items.find(x=>x.id===first.id).quantity,2,'selected zero-man-day follows legacy selected-date semantics');assert.equal(resolved.items.find(x=>x.id===rid(701)).quantity,2,'zero-man-day does not change ordinary day quantity');
 assert.deepEqual((await db.query('select to_jsonb(s) v from public.worker_payroll_settings s where company_id=$1 and worker_id=$2',[cid,wid])).rows[0].v,settingsBefore,'overlay never writes individual settings');
 const noView='00000000-0000-0000-0000-000000000004';await db.query("select set_config('request.jwt.claim.sub',$1,false)",[noView]);assert.equal((await db.query("select coalesce(private.payroll_settings_allowed($1,$2,'view'),false) ok",[cid,wid])).rows[0].ok,false);await insertSelected(754,wid,month,[]);assert.equal((await statement(month)).calculation_blocked,false,'trusted attendance trigger does not require salary-view permission');
 await actor();await db.exec('reset role');
 const newWid='40000000-0000-0000-0000-000000000099';await db.query("insert into public.workers(id,company_id,user_id,name,status,affiliation) values($1,$2,$3,'Synthetic new employee','active','employee')",[newWid,cid,viewer]);
 const newRaw={...settingsBefore,worker_id:newWid};await db.query('insert into public.worker_payroll_settings select (jsonb_populate_record(null::public.worker_payroll_settings,$1::jsonb)).*',[JSON.stringify(newRaw)]);await insertSelected(755,newWid,month,[first.name]);let newSalary=(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,newWid,month])).rows[0];assert(newSalary);assert.equal(newSalary.calculation_blocked,false);assert.equal(newSalary.detail.unit_resolution.items.find(x=>x.id===first.id).quantity,1,'new employee uses latest canonical publication');
 await db.query('update public.worker_payroll_settings set allowance_name_1=$3,allowance_1=$4 where company_id=$1 and worker_id=$2',[cid,newWid,first.name,Number(first.amount_yen)+7]);assert((await resolve(newWid)).legacy_resolution.reasons.some(x=>x.code==='individual_override_unresolved'),'different individual amount requires explicit reconciliation');
 await db.query('update public.worker_payroll_settings set allowance_1=$3 where company_id=$1 and worker_id=$2',[cid,newWid,Number(first.amount_yen)]);
 await insertSelected(756,newWid,month,['Synthetic historical unknown']);assert((await resolve(newWid)).legacy_resolution.reasons.some(x=>x.code==='attendance_interpretation_unconfirmed'),'unknown name is not silently remapped or accepted as zero');
 const frozenBefore=(await db.query("update public.payroll_statements set automatic_calculation=false where company_id=$1 and worker_id=$2 and period_start=$3 returning to_jsonb(payroll_statements) v",[cid,wid,month])).rows[0].v;
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);assert.deepEqual((await db.query('select to_jsonb(s) v from public.payroll_statements s where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,month])).rows[0].v,frozenBefore);
 const frozenCard=(await db.query('select payroll_unit_private.common_state($1,$2,$3) v',[cid,wid,month])).rows[0].v;assert.equal(frozenCard.frozen,true);assert(frozenCard.items.some(x=>x.source_origin==='company_legacy'),'existing frozen common card retains canonical origin rows');
 console.log(JSON.stringify({review_only:true,private_rates:!!privatePath,canonical_publication_only:true,no_future_policy_dependency:true,ordinary_quantities_unchanged:true,selected_distinct_dates:true,actual_payroll_created:true,attendance_edit:true,duplicate_day_deduplicated:true,zero_man_day_selected:true,new_employee:true,unknown_alias_unconfirmed:true,individual_conflict_unresolved:true,individual_originals_preserved:true,manual_preserved:true,frozen_card_compatible:true,unchanged_callers:true,security_mutations_rejected:true,identical_duplicate_rejected:true,no_salary_view_trigger_contract:true,normal_publisher_approval_not_integrated:true,production_changed:false}));
}catch(error){console.error(error.name==='AssertionError'?error.stack:error.message);process.exitCode=1;}finally {await db.close();}
