// Uses exact reviewed payroll calculator + normalization triggers in isolated SQL.
// Synthetic schema/access prerequisites; never connects to a linked database.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001';
const editor='00000000-0000-0000-0000-000000000002';
const viewer='00000000-0000-0000-0000-000000000003';
const otherOwner='00000000-0000-0000-0000-000000000004';
async function actor(id,role='authenticated',denied=false) {
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('test.account_access_denied',$2,false)",[id,denied?'1':'']);
 await db.exec(`set role ${role}`);
}
async function save(version,mode,cutover,entries,confirmed=true) {
 return (await db.query('select public.save_worker_resident_tax_schedule($1,$2,$3,$4,$5,$6::jsonb,$7) as result',[cid,wid,version,mode,cutover,JSON.stringify(entries),confirmed])).rows[0].result;
}
async function state(month) {
 return (await db.query('select public.read_worker_resident_tax_schedule($1,$2,$3) as result',[cid,wid,month])).rows[0].result;
}
async function statement(month) {
 await db.exec('reset role');
 return (await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,month])).rows[0];
}
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_calculation_invariant_fixture.sql'));
 await db.exec(read('supabase/migrations/20261006162510_payroll_flexible_earnings_deductions_payment_day.sql'));
 await db.exec(read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql'));
 await db.exec(read('supabase/migrations/20261008001025_payroll_statement_pay_type_metadata.sql'));
 await db.exec(read('supabase/migrations/20261008035104_stabilize_automatic_payroll_totals.sql'));
 await db.exec(`create table public.paid_leave_requests(company_id uuid,worker_id uuid,leave_date date,status text); alter table public.workers add column status text default 'active',add column affiliation text default 'employee',add column hire_date date;`);
 await db.exec(read('supabase/migrations/20261008040428_generate_fixed_monthly_payroll_without_attendance.sql'));

 await db.exec(`alter table public.attendance_entries add primary key(id),add column night_hours numeric default 0;
 alter table public.worker_payroll_settings add column night_daily numeric default 15000,
 add column night_overtime numeric default 2000,add column night_early numeric default 2000,
 add column holiday_daily numeric default 13500,add column holiday_overtime numeric default 2000,
 add column holiday_early numeric default 2000,add column holiday_night_daily numeric default 16000,
 add column holiday_night_overtime numeric default 2500,add column holiday_night_early numeric default 2500,
 add column allowance_name_1 text,add column allowance_1 numeric default 0;
 delete from public.payroll_statements; delete from public.attendance_entries;
 update public.worker_payroll_settings set pay_type='daily',day_daily=10000,day_overtime=1563,day_early=1563,
 monthly_salary_yen=0,custom_earnings='[]',custom_deductions='[]' where worker_id='${wid}';`);
 await db.exec(read('supabase/tests/payroll_live_linkage_snapshot.sql'));
 await db.exec(`create trigger attendance_refresh_payroll after insert or update or delete on public.attendance_entries
 for each row execute function private.attendance_refresh_payroll();
 create trigger attendance_sync_payroll_detail after insert or update or delete on public.attendance_entries
 for each row execute function private.attendance_sync_payroll_detail();
 create trigger settings_refresh_payroll after insert or update on public.worker_payroll_settings
 for each row execute function private.settings_refresh_payroll();
 create trigger paid_leave_sync_payroll_detail after insert or update or delete on public.paid_leave_requests
 for each row execute function private.paid_leave_sync_payroll_detail();`);
 // Optional reviewed migration(s) under test can override snapshots without editing them.
 for(const migration of ['supabase/migrations/20261008042817_prevent_paid_leave_attendance_overlap.sql','supabase/migrations/20261008043151_align_future_attendance_monthly_payroll_boundary.sql','supabase/migrations/20261008045401_preserve_payroll_named_financial_details.sql']) await db.exec(read(migration));
 await db.exec(`alter table public.worker_payroll_settings add column if not exists rate_formula jsonb default '{}', add column if not exists hourly_rate_yen numeric default 0;`);
 await db.exec(read('supabase/migrations/20261008200018_paid_leave_wage_contract.sql'));

 await db.exec(read('supabase/tests/resident_tax_effective_month_access_fixture.sql'));
 const baseline=(await db.query("select pg_get_functiondef('private.refresh_automatic_payroll_internal(uuid,uuid,date)'::regprocedure) as definition")).rows[0].definition;
 await db.exec("create or replace function private.refresh_automatic_payroll_internal(cid uuid,wid uuid,day date) returns void language plpgsql security definer set search_path='' as $$begin return; end$$");
 await assert.rejects(db.exec(read('supabase/migrations/20261009161427_resident_tax_effective_month.sql')),/prerequisite differs/);
 assert.equal((await db.query("select to_regnamespace('resident_tax_private') as namespace")).rows[0].namespace,null,'unknown source guard must stop before new schema writes');
 await db.exec(baseline);
 await db.exec(read('supabase/migrations/20261009161427_resident_tax_effective_month.sql'));
 await actor(editor);
 assert.equal((await db.query('select public.resident_tax_schedule_contract_version() as version')).rows[0].version,1);
 await actor(owner,'anon');
 await assert.rejects(db.query('select public.resident_tax_schedule_contract_version()'),/permission denied/);
 await db.exec('reset role');
 assert.equal((await db.query("select has_function_privilege('anon','public.resident_tax_schedule_contract_version()','execute') as allowed")).rows[0].allowed,false);
 // Exact live function hashes are prerequisites; the harness verifies them through
 // the migration guard after applying the same original migrations and triggers.
 await db.exec(`delete from public.attendance_entries; delete from public.paid_leave_requests; delete from public.payroll_statements;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,
 family_monthly=0,transport_monthly=0,income_tax_monthly=0,resident_tax_monthly=12000,social_insurance_monthly=0,other_deduction_monthly=0,custom_earnings='[]',custom_deductions='[]';`);
 const months=(await db.query(`select date_trunc('month',(now() at time zone 'Asia/Tokyo')::date)::date::text as current,
 (date_trunc('month',(now() at time zone 'Asia/Tokyo')::date)+interval '1 month')::date::text as future,
 (date_trunc('month',(now() at time zone 'Asia/Tokyo')::date)-interval '1 month')::date::text as old`)).rows[0];
 await db.query('select private.refresh_automatic_payroll_internal($1,$2,$3),private.sync_payroll_attendance_detail($1,$2,$3)',[cid,wid,months.current]);
 const initial=await statement(months.current);
 assert.equal(initial.deductions,12000);assert.equal(initial.net_pay,288000);
 for(const id of [viewer,otherOwner,'']) {
  await actor(id);await assert.rejects(save(0,'timeline',months.future,[{effective_month:months.future,amount_yen:15000}]),/access denied/);
 }
 await actor(owner,'anon');await assert.rejects(save(0,'legacy',null,[]),/permission denied/);
 await actor(owner,'authenticated',true);await assert.rejects(state(months.current),/access denied/);
 await actor(editor);
 await assert.rejects(db.query('select public.read_worker_resident_tax_schedule($1,$2,$3) as result',['10000000-0000-0000-0000-000000000002',wid,months.current]),/access denied/);
 await assert.rejects(db.query('select public.save_worker_resident_tax_schedule($1,$2,0,$3,$4,$5::jsonb,true) as result',['10000000-0000-0000-0000-000000000002',wid,'legacy',null,'[]']),/access denied/);
 // This editor is an ordinary member with can_edit payroll access, not owner/admin.
 await assert.rejects(db.query('select * from resident_tax_private.state'),/permission denied/);
 await assert.rejects(save(0,'timeline',months.future,[{effective_month:months.future,amount_yen:15000}],false),/unconfirmed/);
 const future=await save(0,'timeline',months.future,[{effective_month:months.future,amount_yen:15000}]);
 assert.equal(future.version,1);assert.equal(future.mode,'timeline');
 const beforeCutover=await state(months.current);assert.deepEqual(beforeCutover.resolved,{mode:'legacy',amount_yen:12000});
 assert.equal(beforeCutover.history[0].before_value,null);assert.equal(beforeCutover.history[0].actor_id,editor);
 assert.deepEqual(await statement(months.current),initial,'future first registration must not touch any current draft field');
 assert.equal(await statement(months.future),undefined,'future registration must not create a future draft');
 await actor(editor);
 assert.deepEqual((await state(months.future)).resolved,{mode:'timeline',effective_month:months.future,amount_yen:15000});
 const beforeInvalid=await state(months.current);
 await assert.rejects(save(0,'timeline',months.future,[{effective_month:months.future,amount_yen:15000}]),/version conflict/);
 await assert.rejects(save(1,'timeline',months.current,[{effective_month:months.future,amount_yen:15000}]),/first entry/);
 await assert.rejects(save(1,'timeline',months.current,[{effective_month:months.current,amount_yen:1.5}]),/monthly entry/);
 await assert.rejects(save(1,'timeline',months.current,[{effective_month:months.current,amount_yen:-1}]),/monthly entry/);
 await assert.rejects(save(1,'timeline',months.current,[{effective_month:months.current,amount_yen:1},{effective_month:months.current,amount_yen:2}]),/duplicate/);
 assert.deepEqual(await state(months.current),beforeInvalid);
 const adopted=await save(1,'timeline',months.current,[{effective_month:months.current,amount_yen:15000},{effective_month:months.future,amount_yen:18000}]);
 assert.equal(adopted.version,2);
 const changed=await statement(months.current);
 assert.equal(changed.deductions,15000);assert.equal(changed.net_pay,285000);
 assert.equal(changed.detail['住民税'],15000);assert.equal(changed.detail.resident_tax_source.mode,'timeline');
 assert.ok(changed.revision>initial.revision);assert.notEqual(changed.calculation_fingerprint,initial.calculation_fingerprint);
 await actor(editor);assert.deepEqual((await state(months.old)).resolved,{mode:'legacy',amount_yen:12000});
 // Future-only edits and whole-schedule version changes do not invalidate reviews.
 await save(2,'timeline',months.current,[{effective_month:months.current,amount_yen:15000},{effective_month:months.future,amount_yen:19000}]);
 assert.deepEqual(await statement(months.current),changed);
 await actor(editor);await save(3,'timeline',months.current,[{effective_month:months.current,amount_yen:0},{effective_month:months.future,amount_yen:19000}]);
 const zero=await statement(months.current);
 assert.equal(zero.deductions,0);assert.equal(zero.net_pay,300000);assert.equal(zero.detail['住民税'],0);
 await db.exec('reset role');
 assert.equal((await db.query('select resident_tax_monthly::int as amount from public.worker_payroll_settings where worker_id=$1',[wid])).rows[0].amount,12000,'timeline must not copy computed amounts into legacy field');
 // Actual source changes reset draft approval while manual/finalized rows remain exact.
 await db.query("update public.payroll_statements set approved_ids=array[$1::uuid] where id=$2",[owner,zero.id]);
 await actor(editor);await save(4,'timeline',months.current,[{effective_month:months.current,amount_yen:7000}]);
 const reviewed=await statement(months.current);assert.deepEqual(reviewed.approved_ids,[]);assert.equal(reviewed.net_pay,293000);
 await db.query('update public.payroll_statements set automatic_calculation=false where id=$1',[reviewed.id]);
 const manual=await statement(months.current);
 await actor(editor);await save(5,'timeline',months.current,[{effective_month:months.current,amount_yen:8000}]);
 assert.deepEqual(await statement(months.current),manual);
 await db.query("update public.payroll_statements set automatic_calculation=true,workflow_state='finalized' where id=$1",[manual.id]);
 const finalized=await statement(months.current);
 await actor(editor);await save(6,'timeline',months.current,[{effective_month:months.current,amount_yen:9000}]);
 assert.deepEqual(await statement(months.current),finalized);
 // Force failed audit and prove timeline header/entries/history transaction rollback.
 await db.exec(`create function resident_tax_private.fixture_audit_fail() returns trigger language plpgsql as $$begin raise exception 'synthetic resident tax audit unavailable'; end$$;
 create trigger fixture_audit_fail before insert on resident_tax_private.history for each row execute function resident_tax_private.fixture_audit_fail()`);
 await actor(editor);const beforeFailure=await state(months.current);
 await assert.rejects(save(7,'legacy',null,[]),/synthetic resident tax audit unavailable/);
 assert.deepEqual(await state(months.current),beforeFailure);
 await db.exec('reset role');
 await db.exec('drop trigger fixture_audit_fail on resident_tax_private.history');
 await db.query("update public.payroll_statements set workflow_state='draft' where id=$1",[finalized.id]);
 await db.query('select private.refresh_automatic_payroll_internal($1,$2,$3),private.sync_payroll_attendance_detail($1,$2,$3)',[cid,wid,months.current]);
 const beforeRefreshFailure=await statement(months.current);
 await db.exec(`create function private.fixture_payroll_audit_fail() returns trigger language plpgsql as $$begin raise exception 'synthetic payroll refresh audit unavailable'; end$$;
 create trigger fixture_payroll_audit_fail before insert on public.payroll_audit for each row execute function private.fixture_payroll_audit_fail()`);
 await actor(editor);const beforeRefreshState=await state(months.current);
 await assert.rejects(save(7,'timeline',months.current,[{effective_month:months.current,amount_yen:10000}]),/synthetic payroll refresh audit unavailable/);
 assert.deepEqual(await state(months.current),beforeRefreshState,'refresh failure must roll back timeline and its audit');
 assert.deepEqual(await statement(months.current),beforeRefreshFailure,'refresh failure must roll back actual draft amounts/revision/fingerprint/review');
 await actor(viewer);assert.equal((await state(months.current)).resolved.amount_yen,9000,'existing payroll view grant must be respected');
 await db.exec('reset role');await db.exec('drop trigger fixture_payroll_audit_fail on public.payroll_audit');
 const noSettingsWorker='40000000-0000-0000-0000-000000000003';
 await db.query("insert into public.workers(id,company_id,user_id,name,status,affiliation) values($1,$2,$3,'No wage settings','active','employee')",[noSettingsWorker,cid,editor]);
 await actor(editor);
 await db.query('select public.save_worker_resident_tax_schedule($1,$2,0,$3,$4,$5::jsonb,true)',[cid,noSettingsWorker,'timeline',months.current,JSON.stringify([{effective_month:months.current,amount_yen:1000}])]);
 await db.exec('reset role');
 await db.query("insert into public.attendance_entries(company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours) values($1,$2,'70000000-0000-0000-0000-000000000001',(now() at time zone 'Asia/Tokyo')::date,'day',1,0,0)",[cid,noSettingsWorker]);
 const noSettings=(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2',[cid,noSettingsWorker])).rows[0];
 assert.equal(noSettings.deductions,1000);assert.equal(noSettings.net_pay,0);
 await db.query('select private.refresh_automatic_payroll_internal($1,$2,$3)',[cid,noSettingsWorker,months.current]);
 assert.equal((await db.query('select revision from public.payroll_statements where id=$1',[noSettings.id])).rows[0].revision,noSettings.revision,'missing wage settings must not cause repeated resident-tax revision mismatch');
 console.log('PASS exact resident tax integration: existing payroll access, legacy/future cutover, month/zero, direct source, atomic audit+refresh, stable future-only drafts, review invalidation, manual/finalized preservation');
} finally {await db.close();}
