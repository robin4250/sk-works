-- Source preparation only. Empty/default-OFF; no production target IDs or backfill.
-- A trusted operator must separately verify each driving-license requirement.
set local lock_timeout = '5s';

do $$
declare v_policy record; v_expected record; v_auth oid;
begin
 select oid into v_auth from pg_roles where rolname='authenticated';
 if v_auth is null then raise exception 'Authenticated role missing'; end if;
 select p.* into v_policy from pg_policy p
 where p.polrelid='storage.objects'::regclass
 and p.polname='initial_beta_official_documents_insert_pause';
 if not found or v_policy.polpermissive or v_policy.polcmd<>'a'
 or v_policy.polroles<>array[0::oid]
 or regexp_replace(pg_get_expr(v_policy.polwithcheck,v_policy.polrelid),'\s','','g')
 <> '(bucket_id<>ALL(ARRAY[''worker-documents''::text,''qualification-certificates''::text,''employee-onboarding-documents''::text]))' then
  raise exception 'Unexpected official upload pause; review instead of replacing';
 end if;
 if to_regprocedure('private.account_access_allowed()') is null
 or to_regprocedure('private.has_company_feature(uuid,text)') is null
 or to_regprocedure('private.try_uuid(text)') is null
 or to_regprocedure('private.official_document_path_is_retained(text,text)') is null then
  raise exception 'Required scoped access or storage hold helper missing';
 end if;
 if not exists(select 1 from pg_policy where polrelid='storage.objects'::regclass
  and polname='account_deletion_access_guard' and not polpermissive and polcmd='*')
 or not exists(select 1 from pg_policy where polrelid='storage.objects'::regclass
  and polname='official_document_history_no_delete' and not polpermissive and polcmd='d')
 or not exists(select 1 from pg_policy where polrelid='storage.objects'::regclass
  and polname='official_document_history_no_overwrite' and not polpermissive and polcmd='w')
 or not exists(select 1 from pg_policy where polrelid='storage.objects'::regclass
  and polname='initial_beta_official_documents_update_pause' and not polpermissive and polcmd='w') then
  raise exception 'Required existing storage guards missing';
 end if;
 for v_expected in select * from (values
  ('account_deletion_access_guard','*',array[v_auth],
   '(selectprivate.account_access_allowed()asaccount_access_allowed)',
   '(selectprivate.account_access_allowed()asaccount_access_allowed)'),
  ('official_document_history_no_delete','d',array[v_auth],
   '(notprivate.official_document_path_is_retained(bucket_id,name))',null::text),
  ('official_document_history_no_overwrite','w',array[v_auth],
   '(notprivate.official_document_path_is_retained(bucket_id,name))',
   '(notprivate.official_document_path_is_retained(bucket_id,name))'),
  ('initial_beta_official_documents_update_pause','w',array[0::oid],
   '(bucket_id<>all(array[''worker-documents''::text,''qualification-certificates''::text,''employee-onboarding-documents''::text]))',
   '(bucket_id<>all(array[''worker-documents''::text,''qualification-certificates''::text,''employee-onboarding-documents''::text]))')
 ) e(name,command,roles,using_expr,check_expr) loop
  select p.* into v_policy from pg_policy p
   where p.polrelid='storage.objects'::regclass and p.polname=v_expected.name;
  if not found or v_policy.polpermissive or v_policy.polcmd::text<>v_expected.command
   or v_policy.polroles<>v_expected.roles
   or lower(regexp_replace(pg_get_expr(v_policy.polqual,v_policy.polrelid),'\s','','g'))
      is distinct from v_expected.using_expr
   or lower(regexp_replace(pg_get_expr(v_policy.polwithcheck,v_policy.polrelid),'\s','','g'))
      is distinct from v_expected.check_expr then
   raise exception 'Unexpected existing storage guard: %',v_expected.name;
  end if;
 end loop;
 if exists(select 1 from unnest(array['id','company_id','user_id','status']) c
  where not has_column_privilege('authenticated','public.workers',c,'select'))
 or exists(select 1 from unnest(array['company_members','document_requirements','worker_document_statuses']) t
  where not has_table_privilege('authenticated','public.'||t,'select')) then
  raise exception 'Existing scoped column/table read contract missing';
 end if;
