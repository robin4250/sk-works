begin;
-- Optional route contacts: no old data rewrite, new RPC, privilege or RLS change.
set local lock_timeout='5s';
do $guard$
declare t record;
begin
 if to_regclass('public.route_assignments') is null then
  raise exception 'Route assignment baseline is required' using errcode='55000';
 end if;
 if not (select relrowsecurity from pg_class where oid='public.route_assignments'::regclass)
  or not has_table_privilege('authenticated','public.route_assignments','SELECT')
  or not has_table_privilege('authenticated','public.route_assignments','INSERT')
  or not has_table_privilege('authenticated','public.route_assignments','UPDATE')
  or has_table_privilege('anon','public.route_assignments','SELECT') then
  raise exception 'Route assignment access baseline changed' using errcode='55000';
 end if;
 if exists(select 1 from pg_attribute where attrelid='public.route_assignments'::regclass
  and attname in ('responsible_name','responsible_phone') and not attisdropped) then
  raise exception 'Route responsibility columns already exist; inspect before deployment' using errcode='55000';
 end if;
 select tr.tgenabled,tr.tgtype,tr.tgattr,fn.prosrc,fn.prosecdef,fn.proconfig into t
 from pg_trigger tr join pg_proc fn on fn.oid=tr.tgfoid
 where tr.tgrelid='public.route_assignments'::regclass and tr.tgname='zz_master_optional_write_guard'
  and tr.tgfoid=to_regprocedure('private.guard_master_optional_feature_write()');
 if not found or t.tgenabled<>'O' or t.tgtype<>23 or t.tgattr::text<>''
  or md5(t.prosrc) is distinct from '427d9bd98e3e540ca51a36025f027b65'
  or not t.prosecdef or t.proconfig is distinct from array['search_path=""'] then
  raise exception 'Route Master OFF write guard changed' using errcode='55000';
 end if;
end $guard$;
alter table public.route_assignments
 add column responsible_name text constraint route_assignments_responsible_name_length
  check(responsible_name is null or char_length(responsible_name)<=120),
 add column responsible_phone text constraint route_assignments_responsible_phone_length
  check(responsible_phone is null or char_length(responsible_phone)<=40);
-- Existing table-level SELECT/INSERT/UPDATE privileges cover both nullable fields.
-- Absent fields in old INSERT/UPDATE calls remain compatible. Existing saved
-- routes receive NULL contact fields; no old names, stops or attendance change.
commit;
