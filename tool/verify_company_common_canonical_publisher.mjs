// Disposable fixture only. Original common saver + actual payroll refresh/finalization.
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
if(process.env.SKO_CANONICAL_PUBLIC_CONTRACT_OUTPUT&&process.env.SKO_COMMON_LEGACY_PRIVATE_FIXTURE)throw Error('public contract export forbids all private-rate inputs');
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
 if(process.env.SKO_CANONICAL_PUBLIC_CONTRACT_OUTPUT){
  const path=await import('node:path');if(!path.isAbsolute(process.env.SKO_CANONICAL_PUBLIC_CONTRACT_OUTPUT))throw Error('absolute synthetic contract output path required');
  // Fixture-only default allocator: actual SQL responses contain fixed synthetic IDs.
  await db.exec("create sequence public.synthetic_contract_ids;create function public.synthetic_contract_uuid() returns uuid language sql volatile as $$select ('90000000-0000-0000-0000-'||lpad(nextval('public.synthetic_contract_ids')::text,12,'0'))::uuid$$;alter table company_allowance_identity_private.identities alter column id set default public.synthetic_contract_uuid();alter table public.payroll_statements alter column id set default public.synthetic_contract_uuid()");
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

 await db.exec('drop schema company_common_canonical_review_private cascade');
 const stripTransaction=sql=>sql.replace(/^begin;$/m,'').replace(/commit;\s*$/,'');
 const installBundle='begin;\n'+['snapshot','resolver','publisher'].map(x=>stripTransaction(read('docs/candidates/company_common_canonical_'+x+'_20261022.sql.review-only'))).join('\n')+'\ncommit;';
 await assert.rejects(db.exec(installBundle.replace('d56f5fa295167f8c49f6e9c1dd97b7f0','00000000000000000000000000000000')),/canonical payroll resolver prerequisite differs/);await db.exec('rollback');assert.equal((await db.query("select to_regnamespace('company_common_canonical_review_private') v")).rows[0].v,null,'failed closure install rolls back the earlier preparation unit');assert.deepEqual(await financialState(),before);
 const installPrefix='begin;\n'+['snapshot','resolver'].map(x=>stripTransaction(read('docs/candidates/company_common_canonical_'+x+'_20261022.sql.review-only'))).join('\n');
 const publisherUnit=stripTransaction(read('docs/candidates/company_common_canonical_publisher_20261022.sql.review-only'));
 for(const mutation of [
  'grant execute on function company_common_canonical_review_private.resolve_legacy(uuid,uuid,date,date,jsonb,bigint,date) to authenticated',
  'alter function company_common_canonical_review_private.resolve_legacy(uuid,uuid,date,date,jsonb,bigint,date) security definer',
  'alter function company_common_allowance_private.publish_payroll(uuid,text,date,bigint,jsonb,bigint,uuid) stable',
  'grant create on schema company_common_canonical_review_private to authenticated',
  'alter function payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb) set search_path=public'
 ]){await assert.rejects(db.exec(installPrefix+';'+mutation+';'+publisherUnit+';commit;'),/canonical publisher prerequisite differs/);await db.exec('rollback');assert.equal((await db.query("select to_regnamespace('company_common_canonical_review_private') v")).rows[0].v,null);assert.deepEqual(await financialState(),before);}
 await db.exec(installBundle);
 assert.deepEqual(await financialState(),before,'install retains activation/publication/data default OFF');assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_activation_modes')).rows[0].n,0);assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_type_activation')).rows[0].n,0);
 const insertSelected=async(id,worker,date,names)=>db.query("insert into public.attendance_entries(id,company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,$4,'day',1,0,0,$5)",[rid(id),cid,worker,date,names]);
 const first=built.items.find(x=>x.origin==='company_legacy');await insertSelected(850,wid,month,[first.name]);
 const manualWid='40000000-0000-0000-0000-000000000088';await db.query("insert into public.workers(id,company_id,user_id,name,status,affiliation) values($1,$2,$3,'Synthetic manual employee','active','employee')",[manualWid,cid,viewer]);
 const originalRaw=(await db.query('select to_jsonb(s) v from public.worker_payroll_settings s where company_id=$1 and worker_id=$2',[cid,wid])).rows[0].v;
 await db.query('insert into public.worker_payroll_settings select (jsonb_populate_record(null::public.worker_payroll_settings,$1::jsonb)).*',[JSON.stringify({...originalRaw,worker_id:manualWid})]);
 await insertSelected(851,manualWid,month,[first.name]);await db.query('update public.payroll_statements set automatic_calculation=false where company_id=$1 and worker_id=$2',[cid,manualWid]);
 const manualBefore=(await db.query('select to_jsonb(s) v from public.payroll_statements s where company_id=$1 and worker_id=$2',[cid,manualWid])).rows[0].v;
 const previewArgs=[cid,typ,month,state.version,JSON.stringify(state.expected_source),0,JSON.stringify(quantities),rule];
 const previewV2=async()=>(await db.query('select public.preview_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8) v',previewArgs)).rows[0].v;
 await actor(viewer);await assert.rejects(previewV2(),e=>e.code==='42501');await actor();assert.equal((await db.query('select public.company_common_payroll_publication_v2_contract_version() v')).rows[0].v,3);let v2Preview=await previewV2();assert.equal(v2Preview.ready,true);assert.equal(v2Preview.activation_required,true);assert.equal(v2Preview.target_count,1);assert.equal(v2Preview.excluded_count,1);assert.equal(v2Preview.unresolved_count,0);assert(v2Preview.scopes.some(x=>x.status==='excluded_manual'));
 await db.exec('reset role');await db.query('update public.worker_payroll_settings set allowance_name_1=$3,allowance_1=$4 where company_id=$1 and worker_id=$2',[cid,wid,first.name,Number(first.amount_yen)+7]);await actor();const unresolved=await previewV2();assert.equal(unresolved.ready,false);assert.equal(unresolved.unresolved_count,1);assert(unresolved.scopes.some(x=>x.status==='unresolved'&&x.reasons.some(r=>r.code==='individual_override_unresolved')));
 await db.exec('reset role');await db.query('update public.worker_payroll_settings set allowance_name_1=$3,allowance_1=$4 where company_id=$1 and worker_id=$2',[cid,wid,originalRaw.allowance_name_1,originalRaw.allowance_1]);await actor();v2Preview=await previewV2();
 const staleToken=v2Preview.preview_token;await db.exec('reset role');await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(850),[]]);await actor();await assert.rejects(db.query('select public.publish_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9,$10,true,$11)',[...previewArgs,rid(859),staleToken,'payroll_type']),/canonical preview changed/);await db.exec('reset role');await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(850),[first.name]]);await actor();v2Preview=await previewV2();
 const requestV2=rid(860);const command={...v2Preview.command_base,p_request_id:requestV2,p_preview_token:v2Preview.preview_token,p_approve_activation:true,p_activation_scope:v2Preview.activation_scope};
 const publish=async(approved=true,token=v2Preview.preview_token,request=requestV2,scope=v2Preview.activation_scope)=>(await db.query('select public.publish_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9,$10,$11,$12) v',[...previewArgs,request,token,approved,scope])).rows[0].v;
 await assert.rejects(publish(false),/first activation requires explicit approval/);await db.exec('reset role');assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_activation')).rows[0].n,0);assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_publications')).rows[0].n,0);await actor();
 const missingReceipt=(await db.query('select public.read_company_common_payroll_publish_receipt_v2($1,$2,$3::jsonb) v',[cid,requestV2,JSON.stringify(command)])).rows[0].v;assert.equal(missingReceipt.found,false);
 await db.exec('reset role');const stableBefore=await financialState();await db.exec(`create function public.synthetic_excluded_mutation() returns trigger language plpgsql as $$begin if new.worker_id='${wid}'::uuid then update public.payroll_statements set revision=revision+1 where company_id='${cid}'::uuid and worker_id='${manualWid}'::uuid;end if;return new;end $$;create trigger synthetic_excluded_mutation after update on public.payroll_statements for each row execute function public.synthetic_excluded_mutation();`);await actor();await assert.rejects(publish(),/canonical excluded salary changed/);await db.exec('reset role');assert.deepEqual(await financialState(),stableBefore,'failed readback rolls back activation publication payroll and excluded mutations');await db.exec('drop trigger synthetic_excluded_mutation on public.payroll_statements;drop function public.synthetic_excluded_mutation()');await actor();
 await assert.rejects(db.query('select public.publish_company_common_payroll($1,$2,$3,$4,$5::jsonb,$6,$7)',[cid,typ,month,state.version,JSON.stringify(state.expected_source),0,rid(858)]),/activation is not configured|legacy payroll requires versioned preview/);
 const result=await publish();await assert.rejects(db.query('select public.publish_company_common_payroll($1,$2,$3,$4,$5::jsonb,$6,$7)',[cid,typ,month,state.version,JSON.stringify(state.expected_source),1,rid(857)]),/legacy payroll requires versioned preview/);assert.equal(result.activation_changed,true);assert.equal(result.publication_version,1);assert.equal(result.recalculated_scopes,1);assert.equal(result.excluded_scopes,1);assert(result.scopes.some(x=>x.readback_status==='verified'));
 assert.deepEqual(await publish(),result,'same request/payload receipt returns before changed timeline CAS');
 const receipt=(await db.query('select public.read_company_common_payroll_publish_receipt_v2($1,$2,$3::jsonb) v',[cid,requestV2,JSON.stringify(command)])).rows[0].v;assert.equal(receipt.found,true);assert.deepEqual(receipt.result,result);
 await assert.rejects(publish(false),/request mismatch/);
 await assert.rejects(db.query('select public.read_company_common_payroll_publish_receipt_v2($1,$2,$3::jsonb)',[cid,requestV2,JSON.stringify({...command,p_approve_activation:false})]),/receipt request mismatch/);
 await db.exec('reset role');assert.deepEqual((await db.query('select to_jsonb(s) v from public.payroll_statements s where company_id=$1 and worker_id=$2',[cid,manualWid])).rows[0].v,manualBefore,'excluded manual original preserved');
 let actual=await statement(month);assert.equal(actual.calculation_blocked,false);assert.equal(actual.detail.unit_resolution.items.find(x=>x.id===first.id).quantity,1);
 const gross=actual.gross_pay;await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(850),[]]);assert.equal((await statement(month)).gross_pay,gross-Number(first.amount_yen));await db.query('update public.attendance_entries set allowance_names=$2 where id=$1',[rid(850),[first.name]]);assert.equal((await statement(month)).gross_pay,gross);
 assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_publications')).rows[0].n,1);assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_publication_receipts')).rows[0].n,1,'retry/readback creates no duplicate receipt');
 await db.query("update public.company_members set role='admin' where company_id=$1 and user_id=$2",[cid,viewer]);await actor(viewer);await assert.rejects(db.query('select public.read_company_common_payroll_publish_receipt_v2($1,$2,$3::jsonb)',[cid,requestV2,JSON.stringify(command)]),/receipt request mismatch/);await actor();await db.exec('reset role');await db.query("update public.company_members set role='viewer' where company_id=$1 and user_id=$2",[cid,viewer]);
 assert.equal((await db.query("select to_regnamespace('common_payroll_future_review_private') exists")).rows[0].exists,null);

 const otherType=['monthly','hourly','daily'].find(x=>x!==typ),otherWid='40000000-0000-0000-0000-000000000077';
 await db.query("insert into public.workers(id,company_id,user_id,name,status,affiliation) values($1,$2,$3,'Synthetic other payroll type','active','employee')",[otherWid,cid,viewer]);
 await db.query('insert into public.worker_payroll_settings select (jsonb_populate_record(null::public.worker_payroll_settings,$1::jsonb)).*',[JSON.stringify({...originalRaw,worker_id:otherWid,pay_type:otherType})]);await insertSelected(855,otherWid,month,[first.name]);
 const otherUnactivated=(await db.query("select payroll_unit_private.resolve_company_common($1,$2,$3::date,($3::date+interval '1 month - 1 day')::date) v",[cid,otherWid,month])).rows[0].v;
 assert.equal(otherUnactivated.blocked,false,'unapproved different payroll type retains original path');assert.equal(otherUnactivated.history_missing,false);assert.deepEqual(otherUnactivated.items,[]);
 assert.equal((await db.query('select calculation_blocked from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,otherWid,month])).rows[0].calculation_blocked,false);
 await actor();const secondArgs=[cid,otherType,month,state.version,JSON.stringify(state.expected_source),1,JSON.stringify(quantities),rule];
 const secondPreview=(await db.query('select public.preview_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8) v',secondArgs)).rows[0].v;assert.equal(secondPreview.activation_scope,'payroll_type');assert.equal(secondPreview.activation_required,true);assert.equal(secondPreview.activation_mode,'per_type');
 await assert.rejects(db.query('select public.publish_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9,$10,false,$11)',[...secondArgs,rid(861),secondPreview.preview_token,secondPreview.activation_scope]),/first activation requires explicit approval/);
 await assert.rejects(db.query('select public.publish_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9,$10,true,$11)',[...secondArgs,rid(861),secondPreview.preview_token,'legacy_company']),/activation scope changed/);
 const secondResult=(await db.query('select public.publish_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9,$10,true,$11) v',[...secondArgs,rid(861),secondPreview.preview_token,secondPreview.activation_scope])).rows[0].v;assert.equal(secondResult.activation_changed,true);assert.equal(secondResult.activation_scope,'payroll_type');assert.equal(secondResult.activation_mode,'per_type');assert.equal(secondResult.contract_version,3);
 assert.deepEqual(await publish(),result,'first type receipt remains valid after another type activates');await db.exec('reset role');
 assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_activation_modes where company_id=$1',[cid])).rows[0].n,1);assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_type_activation where company_id=$1',[cid])).rows[0].n,2);assert.equal((await db.query('select count(*) n from company_common_allowance_private.payroll_type_activation_events where company_id=$1',[cid])).rows[0].n,2);
 await assert.rejects(db.query('update company_common_allowance_private.payroll_type_activation_events set starts_on=starts_on where company_id=$1',[cid]),/history is immutable/);
 const historicalCid='10000000-0000-0000-0000-000000000099',historicalWid='40000000-0000-0000-0000-000000000066';
 const companyRow=(await db.query('select to_jsonb(c) v from public.companies c where id=$1',[cid])).rows[0].v;await db.query('insert into public.companies select (jsonb_populate_record(null::public.companies,$1::jsonb)).*',[JSON.stringify({...companyRow,id:historicalCid})]);
 await db.query("insert into public.company_members(company_id,user_id,role) values($1,$2,'owner')",[historicalCid,owner]);await db.query('insert into public.company_rate_settings(company_id) values($1)',[historicalCid]);
 await db.query("insert into public.workers(id,company_id,user_id,name,status,affiliation) values($1,$2,$3,'Synthetic historical global','active','employee')",[historicalWid,historicalCid,owner]);await db.query('insert into public.worker_payroll_settings select (jsonb_populate_record(null::public.worker_payroll_settings,$1::jsonb)).*',[JSON.stringify({...originalRaw,worker_id:historicalWid,company_id:historicalCid})]);
 await db.query('insert into company_common_allowance_private.payroll_activation values($1,$2)',[historicalCid,month]);
 const historical=(await db.query("select payroll_unit_private.resolve_company_common($1,$2,$3::date,($3::date+interval '1 month - 1 day')::date) v",[historicalCid,historicalWid,month])).rows[0].v;assert.equal(historical.history_missing,true,'existing historical global missing publication remains blocked');assert.equal(historical.blocked,true);
 const futureMonth=(await db.query("select ($1::date+interval '1 month')::date::text m",[month])).rows[0].m;await db.query('update company_common_allowance_private.payroll_activation set starts_on=$2 where company_id=$1',[historicalCid,futureMonth]);await actor();
 const historicalState=(await db.query('select public.read_company_common_allowances_admin($1) v',[historicalCid])).rows[0].v;
 const historicalPreview=(await db.query('select public.preview_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,0,$6::jsonb,$7) v',[historicalCid,typ,month,historicalState.version,JSON.stringify(historicalState.expected_source),'[]',rule])).rows[0].v;assert.equal(historicalPreview.ready,false);assert.equal(historicalPreview.activation_mode,'legacy_global');assert.equal(historicalPreview.activation_scope,'legacy_company');assert(historicalPreview.activation_blockers.includes('legacy_global_boundary_advance_requires_review'));
 await assert.rejects(db.query('select public.publish_company_common_payroll_v2($1,$2,$3,$4,$5::jsonb,0,$6::jsonb,$7,$8,$9,true,$10)',[historicalCid,typ,month,historicalState.version,JSON.stringify(historicalState.expected_source),'[]',rule,rid(862),historicalPreview.preview_token,historicalPreview.activation_scope]),/unresolved scopes require review/);

 if(process.env.SKO_CANONICAL_PUBLIC_CONTRACT_OUTPUT){
  await db.exec('reset role');const capturedCommand=(await db.query('select payload from company_common_allowance_private.payroll_publication_receipts where company_id=$1 and request_id=$2',[cid,requestV2])).rows[0].payload;assert.deepEqual(capturedCommand,command);
  const exported={company_state:state,preview:v2Preview,command:capturedCommand,publish_result:result,receipt_found:receipt,receipt_missing:missingReceipt};
  const bytes=JSON.stringify(exported,null,2)+'\n';const uuids=bytes.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi)??[];
  assert(uuids.every(id=>/^(?:00000000-0000-0000-0000-000000000001|10000000-0000-0000-0000-000000000001|40000000-0000-0000-0000-0000000000(?:01|88)|[89]0000000-0000-0000-0000-\d{12})$/.test(id)),'export allows fixed synthetic UUID namespaces only');
  const path=await import('node:path');fs.mkdirSync(path.dirname(process.env.SKO_CANONICAL_PUBLIC_CONTRACT_OUTPUT),{recursive:true});fs.writeFileSync(process.env.SKO_CANONICAL_PUBLIC_CONTRACT_OUTPUT,bytes,{mode:0o600});
 }
 console.log(JSON.stringify({review_only:true,private_rates:!!privatePath,canonical_v2_public_rpc:true,per_type_activation:true,other_type_original_path:true,other_type_requires_approval:true,historical_global_missing_blocked:true,historical_boundary_advance_refused:true,activation_audit_immutable:true,explicit_first_activation:true,activation_refusal_rolls_back:true,preview_target_excluded_counts:true,atomic_publication_readback_receipt:true,same_payload_receipt_before_cas:true,read_only_receipt:true,wrong_payload_rejected:true,different_admin_receipt_denied:true,no_duplicate_receipts:true,manual_original_preserved:true,excluded_trigger_rollback:true,unresolved_preview:true,viewer_denied:true,install_default_off:true,atomic_closure_install:true,publisher_security_mutations_rejected:true,stale_preview_rejected:true,legacy_v1_drop_prevented:true,attendance_edit:true,no_future_policy_dependency:true,production_changed:false}));
}catch(error){console.error(error.name==='AssertionError'?error.stack:error.message);process.exitCode=1;}finally {await db.close();}
