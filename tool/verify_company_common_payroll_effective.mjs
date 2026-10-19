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
 const currentScopeCount=(await db.query("select count(*)::int n from public.worker_payroll_settings where company_id=$1 and pay_type='monthly'",[cid])).rows[0].n;
 await db.query('insert into company_common_allowance_private.payroll_activation values($1,$2)',[cid,dates.previous_key]);
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,dates.month_key]);
 let row=await statement(dates.month_key);assert.equal(row.calculation_blocked,true,'missing dated history blocks; no current-rate guess');
 await actor();let settings=await common();
 const extra=(amount,id=null)=>({id,client_key:'common-one',section:'earning',unit:'month',name:'Common month',amount_yen:amount});
 settings=await save(settings,[extra(1000)]);let t=await timeline();
 await assert.rejects(publish(t,dates.previous_key),/past payroll publication/);
 const request=rid(++n);const first=await publish(t,dates.month_key,request);assert.equal(first.recalculated_scopes,currentScopeCount);assert.equal(first.publication_version,1);
 row=await statement(dates.month_key);assert.equal(row.calculation_blocked,false);assert.equal(row.gross_pay,301000);assert.equal(row.net_pay,row.gross_pay-row.deductions);
 const beforeRevision=row.revision;await actor();assert.deepEqual(await publish(t,dates.month_key,request),first);assert.equal((await statement(dates.month_key)).revision,beforeRevision,'same request does not recalculate twice');
 await actor();settings=await save(settings,[extra(2000,settings.items[0].id)]);
 await db.exec('reset role');await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,dates.month_key]);
 assert.equal((await statement(dates.month_key)).gross_pay,301000,'editing common defaults does not rewrite published month');
 await actor();t=await timeline();await publish(t,dates.next_key);
 await db.exec('reset role');await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,dates.next_key]);
 assert.equal((await statement(dates.next_key)).gross_pay,302000);assert.equal((await statement(dates.month_key)).gross_pay,301000);
 await actor();settings=await save(settings,[extra(3000,settings.items[0].id)]);t=await timeline();const current=await publish(t,dates.month_key);
 assert.equal(current.recalculated_scopes,currentScopeCount,'next effective boundary excluded from recalculation');assert.equal((await statement(dates.month_key)).gross_pay,303000);assert.equal((await statement(dates.next_key)).gross_pay,302000);
 await actor();await assert.rejects(publish(t,dates.month_key),/source conflict/);await actor(viewer);await assert.rejects(publish(await timeline(),dates.month_key),/access denied/);
 await actor();row=await statement(dates.month_key);await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[row.id,owner,row.revision]);await actor();await db.query('select public.finalize_payroll_statement($1,$2,true)',[row.id,row.revision]);const frozen=await statement(dates.month_key);
 await actor();settings=await save(settings,[extra(4000,settings.items[0].id)]);t=await timeline();const frozenResult=await publish(t,dates.month_key);assert.equal(frozenResult.recalculated_scopes,currentScopeCount-1);assert.deepEqual(await statement(dates.month_key),frozen);
 await actor();const frozenCommon=(await db.query('select public.payroll_unit_conditions($1,$2,$3) value',[cid,wid,dates.month_key])).rows[0].value;assert.equal(frozenCommon.company_common.frozen,true);assert.equal(frozenCommon.company_common.items[0].rate_yen,3000,'individual display uses saved final statement, not new published 4000');

 await db.exec('reset role');await assert.rejects(db.query('update company_common_allowance_private.payroll_publications set common_version=99 where company_id=$1',[cid]),/immutable/);
 if(pg) {
  // Genuine native lock wait: common settings advance while a publisher waits.
  await actor();const waitingSource=await timeline();await db.exec('reset role');
  const blocker=new pg.Client({connectionString:process.env.SKO_COMMON_EFFECTIVE_FIXTURE_URL});
  const publisher=new pg.Client({connectionString:process.env.SKO_COMMON_EFFECTIVE_FIXTURE_URL});
  await blocker.connect();await publisher.connect();
  try {
   const claims=JSON.stringify({sub:owner,role:'authenticated',session_id:sid(owner)});
   for(const client of [blocker,publisher])await client.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[owner,claims]);
   await blocker.query('begin');await blocker.query('select 1 from public.companies where id=$1 for update',[cid]);
   await publisher.query('set role authenticated');
   const waiting=publisher.query('select public.publish_company_common_payroll($1,$2,$3,$4,$5::jsonb,$6,$7)',[cid,'monthly',dates.next_key,waitingSource.common_version,JSON.stringify(waitingSource.common_source),waitingSource.timeline_version,rid(++n)]).then(value=>({value}),error=>({error}));
   let observed=false;
   for(let attempt=0;attempt<40;attempt++) {
    const state=(await db.query('select wait_event_type from pg_stat_activity where pid=$1',[publisher.processID])).rows[0];
    if(state?.wait_event_type==='Lock'){observed=true;break;}
    await new Promise(resolve=>setTimeout(resolve,50));
   }
   assert.equal(observed,true,'publisher genuinely waits on company scope');
   settings=(await blocker.query('select public.save_company_common_allowances($1,$2,$3,$4::jsonb,$5,$6::jsonb,$7::jsonb,true) value',[cid,'monthly',settings.version,JSON.stringify(settings.expected_source),rid(++n),JSON.stringify([extra(5000,settings.items[0].id)]),JSON.stringify(legacy(settings))])).rows[0].value;
   await blocker.query('commit');const result=await waiting;assert.match(result.error?.message??'',/source conflict/);
   await actor();assert.equal((await timeline()).timeline_version,waitingSource.timeline_version,'waiting stale publisher adds no history');
  } finally {await blocker.query('rollback');await blocker.end();await publisher.end();}
 }
 if(pg) {
  // Prove the inherited #1276 worker lock serializes common-hour CAS and finalization.
  await actor();settings=await save(settings,[extra(5000,settings.items[0].id),{id:null,client_key:'hour',section:'earning',unit:'hour',name:'Common hours',amount_yen:100}]);
  await publish(await timeline(),dates.next_key);
  const hourId=settings.items.find(x=>x.unit==='hour').id;
  const readHourSource=async()=>{await actor();return (await db.query('select public.payroll_unit_conditions($1,$2,$3) value',[cid,wid,dates.next_key])).rows[0].value.company_common.source;};
  const source=await readHourSource();await db.exec('reset role');
  const first=new pg.Client({connectionString:process.env.SKO_COMMON_EFFECTIVE_FIXTURE_URL});const second=new pg.Client({connectionString:process.env.SKO_COMMON_EFFECTIVE_FIXTURE_URL});
  await first.connect();await second.connect();
  const observe=async()=>{for(let attempt=0;attempt<40;attempt++){const row=(await db.query('select wait_event_type from pg_stat_activity where pid=$1',[second.processID])).rows[0];if(row?.wait_event_type==='Lock')return;await new Promise(resolve=>setTimeout(resolve,50));}throw Error('native common-hour writer did not wait');};
  const hours=amount=>JSON.stringify([{id:hourId,quantity:amount}]);
  const sql='select public.save_payroll_common_hours($1,$2,$3,$4::jsonb,$5::jsonb)';
  try {
   for(const client of [first,second]){await client.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[owner,JSON.stringify({sub:owner,role:'authenticated',session_id:sid(owner)})]);await client.query('set role authenticated');}
   await first.query('begin');await first.query(sql,[cid,wid,dates.next_key,JSON.stringify(source),hours('1')]);
   const waiting=second.query(sql,[cid,wid,dates.next_key,JSON.stringify(source),hours('2')]).then(value=>({value}),error=>({error}));await observe();await first.query('commit');assert.match((await waiting).error?.message??'',/source conflict/);
   const current=await statement(dates.next_key);assert.equal(current.detail.unit_resolution.items.find(x=>x.id===hourId).quantity,1);
   const fresh=await readHourSource();await db.exec('reset role');
   await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[current.id,owner,current.revision]);
   await first.query('begin');await first.query('select public.finalize_payroll_statement($1,$2,true)',[current.id,current.revision]);
   const afterFinalize=second.query(sql,[cid,wid,dates.next_key,JSON.stringify(fresh),hours('3')]).then(value=>({value}),error=>({error}));await observe();await first.query('commit');assert.match((await afterFinalize).error?.message??'',/finalized\/manual/);
   assert.equal((await db.query('select hours from payroll_unit_private.quantities where company_id=$1 and worker_id=$2 and item_id=$3 and month=$4',[cid,wid,hourId,dates.next_key])).rows[0].hours,1);
  } finally {await first.query('rollback');await first.end();await second.end();}
  // A later mutable month provides the financial rollback target after the race finalized next month.
  await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,dates.later_key]);
  await actor();settings=await save(settings,[extra(6000,settings.items.find(x=>x.unit==='month').id)]);
 }
 const rollbackMonth=pg?dates.later_key:dates.next_key;
 await db.exec('reset role');
 // A late receipt failure must roll back publication, every recalculated draft, and its receipt.
 await db.exec("create function company_common_allowance_private.fail_publication_receipt() returns trigger language plpgsql as $$begin raise exception 'fixture receipt failure';end$$;create trigger fail_publication_receipt before insert on company_common_allowance_private.payroll_publication_receipts for each row execute function company_common_allowance_private.fail_publication_receipt()");
 const oldFuture=await statement(rollbackMonth);await actor();t=await timeline();await assert.rejects(publish(t,rollbackMonth),/fixture receipt failure/);assert.deepEqual(await statement(rollbackMonth),oldFuture);await actor();assert.equal((await timeline()).timeline_version,t.timeline_version);
 console.log('PASS actual common saver -> immutable effective-month publication -> real payroll recalculation; history, future boundary, retry, CAS, viewer, finalized and late rollback');
} catch(error) {console.error(error.message);console.error(error.stack.split('\n').filter(x=>x.includes('verify_company_common_payroll_effective')).join('\n'));process.exitCode=1;} finally {await db.close();}
