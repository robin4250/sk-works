begin;
-- Enable this feature's new private worker-document photos without opening
-- qualification/onboarding buckets or changing the existing pilot settings.
set local lock_timeout='5s';
do $guard$
declare p record; base text; expected_qualified text;
begin
 if not exists(select 1 from information_schema.columns where table_schema='public'
   and table_name='worker_document_statuses' and column_name='attachment_paths' and udt_name='_text')
 or not exists(select 1 from information_schema.columns where table_schema='public'
   and table_name='worker_document_status_history' and column_name='attachment_paths' and udt_name='_text') then
  raise exception 'Worker document multi-photo schema is required' using errcode='55000';
 end if;
 base:='((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)))';
 expected_qualified:=left(base,length(base)-1)||' OR ((bucket_id = ''qualification-certificates''::text) AND private.qualification_photo_draft_upload_allowed(name)))';
 select polcmd,polpermissive,polroles,pg_get_expr(polwithcheck,polrelid) expr into p
 from pg_policy where polrelid='storage.objects'::regclass and polname='license_document_pilot_insert_scope';
 if not found or p.polcmd<>'a' or p.polpermissive or p.polroles<>array['authenticated'::regrole::oid]
   or p.expr not in (base,expected_qualified) then
  raise exception 'Worker photo upload scope changed; inspect before deployment' using errcode='55000';
 end if;
 if to_regprocedure('private.account_access_allowed()') is null
   or to_regprocedure('private.has_company_feature(uuid,text)') is null then
  raise exception 'Existing worker account/feature contracts are required' using errcode='55000';
 end if;
end $guard$;

-- Invoker: every referenced row remains subject to its existing table ACL/RLS.
create function private.worker_document_photo_upload_allowed(p_path text)
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
   and (w.user_id=auth.uid() or private.has_company_feature(w.company_id,'can_manage_people'))
   and (split_part(p_path,'/',4)='own-upload' or exists(select 1 from public.worker_document_statuses s
    where s.id=private.try_uuid(split_part(p_path,'/',4)) and s.company_id=w.company_id
     and s.worker_id=w.id and s.requirement_id=r.id)));
$$;
revoke all on function private.worker_document_photo_upload_allowed(text) from public,anon;
grant execute on function private.worker_document_photo_upload_allowed(text) to authenticated;

-- Keep any already deployed, exactly scoped qualification branch intact.
do $scope$
declare original text;
begin
 select pg_get_expr(polwithcheck,polrelid) into original from pg_policy
 where polrelid='storage.objects'::regclass and polname='license_document_pilot_insert_scope';
 execute format('alter policy license_document_pilot_insert_scope on storage.objects with check((%s) or (bucket_id=%L and private.worker_document_photo_upload_allowed(name)))',original,'worker-documents');
end $scope$;
create policy worker_document_photo_self_insert on storage.objects
for insert to authenticated with check(bucket_id='worker-documents'
 and private.worker_document_photo_upload_allowed(name)
 and exists(select 1 from public.workers w where w.id=private.try_uuid(split_part(storage.objects.name,'/',2))
  and w.company_id=private.try_uuid(split_part(storage.objects.name,'/',1)) and w.user_id=auth.uid()));
-- No old object/record writes, table grants, read policy, UPDATE/DELETE policy,
-- pilot rows or original pilot helper changes. Retention/account guards remain.

commit;
