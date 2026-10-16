// Disposable synthetic fixture only: managed leave/work transitions with all attendance gates OFF.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {validatePaidLeaveFixtureUrl} from './paid_leave_pg17_database_guard.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const cid='10000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000001';
let db;
if(process.argv[3]==='--pg17') {
 const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href);
 const Client=mod.Client??mod.default?.Client;
 db=new Client({connectionString:validatePaidLeaveFixtureUrl(process.env.SKO_PAID_LEAVE_FIXTURE_URL)});
 await db.connect(); db.exec=q=>db.query(q); db.close=()=>db.end();
 assert.equal((Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000)|0,17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth') and c.relkind in ('r','v','m')")).rows[0].n,0,'Only empty disposable fixture accepted');
} else {
 const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();
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
 await db.exec(`alter table public.companies add column if not exists name text,
 add column company_seal_enabled boolean default true,add column updated_at timestamptz;
 update public.companies set name='株式会社テスト建設';
 create table public.payment_certificates(id uuid primary key,company_id uuid,snapshot jsonb);
 create function private.refresh_automatic_invoice(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.invoices; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.refresh_automatic_payment_certificate(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.payment_certificates; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.payroll_document_metadata(p_statement_id uuid) returns jsonb language sql as $$
 select jsonb_build_object('company_seal_enabled',c.company_seal_enabled,'synthetic_metadata_stub',true)
 from public.payroll_statements ps join public.companies c on c.id=ps.company_id where ps.id=p_statement_id $$;
 create function private.saved_site_payment_document(p_proposal uuid,p_company uuid) returns jsonb language plpgsql as $$
 declare result jsonb;
 begin select jsonb_build_object('snapshot_version',2,'parent_company_seal_enabled',parent.company_seal_enabled)
 into result from public.companies parent where parent.id=p_company; return result; end $$;`);
 await db.exec(read('supabase/migrations/20261009011357_company_seal_aoyagi_style.sql'));
 await db.exec(read('supabase/migrations/20261009012730_company_seal_document_snapshots.sql'));

 await db.exec(read('tool/fixtures/paid_leave_pg17/rollout_seed.sql'));
 await db.exec(`create function public.current_feature_permissions() returns jsonb language sql as $$select '{"can_manage_attendance":true}'::jsonb$$;
 alter table public.attendance_entries add column allowance_amount integer default 0,add column notes text,add column created_by uuid,add column updated_by uuid,add column source_report_id uuid;
 alter table public.paid_leave_requests add column batch_id uuid,add column requested_by uuid,add column reason text,add column reviewed_by uuid,add column reviewed_at timestamptz,add column review_note text,add column updated_at timestamptz;
 create table public.sites(id uuid primary key,company_id uuid,name text,latitude double precision,longitude double precision);
 create table public.daily_reports(id uuid primary key default gen_random_uuid(),company_id uuid,site_id uuid,report_date date,work_description text,status text,created_by uuid,updated_by uuid,updated_at timestamptz,signer_name text,signature_json jsonb,signed_at timestamptz,representative_signature_json jsonb,representative_signer_name text,supervisor_signature_json jsonb,supervisor_signer_name text,route_assignment_id uuid);
 create table public.daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,allowance_label text,work_category text,vehicle_id uuid,route_assignment_id uuid,odometer_km numeric,unique(report_id,worker_id));
 create table public.vehicles(id uuid primary key,company_id uuid,is_active boolean,odometer_km numeric default 1000,display_name text,registration_number text,updated_by uuid,updated_at timestamptz);
 create table public.attendance_verifications(id uuid primary key default gen_random_uuid(),company_id uuid,worker_id uuid,site_id uuid,event_type text,verification_mode text,confirmed_at timestamptz,proximity_status text,note text,created_by uuid,daily_report_id uuid,vehicle_id uuid references public.vehicles(id) on delete set null,route_assignment_id uuid,photo_storage_path text,latitude double precision,longitude double precision,accuracy_m double precision,distance_to_site_m double precision);
 alter table public.attendance_verifications enable row level security;
 create policy "worker or attendance manager can create verification" on public.attendance_verifications for insert to authenticated with check(true);
 create policy fixture_read on public.attendance_verifications for select to authenticated using(private.has_company_feature(company_id,'can_manage_attendance'));
 create table public.work_vehicle_route_selections(company_id uuid,worker_id uuid,work_date date,vehicle_id uuid);
 create table public.route_assignments(id uuid,company_id uuid,route_name text,is_active boolean default true);
 create table public.route_stops(id uuid,route_assignment_id uuid,latitude double precision,longitude double precision,source_label text,address text);
 create table public.gps_auto_attendance_schedules(company_id uuid,worker_id uuid,enabled boolean,site_id uuid,route_assignment_id uuid,timezone text,weekdays smallint[],local_time time,last_attempt_date date,last_result text,updated_at timestamptz,radius_m double precision);
 create table public.work_attendance_selections(company_id uuid,worker_id uuid,work_date date,verification_mode text,site_id uuid,route_assignment_id uuid,updated_by uuid,updated_at timestamptz,unique(company_id,worker_id,work_date));
 create table public.attendance_correction_items(attendance_entry_id uuid);
 create table public.daily_report_edit_requests(id uuid,report_id uuid,requested_by uuid,status text,created_at timestamptz,resolved_at timestamptz);
 drop table public.app_notifications;
 drop function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid);
 insert into public.sites values('70000000-0000-0000-0000-000000000001','${cid}','Synthetic site',null,null);`);
 await db.exec(read('tool/fixtures/source_member_notifications/20260919213000_add_app_notifications.sql'));
 await db.exec(read('tool/fixtures/source_member_notifications/20260920214500_restrict_notification_table_grants.sql'));
 const before=(await db.query('select to_jsonb(p) row from payroll_statements p order by id')).rows;
 for(const name of ['20261008042058_fix_managed_attendance_overnight_chronology.sql','20261008124940_gps_shift_work_date_evidence.sql','20261008153425_vehicle_active_driver_claims.sql','20261008154241_group_proxy_checkout_staged.sql','20261008154433_vehicle_meter_snapshots.sql','20261008160834_attendance_rollout_capabilities.sql','20261008161708_group_report_source_attachment.sql','20261008162618_attach_vehicle_meter_to_report.sql','20261008171216_source_member_notifications.sql']) {
  if(name==='20261008154433_vehicle_meter_snapshots.sql') await db.exec(read('supabase/migrations/20261001232457_add_daily_report_vehicle_usage_rpc.sql'));
  await db.exec(read('supabase/migrations/'+name));
 }
 assert.deepEqual((await db.query('select to_jsonb(p) row from payroll_statements p order by id')).rows,before,'OFF union DDL changed financial rows');
 await db.exec(read('supabase/tests/attendance_paid_leave_seal_off_assertions.sql'));
 console.log('PASS actual managed paid-leave/work transitions with OFF union, paid-leave money, seal identity and protected statements');
} catch(e) {console.error(e.code,e.message,e.where??'');process.exitCode=1;} finally {await db.close();}
