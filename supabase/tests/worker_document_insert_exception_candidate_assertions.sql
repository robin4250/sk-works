-- DESIGN COMPARISON ONLY. Synthetic isolated DB only; not a production migration.
create schema auth;create schema private;create schema storage;
create role authenticated;create role anon;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
create function private.try_uuid(v text) returns uuid language plpgsql immutable as $$begin return v::uuid;exception when invalid_text_representation then return null;end$$;
create table public.company_members(company_id uuid,user_id uuid);
create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
create table public.document_requirements(id uuid primary key,company_id uuid,is_active boolean);
create table public.worker_document_statuses(id uuid primary key,company_id uuid,worker_id uuid,requirement_id uuid,attachment_path text);
create table private.feature_grants(company_id uuid,user_id uuid,feature text);
create table private.restricted_users(user_id uuid);
create table private.retained_objects(name text primary key);
create function private.has_company_feature(cid uuid,f text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.feature_grants g where g.company_id=cid and g.user_id=auth.uid() and g.feature=f)$$;
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from private.restricted_users r where r.user_id=auth.uid())$$;
-- This validates the entire 5-segment path against a pre-existing saved status.
create function private.fixture_worker_document_insert_match(p_name text) returns boolean language sql stable security invoker set search_path='' as $$
 select private.account_access_allowed() and cardinality(string_to_array(p_name,'/'))=5
 and split_part(p_name,'/',5) ~ '^[a-zA-Z0-9_-]+[.](jpg|jpeg|png|pdf)$'
 and exists(select 1 from public.worker_document_statuses s
 join public.workers w on w.id=s.worker_id and w.company_id=s.company_id
 join public.document_requirements r on r.id=s.requirement_id and r.company_id=s.company_id
 where s.company_id=private.try_uuid(split_part(p_name,'/',1))
 and s.worker_id=private.try_uuid(split_part(p_name,'/',2))
 and s.requirement_id=private.try_uuid(split_part(p_name,'/',3))
 and s.id=private.try_uuid(split_part(p_name,'/',4)) and r.is_active and w.status='active'
 and exists(select 1 from public.company_members cm where cm.company_id=s.company_id and cm.user_id=auth.uid())
 and (w.user_id=auth.uid() or private.has_company_feature(s.company_id,'can_manage_people')))$$;