end $$;

create table private.license_document_upload_pilots (
 company_id uuid not null,
 requirement_id uuid not null,
 requirement_name_snapshot text not null check(length(trim(requirement_name_snapshot))>0),
 enabled boolean not null default false,
 primary key(company_id,requirement_id)
);
-- No FK/cascade into registered records. Stale tuples cannot authorize a missing
-- worker, membership or requirement and require separate operator cleanup.
alter table private.license_document_upload_pilots enable row level security;
alter table private.license_document_upload_pilots force row level security;
revoke all on private.license_document_upload_pilots from public,anon,authenticated;
grant select(company_id,requirement_id,requirement_name_snapshot,enabled)
 on private.license_document_upload_pilots to authenticated;
create policy license_document_pilot_company_read
 on private.license_document_upload_pilots for select to authenticated
 using(private.account_access_allowed() and exists(
  select 1 from public.company_members cm
  where cm.company_id=license_document_upload_pilots.company_id and cm.user_id=auth.uid()));

create function private.license_document_upload_allowed(p_path text)
returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed()
 and cardinality(string_to_array(p_path,'/'))=5
 and split_part(p_path,'/',5) ~ '^[a-zA-Z0-9_-]+[.](jpg|jpeg|png|pdf|heic|heif)$'
 and exists(
  select 1 from public.workers w
  join public.document_requirements r on r.company_id=w.company_id
  join private.license_document_upload_pilots pilot
   on pilot.company_id=r.company_id and pilot.requirement_id=r.id
  where w.company_id=private.try_uuid(split_part(p_path,'/',1))
  and w.id=private.try_uuid(split_part(p_path,'/',2))
  and r.id=private.try_uuid(split_part(p_path,'/',3))
  and w.status::text='active' and r.is_active and pilot.enabled
  and r.name=pilot.requirement_name_snapshot
  and exists(select 1 from public.company_members cm
   where cm.company_id=w.company_id and cm.user_id=auth.uid())
  and (w.user_id=auth.uid() or private.has_company_feature(w.company_id,'can_manage_people'))
  and (split_part(p_path,'/',4)='own-upload' or exists(
   select 1 from public.worker_document_statuses s
   where s.id=private.try_uuid(split_part(p_path,'/',4))
   and s.company_id=w.company_id and s.worker_id=w.id and s.requirement_id=r.id))
 );
$$;
revoke all on function private.license_document_upload_allowed(text) from public,anon;
grant execute on function private.license_document_upload_allowed(text) to authenticated;

-- Keep anonymous/non-authenticated roles on the original three-bucket pause.
-- PUBLIC must not reference the authenticated-only helper: PostgreSQL checks
-- its EXECUTE ACL even when an OR branch would allow a nonofficial bucket.
-- Route the actual authenticated database role to a separate restrictive check
-- in this same transaction; do not trust a client-supplied JWT role claim.
alter policy initial_beta_official_documents_insert_pause on storage.objects
with check(bucket_id not in ('worker-documents','qualification-certificates','employee-onboarding-documents')
 or current_user='authenticated');
-- ANDed with every applicable permissive INSERT policy. Empty/OFF enables none.
create policy license_document_pilot_insert_scope on storage.objects
as restrictive for insert to authenticated
with check(bucket_id not in ('worker-documents','qualification-certificates','employee-onboarding-documents')
 or (bucket_id='worker-documents' and auth.uid() is not null
  and private.license_document_upload_allowed(name)));
create policy license_document_pilot_self_insert on storage.objects
for insert to authenticated with check(
 bucket_id='worker-documents' and private.license_document_upload_allowed(name)
 and exists(select 1 from public.workers w
  where w.id=private.try_uuid(split_part(storage.objects.name,'/',2))
  and w.company_id=private.try_uuid(split_part(storage.objects.name,'/',1))
  and w.user_id=auth.uid()));
-- No changes to object UPDATE/DELETE, holds, table/Auth permissions, submissions,
-- saved statuses/history, feature roles, account deletion or onboarding paths.
