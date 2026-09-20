-- Run against the production project to verify pre-device security invariants.
do $$
declare
  v_sensitive_bucket_count integer;
  v_storage_guard text;
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
  ) then
    raise exception 'one or more public tables have RLS disabled';
  end if;

  if exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee = 'anon'
  ) then
    raise exception 'anon must not have direct public table privileges';
  end if;

  if exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee in ('anon', 'authenticated')
      and privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')
  ) then
    raise exception 'anon/authenticated has unnecessary public table privilege';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and (
        has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('public', p.oid, 'EXECUTE')
      )
  ) then
    raise exception 'SECURITY DEFINER function is executable by anon or PUBLIC';
  end if;

  if has_table_privilege('authenticated', 'public.app_notifications', 'INSERT,DELETE') then
    raise exception 'authenticated must not insert/delete app_notifications directly';
  end if;

  if has_table_privilege('anon', 'public.company_members', 'SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.company_members', 'INSERT,UPDATE,DELETE') then
    raise exception 'company_members direct writes must be blocked';
  end if;

  if has_table_privilege('anon', 'public.user_secondary_credentials', 'SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.user_secondary_credentials', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'user_secondary_credentials must not be directly accessible';
  end if;

  if has_table_privilege('anon', 'public.line_webhook_events', 'SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.line_webhook_events', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'line_webhook_events must not be directly accessible';
  end if;

  if position('User already belongs to a company' in pg_get_functiondef('public.create_company(text)'::regprocedure)) = 0
     or position('pg_advisory_xact_lock' in pg_get_functiondef('public.create_company(text)'::regprocedure)) = 0 then
    raise exception 'create_company first-membership guard missing';
  end if;

  if position('coalesce(mfp.can_approve_daily_report_edits, true)' in pg_get_functiondef('public.request_daily_report_edit(uuid,text)'::regprocedure)) = 0 then
    raise exception 'daily report approval notification manager default missing';
  end if;

  if position('v_role = ''manager''' in pg_get_functiondef('public.current_feature_permissions()'::regprocedure)) = 0 then
    raise exception 'manager default feature permissions missing';
  end if;

  if position('owner role cannot be changed' in pg_get_functiondef('public.set_member_feature_permissions(uuid,text,jsonb)'::regprocedure)) = 0 then
    raise exception 'owner role protection missing';
  end if;

  if position('failed_attempts + 1 >= 5' in pg_get_functiondef('public.verify_secondary_password(text)'::regprocedure)) = 0 then
    raise exception 'secondary-password five-attempt lock contract missing';
  end if;

  if position('requester cannot approve own request' in pg_get_functiondef('public.decide_daily_report_edit(uuid,text)'::regprocedure)) = 0 then
    raise exception 'daily-report self-approval protection missing';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='daily_report_edit_requests'
      and column_name='approvals_required'
      and column_default::text like '%2%'
  ) then
    raise exception 'daily-report two-approval default missing';
  end if;

  select count(*)
  into v_sensitive_bucket_count
  from storage.buckets
  where id in (
    'attendance-evidence',
    'chat-attachments',
    'communication-albums',
    'profile-photos',
    'qualification-certificates',
    'worker-documents'
  );

  if v_sensitive_bucket_count <> 6 then
    raise exception 'one or more required private storage buckets are missing';
  end if;

  if exists (
    select 1
    from storage.buckets
    where id in (
      'attendance-evidence',
      'chat-attachments',
      'communication-albums',
      'profile-photos',
      'qualification-certificates',
      'worker-documents'
    )
      and public
  ) then
    raise exception 'sensitive storage bucket must not be public';
  end if;

  select pg_get_functiondef('private.has_storage_company_access(text)'::regprocedure)
  into v_storage_guard;

  if position('auth.uid()' in v_storage_guard) = 0
     or position('storage.foldername' in v_storage_guard) = 0 then
    raise exception 'storage company access guard contract missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile_photos_read'
      and 'authenticated' = any(roles)
  ) then
    raise exception 'profile photo authenticated read policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'worker_document_statuses'
      and policyname = 'worker or people manager can read document statuses'
      and position('w.user_id = auth.uid()' in coalesce(qual, '')) > 0
      and position('can_manage_people' in coalesce(qual, '')) > 0
  ) then
    raise exception 'worker document self-or-manager policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'worker_qualifications'
      and policyname = 'worker or people manager can read worker qualifications'
      and position('w.user_id = auth.uid()' in coalesce(qual, '')) > 0
      and position('can_manage_people' in coalesce(qual, '')) > 0
  ) then
    raise exception 'worker qualification self-or-manager policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'worker_documents_read'
      and position('w.user_id = auth.uid()' in coalesce(qual, '')) > 0
      and position('can_manage_people' in coalesce(qual, '')) > 0
  ) then
    raise exception 'worker document storage self-or-manager policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'qualification_certificates_read'
      and position('w.user_id = auth.uid()' in coalesce(qual, '')) > 0
      and position('can_manage_people' in coalesce(qual, '')) > 0
  ) then
    raise exception 'qualification certificate storage self-or-manager policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'attendance_evidence_read'
      and 'authenticated' = any(roles)
      and position('can_manage_attendance' in coalesce(qual, '')) > 0
      and position('w.user_id = auth.uid()' in coalesce(qual, '')) > 0
  ) then
    raise exception 'attendance evidence self-or-manager read policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'attendance_evidence_delete'
      and position('can_manage_attendance' in coalesce(qual, '')) > 0
      and position('w.user_id = auth.uid()' in coalesce(qual, '')) > 0
      and position('photo_storage_path' in coalesce(qual, '')) > 0
  ) then
    raise exception 'attendance evidence orphan cleanup policy missing';
  end if;
end
$$;

select 'SKO pre-device database security assertions passed' as result;
