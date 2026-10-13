import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',editor='00000000-0000-0000-0000-000000000002';
async function actor(id,role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec(`set role ${role}`);}
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

 await db.exec(read('supabase/tests/finalized_payroll_document_access_fixture.sql'));
 const glyph=read('supabase/migrations/20261009011357_company_seal_aoyagi_style.sql'); await db.exec(glyph.slice(glyph.indexOf('create function private.aoyagi_reisho_name_supported'),glyph.indexOf('revoke all on function private.aoyagi_reisho_name_supported')));
 const seal=read('supabase/migrations/20261009012730_company_seal_document_snapshots.sql');
 await db.exec(seal.slice(0,seal.indexOf('create function private.preserve_document_company_seal_snapshot')));
 const payDate=read('supabase/migrations/20261008004129_payroll_assigned_confirmation_notifications.sql').split('create function private.payroll_payment_date')[1];
 await db.exec('create function private.payroll_payment_date'+payDate.slice(0,payDate.indexOf('end $$;')+7));
 console.log('install live definitions'); await db.exec(read('supabase/tests/finalized_payroll_live_source_fixture.sql'));
 await db.exec(`grant execute on function public.create_payroll_adjustment(uuid,uuid,integer,date,text),public.update_payroll_adjustment(uuid,uuid,integer,date,text),public.cancel_payroll_adjustment(uuid,text) to authenticated; create function public.payroll_review_workspace(day date) returns jsonb language sql stable security definer set search_path='' as $$select private.payroll_review_workspace(day)$$; grant execute on function public.payroll_review_workspace(date) to authenticated;`);
 const psTriggerNames=(await db.query("select tgname from pg_trigger where tgrelid='public.payroll_statements'::regclass and not tgisinternal order by tgname")).rows.map(r=>r.tgname);
 assert.deepEqual(psTriggerNames,['aa_monthly_salary_statement_guard','deletion_history_attribution_guard','guard_blocked_payroll','payroll_custom_money_guard','zz_company_seal_snapshot','zz_monthly_salary_detail_guard']);
 const originalMyRows=(await db.query("select pg_get_functiondef('public.my_payroll_statement_rows_with_adjustments()'::regprocedure) as definition")).rows[0].definition;
 await db.exec("create or replace function public.my_payroll_statement_rows_with_adjustments() returns table(id uuid,period_start date,period_end date,gross_pay integer,deductions integer,net_pay integer,detail jsonb,issued_at timestamptz,company_name text,worker_name text) language plpgsql stable security definer set search_path='' as $$begin return;end$$");
 await assert.rejects(db.exec(read('supabase/migrations/20261009165026_finalized_payroll_document_snapshot.sql')),/prerequisite differs/);
 assert.equal((await db.query("select to_regnamespace('payroll_final_private') as schema")).rows[0].schema,null);
 await db.exec(originalMyRows);

 // Reproduce the old all-row live-helper overflow before installing the fix.
 await db.exec(`update public.companies set name='Original Company'; grant execute on function public.my_payroll_statement_rows_with_adjustments() to authenticated;`);
 const overflowLegacy='50000000-0000-0000-0000-000000000097';
 await db.query("insert into public.payroll_statements(id,company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,detail,workflow_state,automatic_calculation) values($1,$2,$3,'2024-01-01','2024-01-31',9000,1000,8000,'{}','finalized',true)",[overflowLegacy,cid,wid]);
 for(let i=0;i<2;i++)await db.query("insert into public.payroll_adjustments(company_id,worker_id,effective_date,label_snapshot,direction,amount_yen) values($1,$2,'2024-01-10','Later legacy addition','addition',2000000000)",[cid,wid]);
 await actor(owner);await assert.rejects(db.query('select * from public.my_payroll_statement_rows_with_adjustments()'),/integer out of range/);
 await assert.rejects(db.query("select public.payroll_review_workspace('2024-01-01')"),/integer out of range/);
 await db.exec('reset role');
 console.log('install new migration'); await db.exec(read('supabase/migrations/20261009165026_finalized_payroll_document_snapshot.sql'));

 await actor(owner);assert.equal((await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===overflowLegacy).net_pay,8000);
 const legacyWorkspace=(await db.query("select public.payroll_review_workspace('2024-01-01') as result")).rows[0].result;assert.equal(legacyWorkspace.statements.find(r=>r.id===overflowLegacy).net_pay,8000);
 await db.exec('reset role');await db.query("delete from public.payroll_adjustments where effective_date='2024-01-10'");
 await db.exec(`update public.companies set name='Original Company'; delete from public.payroll_statements;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,family_monthly=0,transport_monthly=0,income_tax_monthly=0,resident_tax_monthly=12000,social_insurance_monthly=0,other_deduction_monthly=0,custom_earnings='[]',custom_deductions='[]';
 insert into public.payroll_confirmers values('${cid}','${owner}',1);
 insert into public.payroll_adjustment_types values('90000000-0000-0000-0000-000000000001','${cid}','Extra','addition',true);`);
 let ps=(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 order by period_start desc limit 1',[cid,wid])).rows[0];
 assert.equal(ps.net_pay,288000);
 async function finalize(revision=ps.revision,confirmed=true){return (await db.query('select public.finalize_payroll_statement($1,$2,$3) as result',[ps.id,revision,confirmed])).rows[0].result;}
 await actor(editor);
 await assert.rejects(finalize(ps.revision,false),/explicit/);
 await assert.rejects(finalize(ps.revision-1),/revision conflict/);
 await assert.rejects(finalize(),/reviews required/);
 const readStatus=async()=> (await db.query('select public.read_payroll_finalization_status($1) as result',[ps.id])).rows[0].result;
 assert.equal((await readStatus()).can_finalize,false);
 await actor('00000000-0000-0000-0000-000000000003');assert.equal((await readStatus()).can_finalize,false);
 await actor('00000000-0000-0000-0000-000000000099');await assert.rejects(readStatus(),/access denied/);
 await actor(editor);
 await actor(owner);
 const aid=(await db.query('select public.create_payroll_adjustment($1,$2,5000,$3,null) as id',[wid,'90000000-0000-0000-0000-000000000001',ps.period_start])).rows[0].id;
 await db.exec('reset role');
 const adjusted=(await db.query('select * from public.payroll_statements where id=$1',[ps.id])).rows[0];assert.equal(adjusted.revision,ps.revision+1);
 await db.query('select private.refresh_automatic_payroll_internal($1,$2,$3)',[cid,wid,ps.period_start]);
 ps=(await db.query('select * from public.payroll_statements where id=$1',[ps.id])).rows[0];assert.equal(ps.revision,adjusted.revision,'normal calculator must retain adjustment-invalidated revision');
 await actor(owner);await db.query('select public.update_payroll_adjustment($1,$2,5000,$3,$4)',[aid,'90000000-0000-0000-0000-000000000001',ps.period_start,'note only']);
 await db.exec('reset role');assert.equal((await db.query('select revision from public.payroll_statements where id=$1',[ps.id])).rows[0].revision,ps.revision,'note-only update must retain revision');
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[ps.id,owner,ps.revision]);
 await actor(editor);
 const statusBefore=await readStatus();assert.equal(statusBefore.can_finalize,true);assert.equal(statusBefore.contract_version,1);assert.equal(statusBefore.revision,ps.revision);
 await db.exec('reset role');
 await db.exec("create function payroll_final_private.fixture_fail() returns trigger language plpgsql as $$begin raise exception 'snapshot audit unavailable';end$$; create trigger fixture_fail before insert on payroll_final_private.history for each row execute function payroll_final_private.fixture_fail()");
 await actor(editor);await assert.rejects(finalize(),/snapshot audit unavailable/);
 await db.exec('reset role');assert.equal((await db.query('select workflow_state from public.payroll_statements where id=$1',[ps.id])).rows[0].workflow_state,'draft');assert.equal((await db.query('select count(*)::integer n from payroll_final_private.documents')).rows[0].n,0);
 await db.exec('drop trigger fixture_fail on payroll_final_private.history');await actor(editor);
 const result=await finalize();
 const fixturePath=process.env.SKO_PAYROLL_FINALIZATION_FIXTURE_PATH;
 if(fixturePath){fs.mkdirSync(fixturePath.slice(0,fixturePath.lastIndexOf('/')),{recursive:true});fs.writeFileSync(fixturePath,JSON.stringify(result));}
 assert.equal(result.finalized,true);assert.equal(result.snapshot.result.net_pay,293000);assert.equal(result.snapshot.adjustments[0].id,aid);assert.deepEqual(result.snapshot.detail.bank_account,{});
 assert.equal((await readStatus()).snapshot_saved,true);assert.equal((await readStatus()).can_finalize,false);
 assert.deepEqual(await finalize(),result,'same revision retry must return saved result');
 await actor(owner);await assert.rejects(db.query('select public.cancel_payroll_adjustment($1,null)',[aid]),/explicit correction/);
 await assert.rejects(db.query('select public.create_payroll_adjustment($1,$2,1000,$3,null)',[wid,'90000000-0000-0000-0000-000000000001',ps.period_start]),/explicit correction/);
 const self=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===ps.id);assert.equal(self.net_pay,293000);assert.equal(self.detail.bank_account.account_number,'0012345');
 await db.exec('reset role');await db.exec(`update public.companies set name='Changed Company',payroll_payment_day=20; update public.workers set name='Changed Worker'; update public.worker_private_bank_accounts set account_number='CHANGED'; update public.worker_payroll_settings set monthly_salary_yen=400000;`);
 await actor(owner);const reread=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===ps.id);assert.deepEqual(reread,self,'finalized self document must retain all saved amounts, names, bank and metadata');

 // A non-draft metadata call must never occur, even when its live implementation fails.
 await db.exec('reset role');await db.exec("alter function private.payroll_live_document_metadata(uuid) rename to fixture_original_live_metadata; create function private.payroll_live_document_metadata(p_statement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin if exists(select 1 from public.payroll_statements where id=p_statement_id and workflow_state<>'draft') then raise exception 'non-draft live metadata must not be read';end if;return private.fixture_original_live_metadata(p_statement_id);end$$");
 await actor(owner);assert.deepEqual((await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===ps.id),self);
 const workspace=(await db.query('select public.payroll_review_workspace($1) as value',[ps.period_start])).rows[0].value;
 const item=workspace.statements.find(r=>r.id===ps.id);assert.equal(item.net_pay,293000);assert.equal(item.company_name,'Original Company');assert.deepEqual(item.detail.bank_account,{});

 await actor('', 'anon');await assert.rejects(finalize(),/permission denied/);
 await actor('00000000-0000-0000-0000-000000000003');await assert.rejects(finalize(),/access denied/);
 await actor(editor);await assert.rejects(db.query('select * from payroll_final_private.documents'),/permission denied/);
 await db.exec('reset role');await db.query("select set_config('test.account_access_denied','1',false)");await actor(editor);await assert.rejects(finalize(),/access denied/);await assert.rejects(db.query('select * from public.my_payroll_statement_rows_with_adjustments()'),/authentication required/);
 await db.exec('reset role');await db.query("select set_config('test.account_access_denied','',false)");
 const oldId='50000000-0000-0000-0000-000000000099';
 await db.query("insert into public.payroll_statements(id,company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,detail,workflow_state,automatic_calculation,revision) values($1,$2,$3,'2025-01-01','2025-01-31',9000,1000,8000,'{}','finalized',true,1)",[oldId,cid,wid]);
 await actor(owner);await assert.rejects(db.query('select public.finalize_payroll_statement($1,1,true)',[oldId]),/legacy finalization/);

 await db.exec('reset role');for(let i=0;i<2;i++)await db.query("insert into public.payroll_adjustments(company_id,worker_id,effective_date,label_snapshot,direction,amount_yen) values($1,$2,'2025-01-10','Later addition','addition',2000000000)",[cid,wid]);await actor(owner);
 const legacy=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===oldId);assert.equal(legacy.net_pay,8000);assert.equal(legacy.company_name,'');assert.equal(legacy.detail.bank_account,undefined);


 // Noncanonical automatic periods must fail closed without any persisted change.
 await db.exec('reset role');const partial='50000000-0000-0000-0000-000000000098';
 await db.query("insert into public.payroll_statements(id,company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,detail,workflow_state,automatic_calculation,revision) values($1,$2,$3,'2025-02-02','2025-02-28',0,0,0,'{}','draft',true,1)",[partial,cid,wid]);
 const partialBefore=(await db.query('select * from public.payroll_statements where id=$1',[partial])).rows[0];
 const countsBefore=(await db.query('select (select count(*)::integer from payroll_final_private.documents) docs,(select count(*)::integer from payroll_final_private.history) history')).rows[0];
 await actor(editor);await assert.rejects(db.query('select public.finalize_payroll_statement($1,1,true)',[partial]),/canonical monthly/);
 await db.exec('reset role');assert.deepEqual((await db.query('select * from public.payroll_statements where id=$1',[partial])).rows[0],partialBefore);assert.deepEqual((await db.query('select (select count(*)::integer from payroll_final_private.documents) docs,(select count(*)::integer from payroll_final_private.history) history')).rows[0],countsBefore);
 await db.query("update public.payroll_statements set period_start='2025-02-01',period_end='2025-02-27' where id=$1",[partial]);
 const truncatedBefore=(await db.query('select * from public.payroll_statements where id=$1',[partial])).rows[0];
 await actor(editor);await assert.rejects(db.query('select public.finalize_payroll_statement($1,1,true)',[partial]),/canonical monthly/);
 await db.exec('reset role');assert.deepEqual((await db.query('select * from public.payroll_statements where id=$1',[partial])).rows[0],truncatedBefore);assert.deepEqual((await db.query('select (select count(*)::integer from payroll_final_private.documents) docs,(select count(*)::integer from payroll_final_private.history) history')).rows[0],countsBefore);
 // A displayed revision whose source silently changed must remain a refreshed draft.
 await db.exec('reset role');const second='40000000-0000-0000-0000-000000000002';
 await db.query("insert into public.worker_payroll_settings(company_id,worker_id,pay_type,monthly_salary_yen) values($1,$2,'monthly',100000) on conflict(worker_id,company_id) do update set pay_type='monthly',monthly_salary_yen=100000",[cid,second]);
 let secondPs=(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 order by period_start desc limit 1',[cid,second])).rows[0];
 await db.exec('alter table public.worker_payroll_settings disable trigger settings_refresh_payroll');
 await db.query('update public.worker_payroll_settings set monthly_salary_yen=110000 where worker_id=$1',[second]);
 await db.exec('alter table public.worker_payroll_settings enable trigger settings_refresh_payroll');
 await actor(editor);const refreshed=(await db.query('select public.finalize_payroll_statement($1,$2,true) as value',[secondPs.id,secondPs.revision])).rows[0].value;
 assert.equal(refreshed.finalized,false);assert.equal(refreshed.reason,'recalculation_changed');assert.ok(refreshed.revision>secondPs.revision);
 await db.exec('reset role');secondPs=(await db.query('select * from public.payroll_statements where id=$1',[secondPs.id])).rows[0];assert.equal(secondPs.workflow_state,'draft');assert.equal(secondPs.gross_pay,110000);assert.equal(secondPs.revision,refreshed.revision);
 // Real adjustments moving between two months invalidate both drafts, in order.
 const future=(await db.query("select ($1::date+interval '1 month')::date::text as month",[secondPs.period_start])).rows[0].month;
 await db.query("insert into public.payroll_statements(company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,detail,workflow_state,automatic_calculation,revision) values($1,$2,$3,($3::date+interval '1 month - 1 day')::date,0,0,0,'{}','draft',true,1)",[cid,second,future]);
 await actor(owner);const movedId=(await db.query('select public.create_payroll_adjustment($1,$2,1000,$3,null) as id',[second,'90000000-0000-0000-0000-000000000001',secondPs.period_start])).rows[0].id;
 await db.exec('reset role');const beforeMove=(await db.query('select period_start::text,revision from public.payroll_statements where worker_id=$1 order by period_start',[second])).rows;
 await actor(owner);await db.query('select public.update_payroll_adjustment($1,$2,1000,$3,null)',[movedId,'90000000-0000-0000-0000-000000000001',future]);
 await db.exec('reset role');const afterMove=(await db.query('select period_start::text,revision from public.payroll_statements where worker_id=$1 order by period_start',[second])).rows;assert.equal(afterMove[0].revision,beforeMove[0].revision+1);assert.equal(afterMove[1].revision,beforeMove[1].revision+1);
 await db.query('update public.payroll_statements set automatic_calculation=false where id=$1',[secondPs.id]);const manual=(await db.query('select * from public.payroll_statements where id=$1',[secondPs.id])).rows[0];
 await actor(owner);await db.query('select public.create_payroll_adjustment($1,$2,2000,$3,null)',[second,'90000000-0000-0000-0000-000000000001',secondPs.period_start]);
 await db.exec('reset role');assert.deepEqual((await db.query('select * from public.payroll_statements where id=$1',[secondPs.id])).rows[0],manual,'manual base must not be revision-mutated');
 await actor(editor);await assert.rejects(db.query('select public.finalize_payroll_statement($1,$2,true)',[secondPs.id,manual.revision]),/only automatic draft/);
 console.log('PASS exact snapshot: source guards, permissions, reviews, revision/no-op, refresh, atomic audit rollback, immutable saved amounts/metadata, self-only bank, no legacy backfill');



}catch(error){console.error(error.message,error.detail||'',error.where||'',error.position||'');process.exitCode=1;}finally{await db.close();}
