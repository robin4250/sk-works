-- Product SQL assertions. Synthetic isolated DB only; never production.
create schema auth;create schema private;create schema storage;
create role authenticated;create role anon;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
create function private.try_uuid(v text) returns uuid language plpgsql immutable as $$begin return v::uuid;exception when invalid_text_representation then return null;end$$;
create table public.company_members(company_id uuid,user_id uuid);
create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
alter table public.workers add column name text,add column fixture_ungranted text;
create table public.document_requirements(id uuid primary key,company_id uuid,is_active boolean);
create table public.worker_document_statuses(id uuid primary key,company_id uuid,worker_id uuid,requirement_id uuid,attachment_path text);
create table private.feature_grants(company_id uuid,user_id uuid,feature text);
create table private.restricted_users(user_id uuid);
create table private.retained_objects(name text primary key);
create function private.has_company_feature(cid uuid,f text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.feature_grants g where g.company_id=cid and g.user_id=auth.uid() and g.feature=f)$$;
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from private.restricted_users r where r.user_id=auth.uid())$$;
-- Synthetic equivalents of existing scoped readable business rows; no candidate
-- helper is SECURITY DEFINER and no new production table grants are proposed.
grant select on public.company_members,public.document_requirements,public.worker_document_statuses to authenticated;
grant select(id,company_id,name,status,user_id) on public.workers to authenticated;
alter table public.company_members enable row level security;
create policy fixture_member_read on public.company_members for select to authenticated using(user_id=auth.uid());
alter table public.workers enable row level security;
create policy fixture_worker_read on public.workers for select to authenticated using(exists(select 1 from public.company_members cm where cm.company_id=workers.company_id and cm.user_id=auth.uid()));
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
create policy worker_documents_insert on storage.objects for insert to authenticated with check(bucket_id='worker-documents' and private.has_company_feature(private.try_uuid(split_part(name,'/',1)),'can_manage_people'));
create table private.fixture_submission_drafts(upload_path text,requested_by uuid,worker_id uuid);
create function private.document_submission_access(p_name text,p_upload boolean) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.fixture_submission_drafts d join public.workers w on w.id=d.worker_id where p_upload and d.upload_path=p_name and d.requested_by=auth.uid() and w.user_id=auth.uid())$$;
create policy document_submission_upload on storage.objects for insert to authenticated with check(bucket_id='worker-documents' and private.document_submission_access(name,true));
create policy fixture_other_bucket_insert on storage.objects for insert to authenticated with check(bucket_id in ('qualification-certificates','employee-onboarding-documents'));
create policy fixture_authenticated_read on storage.objects for select to authenticated using(true);
create policy fixture_authenticated_update on storage.objects for update to authenticated using(true) with check(true);
create policy fixture_authenticated_delete on storage.objects for delete to authenticated using(true);
create policy initial_beta_official_documents_insert_pause on storage.objects as restrictive for insert to public
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
insert into workers(id,company_id,user_id,status) values
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
-- Metadata-only reproduction of the observed account guard on readable rows.
create policy account_deletion_access_guard on public.workers as restrictive for all to authenticated using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
create policy account_deletion_access_guard on public.company_members as restrictive for all to authenticated using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
create policy account_deletion_access_guard on public.document_requirements as restrictive for all to authenticated using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
create policy account_deletion_access_guard on public.worker_document_statuses as restrictive for all to authenticated using((select private.account_access_allowed())) with check((select private.account_access_allowed()));
create table fixture_checks(label text primary key);

create policy initial_beta_official_documents_update_pause on storage.objects as restrictive for update to public
 using(bucket_id not in ('worker-documents','qualification-certificates','employee-onboarding-documents'))
 with check(bucket_id not in ('worker-documents','qualification-certificates','employee-onboarding-documents'));
