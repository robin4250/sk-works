create role authenticated; create role anon;
create schema auth; create schema private; create schema storage;
create table storage.objects(bucket_id text,name text);
alter table storage.objects enable row level security;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(nullif(current_setting('test.account',true),'')::boolean,false)$$;
create function private.license_document_upload_allowed(text) returns boolean language sql as $$select false$$;
create function private.qualification_photo_draft_upload_allowed(text) returns boolean language sql as $$select false$$;
create function private.worker_document_photo_upload_allowed(text) returns boolean language sql as $$select false$$;
create function public.expense_receipt_access(text,boolean) returns boolean language sql as $$select false$$;
create table public.communication_groups(id uuid);
create function private.can_edit_custom_chat_photo(uuid) returns boolean language sql as $$select false$$;
create table public.workers(user_id uuid,company_id uuid,status text);
create table public.company_members(user_id uuid,company_id uuid,role text);
insert into public.workers values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','active');
insert into public.company_members values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','owner');
create policy license_document_pilot_insert_scope on storage.objects as restrictive for insert to authenticated with check (((bucket_id <> ALL (ARRAY['worker-documents'::text, 'qualification-certificates'::text, 'employee-onboarding-documents'::text])) OR ((bucket_id = 'worker-documents'::text) AND (auth.uid() IS NOT NULL) AND private.license_document_upload_allowed(name)) OR ((bucket_id = 'qualification-certificates'::text) AND private.qualification_photo_draft_upload_allowed(name)) OR ((bucket_id = 'worker-documents'::text) AND private.worker_document_photo_upload_allowed(name))));
create policy custom_chat_photo_insert_boundary on storage.objects as restrictive for insert to authenticated with check (((bucket_id <> 'custom-chat-photos'::text) OR ((split_part(name, '/'::text, 2) = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM communication_groups g
  WHERE (((g.id)::text = split_part(objects.name, '/'::text, 1)) AND private.can_edit_custom_chat_photo(g.id)))))));
create policy expense_receipt_insert_boundary on storage.objects as restrictive for insert to public with check (((bucket_id <> 'expense-receipts'::text) OR expense_receipt_access(name, true)));
create policy fixture_permissive on storage.objects as permissive for insert to authenticated with check (true);

