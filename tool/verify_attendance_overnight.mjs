import fs from 'node:fs';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
try {
  await db.exec(`
    create schema auth; create schema private;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
    create function public.current_feature_permissions() returns jsonb language sql as $$ select '{"can_manage_attendance":true}'::jsonb $$;
    create table company_members(company_id uuid,user_id uuid,role text);
    create table workers(id uuid,company_id uuid,status text);
    create table sites(id uuid,company_id uuid);
    create table daily_reports(id uuid primary key default gen_random_uuid(),company_id uuid,site_id uuid,report_date date,work_description text,status text,created_by uuid,updated_by uuid,updated_at timestamptz,signer_name text,signature_json jsonb,signed_at timestamptz,representative_signature_json jsonb,representative_signer_name text,supervisor_signature_json jsonb,supervisor_signer_name text);
    create table daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,allowance_label text,work_category text,unique(report_id,worker_id));
    create table attendance_entries(id uuid default gen_random_uuid(),company_id uuid,work_date date,worker_id uuid,site_id uuid,base_man_days numeric,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,allowance_names text[],notes text,created_by uuid,updated_by uuid,work_category text,source_report_id uuid);
    create table attendance_verifications(company_id uuid,worker_id uuid,site_id uuid,event_type text,verification_mode text,confirmed_at timestamptz,proximity_status text,note text,created_by uuid,daily_report_id uuid);
    create table attendance_correction_items(attendance_entry_id uuid);
    create table paid_leave_requests(batch_id uuid,company_id uuid,worker_id uuid,requested_by uuid,leave_date date,reason text,status text,reviewed_by uuid,reviewed_at timestamptz,review_note text,updated_at timestamptz);
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261008042058_fix_managed_attendance_overnight_chronology.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/tests/attendance_overnight_chronology_assertions.sql','utf8'));
  console.log('PASS actual force_manage_attendance RPC: chronology, links, repeat/delete, neighboring shift, auth/company guards');
} catch (error) { console.error(error.message, error.where ?? ''); process.exitCode = 1; } finally { await db.close(); }
