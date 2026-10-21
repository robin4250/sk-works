// Disposable fixture only. Original common saver + actual payroll refresh/finalization.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
let db;let pg;
if(process.argv[3]==='postgres') {
 pg=(await import(process.argv[2])).default;const url=new URL(process.env.SKO_COMMON_EFFECTIVE_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_common_effective_fixture') throw Error('disposable loopback effective fixture required');
 pg.types.setTypeParser(20,Number);pg.types.setTypeParser(1700,Number);const client=new pg.Client({connectionString:url.href});await client.connect();
 db={query:(...a)=>client.query(...a),exec:sql=>client.query(sql),close:()=>client.end()};
} else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001',owner='00000000-0000-0000-0000-000000000001',viewer='00000000-0000-0000-0000-000000000003';
const sid=id=>id.replace(/^0/,'7');const rid=n=>`80000000-0000-0000-0000-${String(n).padStart(12,'0')}`;let n=0;
const actor=async(id=owner)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,role:'authenticated',session_id:sid(id)})]);await db.exec('set role authenticated');};
const common=async()=>(await db.query('select public.read_company_common_allowances_admin($1) value',[cid])).rows[0].value;
const timeline=async()=>(await db.query('select public.read_company_common_payroll_publications($1) value',[cid])).rows[0].value;
const legacy=s=>s.legacy_refs.map(({slot,id,generation,name,source_unit,amount_yen})=>({slot,id,generation,name,source_unit,amount_yen}));
const save=async(s,items)=>(await db.query('select public.save_company_common_allowances($1,$2,$3,$4::jsonb,$5,$6::jsonb,$7::jsonb,true) value',[cid,'monthly',s.version,JSON.stringify(s.expected_source),rid(++n),JSON.stringify(items),JSON.stringify(legacy(s))])).rows[0].value;
const publish=async(s,month,id=rid(++n))=>(await db.query('select public.publish_company_common_payroll($1,$2,$3,$4,$5::jsonb,$6,$7) value',[cid,'monthly',month,s.common_version,JSON.stringify(s.common_source),s.timeline_version,id])).rows[0].value;
const statement=async(month)=>{await db.exec('reset role');return(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,month])).rows[0];};
try {
 await setupPayrollScopeFixture(db);
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
 const dates=(await db.query("select date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date::text month_key,(date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')-interval '1 month')::date::text previous_key,(date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')+interval '1 month')::date::text next_key,(date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')+interval '2 months')::date::text later_key")).rows[0];

 await db.exec(read('docs/candidates/company_common_payroll_retroactive_20261021.sql.review-only'));
 const past=(await db.query("select (date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')-interval '3 months')::date::text a,(date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')-interval '2 months')::date::text b")).rows[0];
 await db.query('insert into company_common_allowance_private.payroll_activation values($1,$2)',[cid,past.a]);
 const plan=async()=>{await actor();await db.exec('reset role');return(await db.query('select common_payroll_retro_review_private.plan($1,$2,$3) v',[cid,'monthly',past.a])).rows[0].v;};
 const apply=async(p,id=rid(++n),confirmed=true)=>{await actor();await db.exec('reset role');return(await db.query('select common_payroll_retro_review_private.apply_plan($1,$2,$3,$4,$5::jsonb,$6) v',[cid,'monthly',past.a,id,JSON.stringify(p),confirmed])).rows[0].v;};
 for(const month of [past.a,past.b,dates.previous_key,dates.month_key])await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);
 await actor();let settings=await common();
 const extra=amount=>({id:settings.items[0]?.id??null,client_key:'retro',section:'earning',unit:'month',name:'Retro common',amount_yen:amount});
 settings=await save(settings,[extra(1000)]);
 await publish(await timeline(),dates.month_key);
 await db.exec('reset role');
 const beforeCurrent=await statement(dates.month_key),before=await statement(past.b);
 let p=await plan();
 assert.equal(p.eligible_count,3);assert.ok(p.entries.some(e=>e.reason==='later_publication_preserved'));
 assert.deepEqual(await statement(past.b),before,'read plan makes no financial writes');
 await assert.rejects(apply(p,undefined,false),/explicit reviewed plan/);
 const id=rid(++n),first=await apply(p,id);
 assert.equal(first.recalculated_scopes,3);assert.equal(first.blocked_scopes,0);
 assert.equal((await statement(past.b)).gross_pay,301000);
 assert.deepEqual(await statement(dates.month_key),beforeCurrent,'later effective publication remains exact');
 const applied=await statement(past.b);assert.deepEqual(await apply(p,id),first);assert.deepEqual(await statement(past.b),applied,'receipt replay has no second calculation');
 await assert.rejects(apply({...p,eligible_count:4},id),/request mismatch/);
 // Preserve actual finalized snapshot and synthetic existing manual statement.
 let finalRow=await statement(past.a);
 await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[finalRow.id,owner,finalRow.revision]);
 await actor();await db.query('select public.finalize_payroll_statement($1,$2,true)',[finalRow.id,finalRow.revision]);
 const frozen=await statement(past.a);
 await db.query("update public.payroll_statements set automatic_calculation=false where company_id=$1 and worker_id=$2 and period_start=$3",[cid,wid,dates.previous_key]);
 const manual=await statement(dates.previous_key);
 // Existing individual custom earning must survive the common publication/recalculation.
 await db.query("update public.worker_payroll_settings set custom_earnings='[{\"name\":\"Individual retained\",\"amount_yen\":500}]' where company_id=$1 and worker_id=$2",[cid,wid]);
 await actor();settings=await save(settings,[extra(2000)]);
 p=await plan();assert.equal(p.eligible_count,1);
 for(const reason of ['finalized_or_locked','manual_statement','later_publication_preserved'])assert.ok(p.entries.some(e=>e.reason===reason),reason);
 const stale=p;
 await db.exec('reset role');await db.query('update public.worker_payroll_settings set transport_monthly=123 where company_id=$1 and worker_id=$2',[cid,wid]);
 await assert.rejects(apply(stale),/plan changed/);
 p=await plan();
 const second=await apply(p);
 assert.equal(second.recalculated_scopes,1);assert.equal(second.excluded_count,p.excluded_count);
 assert.equal((await statement(past.b)).gross_pay,302623,'common plus individual earning and transport are retained');
 assert.deepEqual(await statement(past.a),frozen);assert.deepEqual(await statement(dates.previous_key),manual);assert.deepEqual(await statement(dates.month_key),beforeCurrent);
 // A receipt failure rolls back all publication and financial writes together.
 await actor();settings=await save(settings,[extra(3000)]);p=await plan();
 const financialBefore=await statement(past.b);await actor();const timelineBefore=await timeline();await db.exec('reset role');
 await db.exec("create function common_payroll_retro_review_private.fail_receipt() returns trigger language plpgsql as $$begin raise exception 'retro receipt failure';end$$;create trigger fail_receipt before insert on common_payroll_retro_review_private.receipts for each row execute function common_payroll_retro_review_private.fail_receipt()");
 await assert.rejects(apply(p),/retro receipt failure/);
 assert.deepEqual(await statement(past.b),financialBefore);await actor();assert.deepEqual(await timeline(),timelineBefore);
 await actor(viewer);await db.exec('reset role');await assert.rejects(db.query('select common_payroll_retro_review_private.plan($1,$2,$3)',[cid,'monthly',past.a]),/access denied/);
 await actor();await assert.rejects(db.query('select common_payroll_retro_review_private.plan($1,$2,$3)',[cid,'monthly',past.a]),/permission denied/,'candidate remains ungranted to clients');
 console.log('PASS retroactive read-plan/no-write, explicit confirmation, real refresh, all historical drafts, later boundary, replay/CAS, real final snapshot/manual/individual preservation, source mutation, late rollback and ACL');
} catch(error){console.error(error);process.exitCode=1;} finally {await db.close();}
