-- READ ONLY global fingerprints. No row values or Auth rows exported.
-- Any unrelated activity also refuses an unused restore, never reverts it.
begin read only;
set local statement_timeout='15s';
set local lock_timeout='2s';
with fingerprints as (
select 'company_checkout_allowance_private.receipts'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from company_checkout_allowance_private.receipts t) row_hashes
union all
select 'public.daily_reports'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.daily_reports t) row_hashes
union all
select 'public.daily_report_workers'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.daily_report_workers t) row_hashes
union all
select 'public.daily_report_edit_requests'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.daily_report_edit_requests t) row_hashes
union all
select 'public.attendance_verifications'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.attendance_verifications t) row_hashes
union all
select 'public.attendance_entries'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.attendance_entries t) row_hashes
union all
select 'public.payroll_statements'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.payroll_statements t) row_hashes
union all
select 'public.worker_payroll_settings'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.worker_payroll_settings t) row_hashes
union all
select 'public.company_members'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.company_members t) row_hashes
union all
select 'public.gps_auto_attendance_schedules'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.gps_auto_attendance_schedules t) row_hashes
union all
select 'public.work_attendance_selections'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.work_attendance_selections t) row_hashes
union all
select 'public.work_vehicle_route_selections'::text relation,count(*) row_count,md5(coalesce(string_agg(row_sha,'' order by row_sha),'')) row_hasheset_md5 from (select md5(to_jsonb(t)::text) row_sha from public.work_vehicle_route_selections t) row_hashes
)
select jsonb_build_object('phase','global_unused_restore_baseline','application_data_mutations',false,
 'relation_fingerprints',(select jsonb_agg(to_jsonb(f) order by relation) from fingerprints f),
 'default_acls',(select coalesce(jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'schema',n.nspname,'object_type',d.defaclobjtype,'acl',d.defaclacl::text) order by d.defaclobjtype,d.defaclnamespace),'[]')
 from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace
 where d.defaclrole=(select oid from pg_roles where rolname='postgres') and d.defaclobjtype in('f','r','S'))
) as result;
commit;