-- Saved synthetic status/history/object and audit trigger to protect across DDL.
create table public.worker_document_status_history(id uuid primary key default gen_random_uuid(),status_id uuid,old_path text,new_path text,operation text);
create function private.fixture_audit_worker_document_status() returns trigger language plpgsql as $$begin
 insert into public.worker_document_status_history(status_id,old_path,new_path,operation) values(coalesce(new.id,old.id),old.attachment_path,new.attachment_path,tg_op);return coalesce(new,old);end$$;
create trigger audit_worker_document_status_changes after insert or delete or update on public.worker_document_statuses for each row execute function private.fixture_audit_worker_document_status();
update public.worker_document_statuses set attachment_path='10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/old.jpg' where id='50000000-0000-0000-0000-000000000001';
insert into storage.objects(bucket_id,name,payload) select 'worker-documents',attachment_path,'retained-original' from public.worker_document_statuses where attachment_path is not null;
insert into private.retained_objects(name) select name from storage.objects;
alter table public.document_requirements add column name text not null default 'Synthetic license';
update public.document_requirements set name='Synthetic bank' where id='40000000-0000-0000-0000-000000000003';
-- PRODUCT_ASSERTIONS
grant insert on fixture_checks to authenticated,anon;
create function public.fixture_license_insert(p_label text,p_allowed boolean,
 p_worker uuid default '30000000-0000-0000-0000-000000000001',
 p_requirement uuid default '40000000-0000-0000-0000-000000000001',p_segment text default 'own-upload',
 p_filename text default null,p_bucket text default 'worker-documents',
 p_company uuid default '10000000-0000-0000-0000-000000000001') returns void language plpgsql security invoker as $$
declare ok boolean:=true;p_path text;msg text;begin
 p_path:=concat_ws('/',p_company,p_worker,p_requirement,p_segment,coalesce(p_filename,p_label||'.jpg'));
 begin insert into storage.objects(bucket_id,name,payload) values(p_bucket,p_path,'new-synthetic');
 exception when insufficient_privilege then ok:=false;get stacked diagnostics msg=message_text;end;
 if ok is distinct from p_allowed then raise exception 'Unexpected product INSERT % allowed:% expected:% (%): %',p_label,ok,p_allowed,msg,p_path;end if;
 insert into fixture_checks values(p_label);