-- Synthetic equivalents of existing scoped readable business rows; no candidate
-- helper is SECURITY DEFINER and no new production table grants are proposed.
grant select on public.company_members,public.workers,public.document_requirements,public.worker_document_statuses to authenticated;
alter table public.company_members enable row level security;
create policy fixture_member_read on public.company_members for select to authenticated using(user_id=auth.uid());
alter table public.workers enable row level security;
create policy fixture_worker_read on public.workers for select to authenticated using(user_id=auth.uid() or private.has_company_feature(company_id,'can_manage_people'));
alter table public.document_requirements enable row level security;
create policy fixture_requirement_read on public.document_requirements for select to authenticated using(exists(select 1 from public.company_members cm where cm.company_id=document_requirements.company_id and cm.user_id=auth.uid()));
alter table public.worker_document_statuses enable row level security;
create policy fixture_status_read on public.worker_document_statuses for select to authenticated using(private.has_company_feature(company_id,'can_manage_people') or exists(select 1 from public.workers w where w.id=worker_document_statuses.worker_id and w.company_id=worker_document_statuses.company_id and w.user_id=auth.uid()));
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,payload text,unique(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema storage,auth,private to authenticated,anon;
grant select,insert,update,delete on storage.objects to authenticated,anon;
-- Synthetic permissive gate deliberately broad: candidate must reject bad tuples
-- even when an existing permissive policy happens to allow an INSERT.
create policy fixture_authenticated_insert on storage.objects for insert to authenticated with check(true);
create policy fixture_authenticated_read on storage.objects for select to authenticated using(true);
create policy fixture_authenticated_update on storage.objects for update to authenticated using(true) with check(true);
create policy fixture_authenticated_delete on storage.objects for delete to authenticated using(true);
create policy initial_beta_official_documents_insert_pause on storage.objects as restrictive for insert to authenticated
 with check(bucket_id not in ('worker-documents','qualification-certificates','employee-onboarding-documents'));
create policy account_deletion_access_guard on storage.objects as restrictive for all to authenticated
 using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
-- Existing production guard signature is modeled, not a new candidate helper.
create function private.official_document_path_is_retained(p_bucket text,p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select p_bucket in ('worker-documents','qualification-certificates','employee-onboarding-documents') and exists(select 1 from private.retained_objects r where r.name=p_name)$$;
create policy official_document_history_no_overwrite on storage.objects as restrictive for update to authenticated
 using(not private.official_document_path_is_retained(bucket_id,name))
 with check(not private.official_document_path_is_retained(bucket_id,name));
create policy official_document_history_no_delete on storage.objects as restrictive for delete to authenticated
 using(not private.official_document_path_is_retained(bucket_id,name));
insert into company_members values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000004');
insert into workers values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','active'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','active');
insert into document_requirements values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',true),
 ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',false);
insert into worker_document_statuses values
 ('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',null),
 ('50000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001',null),
 ('50000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002',null),
 ('50000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000003',null);
insert into private.feature_grants values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','can_manage_people');
create table fixture_checks(label text primary key);
create function public.fixture_try_insert(p_label text,p_bucket text,p_path text,p_allowed boolean) returns void language plpgsql security invoker as $$
declare ok boolean:=true;msg text;begin
 begin insert into storage.objects(bucket_id,name,payload) values(p_bucket,p_path,'synthetic');
 exception when insufficient_privilege then ok:=false;get stacked diagnostics msg=message_text;end;
 if ok is distinct from p_allowed then raise exception 'Unexpected INSERT permission for %: % (%)',p_label,ok,msg;end if;
 insert into public.fixture_checks values(p_label);
end $$;
grant insert on fixture_checks to authenticated,anon;
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
set role authenticated;
select fixture_try_insert('baseline_self_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/baseline.jpg',false);
reset role;
-- Sole comparison change: INSERT restriction. UPDATE/DELETE policies stay intact.
create temp table original_holds as select polname,polcmd,pg_get_expr(polqual,polrelid) qual,pg_get_expr(polwithcheck,polrelid) chk
 from pg_policy where polrelid='storage.objects'::regclass and polcmd in ('w','d','*');
alter policy initial_beta_official_documents_insert_pause on storage.objects with check(
 bucket_id not in ('worker-documents','qualification-certificates','employee-onboarding-documents')
 or (bucket_id='worker-documents' and private.fixture_worker_document_insert_match(name)));
set role authenticated;
select fixture_try_insert('self_valid','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/self.jpg',true);
select fixture_try_insert('other_worker','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000002/other.jpg',false);
select fixture_try_insert('company_mismatch','worker-documents','10000000-0000-0000-0000-000000000002/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/company.jpg',false);
select fixture_try_insert('status_mismatch','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000002/status.jpg',false);
select fixture_try_insert('requirement_mismatch','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000002/50000000-0000-0000-0000-000000000001/req.jpg',false);
select fixture_try_insert('cross_company_requirement','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000002/50000000-0000-0000-0000-000000000003/cross.jpg',false);
select fixture_try_insert('inactive_requirement','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000003/50000000-0000-0000-0000-000000000004/inactive.jpg',false);
select fixture_try_insert('bad_uuid','worker-documents','not-a-uuid/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/bad.jpg',false);
select fixture_try_insert('extra_segment','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/sub/file.jpg',false);
select fixture_try_insert('empty_filename','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/',false);
select fixture_try_insert('qualification_stays_paused','qualification-certificates','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/qualification.jpg',false);
select fixture_try_insert('onboarding_stays_paused','employee-onboarding-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/onboarding.jpg',false);
select set_config('fixture.uid','20000000-0000-0000-0000-000000000002',false);
select fixture_try_insert('delegated_people_manager','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000002/manager.jpg',true);
select set_config('fixture.uid','20000000-0000-0000-0000-000000000003',false);
select fixture_try_insert('same_company_no_people_grant','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/no-grant.jpg',false);
select set_config('fixture.uid','20000000-0000-0000-0000-000000000004',false);
select fixture_try_insert('other_company_member','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/foreign.jpg',false);
reset role;
set role anon;
select fixture_try_insert('anonymous','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/anon.jpg',false);
reset role;
insert into private.restricted_users values('20000000-0000-0000-0000-000000000001');
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
set role authenticated;
select fixture_try_insert('restricted_self','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/restricted.jpg',false);
reset role;
delete from private.restricted_users;
-- Retention policies do not change in any candidate.
insert into private.retained_objects(name) select name from storage.objects where name like '%/self.jpg';
set role authenticated;
do $$declare n integer;begin
 update storage.objects set payload='overwritten' where name like '%/self.jpg';get diagnostics n=row_count;
 if n<>0 then raise exception 'Retained UPDATE allowed';end if;
 insert into fixture_checks values('retained_update_denied');
 delete from storage.objects where name like '%/self.jpg';get diagnostics n=row_count;
 if n<>0 then raise exception 'Retained DELETE allowed';end if;
 insert into fixture_checks values('retained_delete_denied');
 begin
 insert into storage.objects(bucket_id,name,payload)
 select bucket_id,name,'upsert' from storage.objects where name like '%/self.jpg'
 on conflict(bucket_id,name) do update set payload=excluded.payload;
 raise exception 'Retained UPSERT allowed';
 exception when insufficient_privilege then insert into fixture_checks values('retained_upsert_denied');end;
 begin
 insert into storage.objects(bucket_id,name,payload)
 select bucket_id,name,'duplicate' from storage.objects where name like '%/self.jpg';
 raise exception 'Fresh upload accepted duplicate existing name';
 exception when unique_violation then insert into fixture_checks values('duplicate_no_upsert_rejected');end;
end $$;
reset role;
-- Now replace only the synthetic broad permissive INSERT with the live contract.
-- Existing draft path validation is modeled separately from direct status upload.
drop policy fixture_authenticated_insert on storage.objects;
create policy worker_documents_insert on storage.objects for insert to authenticated with check(
 bucket_id='worker-documents' and private.has_company_feature(private.try_uuid(split_part(name,'/',1)),'can_manage_people'));
create table private.fixture_submission_drafts(upload_path text,requested_by uuid,worker_id uuid);
create function private.fixture_document_submission_access(p_name text,p_upload boolean) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.fixture_submission_drafts d join public.workers w on w.id=d.worker_id
 where p_upload and d.upload_path=p_name and d.requested_by=auth.uid() and w.user_id=auth.uid())$$;
