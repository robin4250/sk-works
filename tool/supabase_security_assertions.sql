-- Run against the production project to verify pre-device security invariants.
do $$
declare
  v_sensitive_bucket_count integer;
  v_storage_guard text;
begin
  if exists (
    with grants as (
      select table_name, privilege_type
      from information_schema.role_table_grants
      where table_schema = 'public'
        and grantee = 'authenticated'
        and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
    ),
    policies as (
      select tablename,
             case cmd
               when 'SELECT' then 'SELECT'
               when 'INSERT' then 'INSERT'
               when 'UPDATE' then 'UPDATE'
               when 'DELETE' then 'DELETE'
               when 'ALL' then 'ALL'
             end as privilege_type
      from pg_policies
      where schemaname = 'public'
        and (
          'authenticated' = any(roles)
          or 'public' = any(roles)
        )
    )
    select 1
    from grants g
    where not exists (
      select 1
      from policies p
      where p.tablename = g.table_name
        and (
          p.privilege_type = g.privilege_type
          or p.privilege_type = 'ALL'
        )
    )
  ) then
    raise exception 'authenticated has CRUD grant without matching RLS policy';
  end if;

  if has_column_privilege('authenticated', 'public.companies', 'bank_settings', 'SELECT')
     or has_column_privilege('authenticated', 'public.companies', 'bank_name', 'SELECT')
     or has_column_privilege('authenticated', 'public.companies', 'bank_branch', 'SELECT')
     or has_column_privilege('authenticated', 'public.companies', 'bank_account_type', 'SELECT')
     or has_column_privilege('authenticated', 'public.companies', 'bank_account_number', 'SELECT')
     or has_column_privilege('authenticated', 'public.companies', 'bank_account_holder', 'SELECT') then
    raise exception 'legacy company bank columns must not be directly selectable';
  end if;

  if not has_column_privilege('authenticated', 'public.companies', 'name', 'SELECT') then
    raise exception 'company name must remain selectable for member UI';
  end if;

  if has_column_privilege('authenticated', 'public.workers', 'phone', 'SELECT')
     or has_column_privilege('authenticated', 'public.workers', 'email', 'SELECT')
     or has_column_privilege('authenticated', 'public.workers', 'notes', 'SELECT') then
    raise exception 'worker private contact columns must not be directly selectable';
  end if;

  if has_column_privilege('authenticated', 'public.partner_companies', 'phone', 'SELECT')
     or has_column_privilege('authenticated', 'public.partner_companies', 'email', 'SELECT')
     or has_column_privilege('authenticated', 'public.partner_companies', 'address', 'SELECT')
     or has_column_privilege('authenticated', 'public.partner_companies', 'notes', 'SELECT') then
    raise exception 'partner-company private contact columns must not be directly selectable';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'customers'
      and policyname = 'invoice viewers can read customers'
      and position('can_view_invoices' in coalesce(qual, '')) > 0
  ) then
    raise exception 'customer billing privacy policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'company_members'
      and policyname = 'company_members_self_read'
      and position('user_id = auth.uid()' in coalesce(qual, '')) > 0
  ) then
    raise exception 'company_members self-read policy missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'line_group_bindings'
      and policyname = 'owners and admins can read line bindings'
      and position('owner' in coalesce(qual, '')) > 0
      and position('admin' in coalesce(qual, '')) > 0
  ) then
    raise exception 'LINE binding owner/admin visibility policy missing';
  end if;

  if has_schema_privilege('anon', 'public', 'CREATE')
     or has_schema_privilege('authenticated', 'public', 'CREATE')
     or has_schema_privilege('anon', 'private', 'CREATE')
     or has_schema_privilege('authenticated', 'private', 'CREATE')
     or has_schema_privilege('anon', 'storage', 'CREATE')
     or has_schema_privilege('authenticated', 'storage', 'CREATE')
     or has_schema_privilege('anon', 'extensions', 'CREATE')
     or has_schema_privilege('authenticated', 'extensions', 'CREATE') then
    raise exception 'app roles must not have CREATE on security-sensitive schemas';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef
      and n.nspname in ('public', 'private')
      and not exists (
        select 1
        from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
      )
  ) then
    raise exception 'SECURITY DEFINER function without explicit search_path';
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('v', 'm')
      and (
        has_table_privilege('anon', format('%I.%I', n.nspname, c.relname), 'SELECT')
        or has_table_privilege('authenticated', format('%I.%I', n.nspname, c.relname), 'SELECT')
      )
      and (
        c.relkind = 'm'
        or not ('security_invoker=true' = any(coalesce(c.reloptions, array[]::text[])))
      )
  ) then
    raise exception 'exposed public view/materialized view may bypass RLS';
  end if;

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

  if exists (
    select 1
    from (
      values
        ('profile-photos'::text, 10485760::bigint),
        ('attendance-evidence'::text, 15728640::bigint),
        ('qualification-certificates'::text, 20971520::bigint),
        ('communication-albums'::text, 20971520::bigint),
        ('worker-documents'::text, 52428800::bigint),
        ('chat-attachments'::text, 52428800::bigint)
    ) as expected(id, file_size_limit)
    left join storage.buckets b on b.id = expected.id
    where b.id is null
       or b.public
       or b.file_size_limit is distinct from expected.file_size_limit
  ) then
    raise exception 'private storage bucket size limits do not match SKO baseline';
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
      and position('auth.uid()' in coalesce(qual, '')) > 0
      and position('company_members' in coalesce(qual, '')) > 0
      and position('other.company_id = me.company_id' in coalesce(qual, '')) > 0
  ) then
    raise exception 'profile photo self-or-same-company read policy missing';
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