end $$;
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
set role authenticated;
select fixture_license_insert('empty_gate_self',false);
select set_config('fixture.uid','20000000-0000-0000-0000-000000000002',false);
select fixture_license_insert('empty_gate_manager',false);
reset role;
insert into private.license_document_upload_pilots(company_id,requirement_id,requirement_name_snapshot)
 values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','Synthetic license');
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
set role authenticated;
select fixture_license_insert('default_off_self',false);
reset role;
-- Gate activation is synthetic operator setup, separate from migration application.
update private.license_document_upload_pilots set enabled=true;
set role authenticated;
select fixture_license_insert('selected_self_new',true);
select fixture_license_insert('selected_self_existing',true,p_segment=>'50000000-0000-0000-0000-000000000001');
select fixture_license_insert('other_worker',false,p_worker=>'30000000-0000-0000-0000-000000000002');
select fixture_license_insert('wrong_company',false,p_company=>'10000000-0000-0000-0000-000000000002');
select fixture_license_insert('wrong_requirement',false,p_requirement=>'40000000-0000-0000-0000-000000000002');
select fixture_license_insert('inactive_requirement',false,p_requirement=>'40000000-0000-0000-0000-000000000003');
select fixture_license_insert('missing_requirement',false,p_requirement=>'40000000-0000-0000-0000-000000000099');
select fixture_license_insert('missing_worker',false,p_worker=>'30000000-0000-0000-0000-000000000099');
select fixture_license_insert('mismatched_status',false,p_segment=>'50000000-0000-0000-0000-000000000002');
select fixture_license_insert('missing_status',false,p_segment=>'50000000-0000-0000-0000-000000000099');
select fixture_license_insert('invalid_status_uuid',false,p_segment=>'not-a-uuid');
select fixture_license_insert('extra_segment',false,p_segment=>'own-upload/extra');
select fixture_license_insert('empty_filename',false,p_filename=>'');
select fixture_license_insert('path_traversal',false,p_filename=>'../file.jpg');
select fixture_license_insert('unsafe_extension',false,p_filename=>'file.exe');
select fixture_license_insert('uppercase_extension',false,p_filename=>'file.JPG');
select fixture_license_insert('missing_extension',false,p_filename=>'file');
select fixture_license_insert('allowed_jpeg',true,p_filename=>'allowed.jpeg');
select fixture_license_insert('allowed_png',true,p_filename=>'allowed.png');
select fixture_license_insert('allowed_pdf',true,p_filename=>'allowed.pdf');
select fixture_license_insert('allowed_heic',true,p_filename=>'allowed.heic');
select fixture_license_insert('allowed_heif',true,p_filename=>'allowed.heif');
select fixture_license_insert('qualification_pause',false,p_bucket=>'qualification-certificates');
select fixture_license_insert('onboarding_pause',false,p_bucket=>'employee-onboarding-documents');
select set_config('fixture.uid','20000000-0000-0000-0000-000000000002',false);
select fixture_license_insert('manager_other_worker',true,p_worker=>'30000000-0000-0000-0000-000000000002');
select fixture_license_insert('manager_unselected_requirement',false,p_requirement=>'40000000-0000-0000-0000-000000000002');
select set_config('fixture.uid','20000000-0000-0000-0000-000000000003',false);
select fixture_license_insert('same_company_no_people',false);
select set_config('fixture.uid','20000000-0000-0000-0000-000000000004',false);
select fixture_license_insert('foreign_company',false);
select set_config('fixture.uid','',false);
select fixture_license_insert('null_uid_authenticated',false);
reset role;
set role anon;
select fixture_license_insert('anonymous',false);
do $$begin
 begin perform private.license_document_upload_allowed('anything');raise exception 'Anon helper executable';
 exception when insufficient_privilege then insert into fixture_checks values('anonymous_helper_denied');end;
end $$;
reset role;
select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',false);
-- Requirement name is frozen: renaming this ID to another kind stops it.
update public.document_requirements set name='Synthetic bank' where id='40000000-0000-0000-0000-000000000001';
set role authenticated;
select fixture_license_insert('renamed_same_id_stopped',false);
reset role;
update public.document_requirements set name='Synthetic license' where id='40000000-0000-0000-0000-000000000001';
insert into public.document_requirements(id,company_id,is_active,name)
 values('40000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001',true,'Synthetic license');
