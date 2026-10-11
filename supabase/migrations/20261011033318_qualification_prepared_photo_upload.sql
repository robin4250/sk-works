-- Prepared personal qualification drafts only; existing pilot and other buckets stay constrained.
begin;
create function private.qualification_photo_draft_upload_allowed(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed()
 and exists(select 1 from private.qualification_submissions r
 join public.workers w on w.id=r.worker_id and w.company_id=r.company_id
 join public.worker_qualifications q on q.id=r.target_id and q.worker_id=r.worker_id
  and q.company_id=r.company_id and q.qualification_master_id=r.qualification_master_id
 where r.photo_contract_version=1 and r.status='draft' and not r.photo_cancelled
 and r.requested_by=auth.uid() and w.user_id=auth.uid() and w.status::text='active'
 and exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid())
 and p_path=any(r.photo_upload_paths)
 and left(p_path,length(r.company_id::text||'/'||r.worker_id::text||'/'||r.target_id::text||'/submissions/'))
  =r.company_id::text||'/'||r.worker_id::text||'/'||r.target_id::text||'/submissions/');
$$;
revoke all on function private.qualification_photo_draft_upload_allowed(text) from public,anon;
grant execute on function private.qualification_photo_draft_upload_allowed(text) to authenticated;

do $$ declare p record; expression text; base text; expected_worker text;begin
 base:='((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)))';
 expected_worker:=left(base,length(base)-1)||' OR ((bucket_id = ''worker-documents''::text) AND private.worker_document_photo_upload_allowed(name)))';

 select * into p from pg_policy where polrelid='storage.objects'::regclass and polname='license_document_pilot_insert_scope';
 if not found or p.polpermissive or p.polcmd<>'a' or p.polroles<>array['authenticated'::regrole::oid] then
  raise exception 'Unexpected license pilot gate; review before qualification upload rollout' using errcode='55000';
 end if;
 expression:=pg_get_expr(p.polwithcheck,p.polrelid);
 if expression not in (base,expected_worker) then
  raise exception 'License gate changed; review before qualification upload rollout' using errcode='55000';
 end if;
 if not exists(select 1 from pg_policy where polrelid='storage.objects'::regclass
  and polname='initial_beta_official_documents_insert_pause' and not polpermissive and polcmd='a'
  and polroles=array[0::oid] and pg_get_expr(polwithcheck,polrelid)=
  '((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR (CURRENT_USER = ''authenticated''::name))') then
  raise exception 'Official document pause gate changed; review before rollout' using errcode='55000';
 end if;
 execute 'alter policy license_document_pilot_insert_scope on storage.objects with check (('||expression||') or (bucket_id=''qualification-certificates'' and private.qualification_photo_draft_upload_allowed(name)))';
end $$;

create function private.qualification_photo_upload_capability()
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed()
 and exists(select 1 from public.workers w where w.user_id=auth.uid() and w.status::text='active'
  and exists(select 1 from public.company_members m where m.company_id=w.company_id and m.user_id=auth.uid()))
 and exists(select 1 from pg_policy p where p.polrelid='storage.objects'::regclass
  and not p.polpermissive and p.polname='license_document_pilot_insert_scope' and p.polcmd='a' and p.polroles=array['authenticated'::regrole::oid] and pg_get_expr(p.polwithcheck,p.polrelid) in ('((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)) OR ((bucket_id = ''qualification-certificates''::text) AND private.qualification_photo_draft_upload_allowed(name)))','((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)) OR ((bucket_id = ''worker-documents''::text) AND private.worker_document_photo_upload_allowed(name)) OR ((bucket_id = ''qualification-certificates''::text) AND private.qualification_photo_draft_upload_allowed(name)))','((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)) OR ((bucket_id = ''qualification-certificates''::text) AND private.qualification_photo_draft_upload_allowed(name)) OR ((bucket_id = ''worker-documents''::text) AND private.worker_document_photo_upload_allowed(name)))'))
 and not exists(select 1 from pg_policy p where p.polrelid='storage.objects'::regclass
  and not p.polpermissive and p.polcmd in ('a','*')
  and (0::oid=any(p.polroles) or 'authenticated'::regrole::oid=any(p.polroles))
  and not (
   (p.polname='license_document_pilot_insert_scope' and p.polcmd='a' and p.polroles=array['authenticated'::regrole::oid] and pg_get_expr(p.polwithcheck,p.polrelid) in ('((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)) OR ((bucket_id = ''qualification-certificates''::text) AND private.qualification_photo_draft_upload_allowed(name)))','((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)) OR ((bucket_id = ''worker-documents''::text) AND private.worker_document_photo_upload_allowed(name)) OR ((bucket_id = ''qualification-certificates''::text) AND private.qualification_photo_draft_upload_allowed(name)))','((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR ((bucket_id = ''worker-documents''::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)) OR ((bucket_id = ''qualification-certificates''::text) AND private.qualification_photo_draft_upload_allowed(name)) OR ((bucket_id = ''worker-documents''::text) AND private.worker_document_photo_upload_allowed(name)))'))
   or (p.polname='initial_beta_official_documents_insert_pause' and p.polcmd='a' and p.polroles=array[0::oid] and pg_get_expr(p.polwithcheck,p.polrelid)='((bucket_id <> ALL (ARRAY[''worker-documents''::text, ''qualification-certificates''::text, ''employee-onboarding-documents''::text])) OR (CURRENT_USER = ''authenticated''::name))')
   or (p.polroles=array['authenticated'::regrole::oid] and (
    (p.polname='account_deletion_access_guard' and p.polcmd='*' and pg_get_expr(p.polwithcheck,p.polrelid)='( SELECT private.account_access_allowed() AS account_access_allowed)')
    or (p.polname='income_tax_pdf_insert_guard' and p.polcmd='a' and pg_get_expr(p.polwithcheck,p.polrelid)='((bucket_id <> ''company-income-tax-tables''::text) OR (income_tax_private.pdf_object_access(name) AND storage.allow_any_operation(ARRAY[''object.upload''::text])))')
    or (p.polname='review no media replacement insert' and p.polcmd='a' and pg_get_expr(p.polwithcheck,p.polrelid)='((NOT private.company_content_review_enabled(private.try_uuid(split_part(name, ''/''::text, 1)))) OR (bucket_id <> ALL (ARRAY[''chat-attachments''::text, ''communication-notes''::text, ''communication-albums''::text])) OR private.content_file_unreferenced(bucket_id, name))')
   ))
  ));
$$;
revoke all on function private.qualification_photo_upload_capability() from public,anon,authenticated;

-- Patch only the conservative capability block, preserving every submission/approval action.
do $guard$ declare body text;begin
 select prosrc into body from pg_proc where oid='private.personal_qualification_photo_submission(text,jsonb)'::regprocedure;
 if md5(body)<>'7c79fa3388e9cba9408f8f5f3f097bd4' then raise exception 'Qualification submission body changed; review before rollout' using errcode='55000';end if;
 if position($old$ select not exists(select 1 from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid=p.polrelid
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='storage' and c.relname='objects' and p.polcmd in ('a','*') and not p.polpermissive)
  into upload_allowed;$old$ in body)=0 then raise exception 'Qualification capability anchor missing';end if;
 body:=replace(body,$old$ select not exists(select 1 from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid=p.polrelid
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='storage' and c.relname='objects' and p.polcmd in ('a','*') and not p.polpermissive)
  into upload_allowed;$old$,$new$ select private.qualification_photo_upload_capability() into upload_allowed;$new$);
 execute 'create or replace function private.personal_qualification_photo_submission(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='''' as '||quote_literal(body);
end $guard$;
commit;
