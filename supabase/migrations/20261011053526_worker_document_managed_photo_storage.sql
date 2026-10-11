begin;
-- Restore only document registration roles; no existing row or object rewrite.
set local lock_timeout='5s';
do $guard$
declare f record; p record;
begin
 select prosrc,prosecdef,provolatile,proconfig,proacl,proowner into f
 from pg_proc where oid=to_regprocedure('private.worker_document_photo_upload_allowed(text)');
 if not found or md5(f.prosrc) is distinct from '22b1693340ab78d0c33eccef652cc221'
  or f.prosecdef or f.provolatile<>'s' or f.proconfig is distinct from array['search_path=""']
  or not has_function_privilege('authenticated','private.worker_document_photo_upload_allowed(text)','EXECUTE')
  or has_function_privilege('anon','private.worker_document_photo_upload_allowed(text)','EXECUTE')
  or exists(select 1 from aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE') then
  raise exception 'Worker document upload helper changed; inspect before deployment' using errcode='55000';
 end if;
 select polcmd,polpermissive,polroles,pg_get_expr(polwithcheck,polrelid) expr into p
 from pg_policy where polrelid='storage.objects'::regclass and polname='license_document_pilot_insert_scope';
 if not found or p.polcmd<>'a' or p.polpermissive or p.polroles<>array['authenticated'::regrole::oid]
  or md5(p.expr) is distinct from '3075293e12c46887297c60263b6b1fa7' then
  raise exception 'Worker document restrictive upload scope changed' using errcode='55000';
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='worker_document_statuses' and column_name='attachment_paths' and udt_name='_text') then
  raise exception 'Worker document multi-photo schema is required' using errcode='55000';
 end if;
end $guard$;

create or replace function private.worker_document_photo_upload_allowed(p_path text)
returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed()
 and cardinality(string_to_array(p_path,'/'))=5
 and split_part(p_path,'/',5) ~ '^[a-zA-Z0-9_-]+[.](jpg|jpeg|png|pdf|heic|heif)$'
 and exists(select 1 from public.workers w
  join public.document_requirements r on r.company_id=w.company_id
  where w.company_id=private.try_uuid(split_part(p_path,'/',1))
   and w.id=private.try_uuid(split_part(p_path,'/',2))
   and r.id=private.try_uuid(split_part(p_path,'/',3))
   and w.status::text='active' and r.is_active
   and exists(select 1 from public.company_members m where m.company_id=w.company_id and m.user_id=auth.uid())
   and (w.user_id=auth.uid() or private.has_company_feature(w.company_id,'can_manage_people')
    or exists(select 1 from public.company_members managed where managed.company_id=w.company_id
     and managed.user_id=auth.uid() and managed.role::text in ('owner','admin','manager')))
   and (split_part(p_path,'/',4)='own-upload' or exists(select 1 from public.worker_document_statuses s
    where s.id=private.try_uuid(split_part(p_path,'/',4)) and s.company_id=w.company_id
     and s.worker_id=w.id and s.requirement_id=r.id)));
$$;

-- CREATE OR REPLACE preserves the helper's authenticated-only execute ACL.
create policy worker_document_photo_managed_insert on storage.objects
for insert to authenticated with check(bucket_id='worker-documents'
 and private.worker_document_photo_upload_allowed(name)
 and exists(select 1 from public.company_members m
  where m.company_id=private.try_uuid(split_part(storage.objects.name,'/',1))
   and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager')));

-- New read access is tied to the currently saved document paths, never arbitrary
-- uploaded objects or historical snapshots. Existing self/feature read remains.
create policy worker_document_photo_managed_read on storage.objects
for select to authenticated using(bucket_id='worker-documents'
 and auth.uid() is not null and private.account_access_allowed()
 and cardinality(string_to_array(name,'/'))=5
 and split_part(name,'/',5) ~ '^[a-zA-Z0-9_-]+[.](jpg|jpeg|png|pdf|heic|heif)$'
 and exists(select 1 from public.company_members m
  where m.company_id=private.try_uuid(split_part(storage.objects.name,'/',1))
   and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager'))
 and exists(select 1 from public.worker_document_statuses s
  join public.workers w on w.id=s.worker_id and w.company_id=s.company_id
  join public.document_requirements r on r.id=s.requirement_id and r.company_id=s.company_id
  where s.company_id=private.try_uuid(split_part(storage.objects.name,'/',1))
   and s.worker_id=private.try_uuid(split_part(storage.objects.name,'/',2))
   and s.requirement_id=private.try_uuid(split_part(storage.objects.name,'/',3))
   and (s.attachment_path=storage.objects.name or storage.objects.name=any(s.attachment_paths))));
-- Existing restrictive account/pilot/retention policies and every UPDATE/DELETE
-- permission, business-table RLS/ACL, pilot row, audit history remain unchanged.
commit;