create policy document_submission_upload on storage.objects for insert to authenticated with check(
 bucket_id='worker-documents' and private.fixture_document_submission_access(name,true));
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
set role authenticated;
select fixture_try_insert('A_self_saved_status_not_permitted','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/live-self.jpg',false);
select set_config('fixture.uid','20000000-0000-0000-0000-000000000002',false);
select fixture_try_insert('A_manager_saved_status_permitted','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/live-manager.jpg',true);
select fixture_try_insert('A_manager_own_upload_has_no_status','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/direct-a.jpg',false);
reset role;
insert into private.fixture_submission_drafts values
 ('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/draft-own.jpg','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/draft-foreign-request.jpg','20000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/draft-other-worker.jpg','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/60000000-0000-0000-0000-000000000001/draft-no-status.jpg','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
set role authenticated;
select fixture_try_insert('A_exact_owned_draft_and_status_permitted','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/draft-own.jpg',true);
select fixture_try_insert('A_draft_other_requested_by_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/draft-foreign-request.jpg',false);
select fixture_try_insert('A_draft_other_worker_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/draft-other-worker.jpg',false);
select fixture_try_insert('A_owned_draft_without_saved_status_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/60000000-0000-0000-0000-000000000001/draft-no-status.jpg',false);
reset role;
-- B: direct-new path needs worker/requirement checks but cannot require a saved
-- status before upload; an existing status path still needs its exact tuple.
create function private.fixture_worker_document_direct_match(p_name text) returns boolean language sql stable security invoker set search_path='' as $$
 select private.fixture_worker_document_insert_match(p_name) or (
 private.account_access_allowed() and cardinality(string_to_array(p_name,'/'))=5
 and split_part(p_name,'/',4)='own-upload'
 and split_part(p_name,'/',5) ~ '^[a-zA-Z0-9_-]+[.](jpg|jpeg|png|pdf)$'
 and exists(select 1 from public.workers w join public.document_requirements r on r.company_id=w.company_id
 where w.id=private.try_uuid(split_part(p_name,'/',2)) and w.company_id=private.try_uuid(split_part(p_name,'/',1))
 and r.id=private.try_uuid(split_part(p_name,'/',3)) and r.is_active and w.status='active'
 and exists(select 1 from public.company_members cm where cm.company_id=w.company_id and cm.user_id=auth.uid())
 and (w.user_id=auth.uid() or private.has_company_feature(w.company_id,'can_manage_people'))))$$;
alter policy initial_beta_official_documents_insert_pause on storage.objects with check(
 bucket_id not in ('worker-documents','qualification-certificates','employee-onboarding-documents')
 or (bucket_id='worker-documents' and private.fixture_worker_document_direct_match(name)));
set role authenticated;
select set_config('fixture.uid','20000000-0000-0000-0000-000000000002',false);
select fixture_try_insert('B_manager_direct_permitted','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/direct-b.jpg',true);
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
select fixture_try_insert('B_self_direct_still_not_permitted','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/self-b.jpg',false);
reset role;
-- C adds only本人 INSERT permissive; no UPDATE/DELETE/self-role grant expansion.
create function private.fixture_worker_document_self_match(p_name text) returns boolean language sql stable security invoker set search_path='' as $$
 select private.fixture_worker_document_direct_match(p_name) and exists(select 1 from public.workers w
 where w.id=private.try_uuid(split_part(p_name,'/',2)) and w.company_id=private.try_uuid(split_part(p_name,'/',1)) and w.user_id=auth.uid())$$;
create policy fixture_self_direct_insert on storage.objects for insert to authenticated with check(
 bucket_id='worker-documents' and private.fixture_worker_document_self_match(name));
set role authenticated;
select fixture_try_insert('C_self_direct_permitted','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/self-c.jpg',true);
select fixture_try_insert('C_self_saved_status_permitted','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/self-c-existing.jpg',true);
select fixture_try_insert('C_direct_other_worker_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/40000000-0000-0000-0000-000000000001/own-upload/other-c.jpg',false);
select fixture_try_insert('C_direct_unsafe_extension_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/unsafe.exe',false);
select fixture_try_insert('C_direct_extra_path_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/sub/extra.jpg',false);
select fixture_try_insert('C_qualification_stays_paused','qualification-certificates','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/qual-c.jpg',false);
select fixture_try_insert('C_onboarding_stays_paused','employee-onboarding-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/onboard-c.jpg',false);
select set_config('fixture.uid','',false);
select fixture_try_insert('C_authenticated_null_uid_denied','worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/null-c.jpg',false);
reset role;
do $$begin
 if exists(select 1 from original_holds h where not exists(select 1 from pg_policy p
 where p.polrelid='storage.objects'::regclass and p.polname=h.polname and p.polcmd=h.polcmd
 and pg_get_expr(p.polqual,p.polrelid) is not distinct from h.qual
 and pg_get_expr(p.polwithcheck,p.polrelid) is not distinct from h.chk)) then raise exception 'Retention policies changed';end if;
 if exists(select 1 from storage.objects o join private.retained_objects r on r.name=o.name where o.payload<>'synthetic') then raise exception 'Retained payload changed';end if;
end $$;