set role authenticated;
select fixture_license_insert('same_name_other_id_stopped',false,p_requirement=>'40000000-0000-0000-0000-000000000004');
reset role;
update public.document_requirements set is_active=false where id='40000000-0000-0000-0000-000000000001';
set role authenticated;
select fixture_license_insert('selected_requirement_inactive',false);
reset role;
update public.document_requirements set is_active=true where id='40000000-0000-0000-0000-000000000001';
update public.workers set status='inactive' where id='30000000-0000-0000-0000-000000000001';
set role authenticated;
select fixture_license_insert('inactive_self_worker',false);
reset role;
update public.workers set status='active' where id='30000000-0000-0000-0000-000000000001';
set role authenticated;
do $$declare n integer;begin
 if has_table_privilege('authenticated','public.workers','SELECT') then raise exception 'Broad worker SELECT introduced';end if;
 perform id,company_id,user_id,status,name from public.workers;
 insert into fixture_checks values('narrow_worker_columns_allowed');
 begin perform * from public.workers;raise exception 'Worker SELECT star allowed';exception when insufficient_privilege then insert into fixture_checks values('worker_select_star_denied');end;
 begin insert into private.license_document_upload_pilots values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000004','Synthetic license',true);raise exception 'Client gate INSERT allowed';exception when insufficient_privilege then insert into fixture_checks values('pilot_insert_denied');end;
 begin update private.license_document_upload_pilots set enabled=false;raise exception 'Client gate UPDATE allowed';exception when insufficient_privilege then insert into fixture_checks values('pilot_update_denied');end;
 begin delete from private.license_document_upload_pilots;raise exception 'Client gate DELETE allowed';exception when insufficient_privilege then insert into fixture_checks values('pilot_delete_denied');end;
 update storage.objects set payload='overwritten' where payload='retained-original';get diagnostics n=row_count;
 if n<>0 then raise exception 'Retained overwrite allowed';end if;insert into fixture_checks values('retained_update_denied');
 delete from storage.objects where payload='retained-original';get diagnostics n=row_count;
 if n<>0 then raise exception 'Retained delete allowed';end if;insert into fixture_checks values('retained_delete_denied');
 begin insert into storage.objects(bucket_id,name,payload) select bucket_id,name,'upsert' from storage.objects where payload='retained-original' on conflict(bucket_id,name) do update set payload=excluded.payload;raise exception 'Retained upsert allowed';exception when insufficient_privilege then insert into fixture_checks values('retained_upsert_denied');end;
 begin insert into storage.objects(bucket_id,name,payload) select bucket_id,name,'duplicate' from storage.objects where name like '%/selected_self_new.jpg';raise exception 'Duplicate non-upsert accepted';exception when unique_violation then insert into fixture_checks values('duplicate_fresh_path_denied');end;
end $$;
reset role;
insert into private.license_document_upload_pilots values('10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','Synthetic license',true);
set role authenticated;
do $$begin
 if exists(select 1 from private.license_document_upload_pilots where company_id='10000000-0000-0000-0000-000000000002') then raise exception 'Other company pilot readable';end if;
 insert into fixture_checks values('foreign_pilot_hidden');
end $$;
reset role;
set role anon;
do $$begin
 begin perform * from private.license_document_upload_pilots;raise exception 'Anon pilot readable';exception when insufficient_privilege then insert into fixture_checks values('anonymous_pilot_read_denied');end;
end $$;
reset role;
insert into private.restricted_users values('20000000-0000-0000-0000-000000000001');
set role authenticated;
select fixture_license_insert('restricted_selected_user',false);
do $$begin
 if exists(select 1 from private.license_document_upload_pilots) then raise exception 'Restricted pilot readable';end if;insert into fixture_checks values('restricted_pilot_hidden');
end $$;
reset role;
delete from private.restricted_users;
-- Even a malformed UUID path is rejected as RLS rather than permitting escape.
set role authenticated;
do $$begin
 begin insert into storage.objects(bucket_id,name,payload) values('worker-documents','not-uuid/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/own-upload/bad.jpg','synthetic');raise exception 'Malformed company UUID allowed';exception when insufficient_privilege then insert into fixture_checks values('malformed_company_uuid_denied');end;
end $$;
reset role;
set role authenticated;
do $$begin
 begin insert into storage.objects(bucket_id,name,payload) values('worker-documents','10000000-0000-0000-0000-000000000001/not-uuid/40000000-0000-0000-0000-000000000001/own-upload/bad-worker.jpg','synthetic');raise exception 'Malformed worker UUID allowed';exception when insufficient_privilege then insert into fixture_checks values('malformed_worker_uuid_denied');end;
 begin insert into storage.objects(bucket_id,name,payload) values('worker-documents','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/not-uuid/own-upload/bad-requirement.jpg','synthetic');raise exception 'Malformed requirement UUID allowed';exception when insufficient_privilege then insert into fixture_checks values('malformed_requirement_uuid_denied');end;
end $$;
reset role;
delete from public.document_requirements where id='40000000-0000-0000-0000-000000000001';
set role authenticated;
select fixture_license_insert('stale_selected_requirement_missing',false);
reset role;
insert into public.document_requirements(id,company_id,is_active,name) values('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true,'Synthetic license');
