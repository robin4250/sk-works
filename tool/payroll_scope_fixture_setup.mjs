// Exact existing payroll + snapshot SQL; disposable prerequisites only.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const read=p=>fs.readFileSync(p,'utf8');
export async function setupPayrollScopeFixture(db){
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',editor='00000000-0000-0000-0000-000000000002';
async function actor(id,role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec(`set role ${role}`);}
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
await db.exec('reset role');
await db.exec(read('supabase/tests/payroll_refresh_scope_access_fixture.sql'));
await db.exec(read('supabase/tests/payroll_refresh_scope_live_source_fixture.sql'));
await db.exec('create trigger report_refresh_payroll after update on public.daily_reports for each row execute function private.report_refresh_payroll()');
await db.exec(`create trigger clear_daily_report_signatures_on_draft before update on public.daily_reports for each row execute function private.clear_daily_report_signatures_on_draft();
create trigger clear_daily_report_signatures_on_workers after insert or update or delete on public.daily_report_workers for each row execute function private.clear_daily_report_signatures_on_workers();
create trigger daily_report_shift_identity_guard before update of company_id,report_date,site_id,route_assignment_id on public.daily_reports for each row execute function private.guard_daily_report_shift_identity();
create trigger reject_direct_attendance_delete before delete on public.attendance_entries for each row execute function private.reject_direct_attendance_delete();
create trigger reject_direct_report_worker_delete before delete on public.daily_report_workers for each row execute function private.reject_direct_attendance_delete();
create trigger reject_direct_report_delete before delete on public.daily_reports for each row execute function private.reject_direct_attendance_delete();`);

}
