alter table public.employee_registration_invites
  add column if not exists address text,
  add column if not exists blood_type text,
  add column if not exists family_composition text,
  add column if not exists emergency_relation text,
  add column if not exists emergency_name text,
  add column if not exists emergency_phone text,
  add column if not exists emergency_address text,
  add column if not exists portrait_path text,
  add column if not exists my_number_front_path text,
  add column if not exists my_number_back_path text,
  add column if not exists submitted_at timestamptz,
  add column if not exists approved_by uuid references auth.users(id) on delete set null,
  add column if not exists approved_at timestamptz;

insert into storage.buckets(id, name, public, file_size_limit)
values (
  'employee-onboarding-documents',
  'employee-onboarding-documents',
  false,
  20971520
)
on conflict(id) do update
set public = false,
    file_size_limit = excluded.file_size_limit;

create or replace function private.can_review_employee_onboarding_user(
  p_subject_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.employee_registration_invites eri
    join public.company_members cm
      on cm.company_id = eri.company_id
     and cm.user_id = auth.uid()
    left join public.company_approval_assignees caa
      on caa.company_id = eri.company_id
     and caa.user_id = auth.uid()
    where eri.auth_user_id = p_subject_user_id
      and (
        cm.role::text in ('owner','admin')
        or caa.user_id is not null
      )
  );
$$;

revoke execute on function private.can_review_employee_onboarding_user(uuid)
  from public, anon;
grant execute on function private.can_review_employee_onboarding_user(uuid)
  to authenticated;

drop policy if exists employee_onboarding_documents_insert on storage.objects;
create policy employee_onboarding_documents_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'employee-onboarding-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1
    from public.employee_registration_invites eri
    where eri.auth_user_id = auth.uid()
      and eri.status in ('invited','password_changed','profile_pending','approval_pending')
  )
);

drop policy if exists employee_onboarding_documents_read on storage.objects;
create policy employee_onboarding_documents_read
on storage.objects for select to authenticated
using (
  bucket_id = 'employee-onboarding-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or private.can_review_employee_onboarding_user(
      ((storage.foldername(name))[1])::uuid
    )
  )
);

drop policy if exists employee_onboarding_documents_update on storage.objects;
create policy employee_onboarding_documents_update
on storage.objects for update to authenticated
using (
  bucket_id = 'employee-onboarding-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'employee-onboarding-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists employee_onboarding_documents_delete on storage.objects;
create policy employee_onboarding_documents_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'employee-onboarding-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create or replace function public.save_employee_onboarding_profile(
  p_address text,
  p_blood_type text,
  p_family_composition text,
  p_emergency_relation text,
  p_emergency_name text,
  p_emergency_phone text,
  p_emergency_address text,
  p_portrait_path text,
  p_my_number_front_path text,
  p_my_number_back_path text
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_invite_id uuid;
  v_reviewer record;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if nullif(trim(coalesce(p_address, '')), '') is null
     or nullif(trim(coalesce(p_blood_type, '')), '') is null
     or nullif(trim(coalesce(p_family_composition, '')), '') is null
     or nullif(trim(coalesce(p_emergency_relation, '')), '') is null
     or nullif(trim(coalesce(p_emergency_name, '')), '') is null
     or nullif(trim(coalesce(p_emergency_phone, '')), '') is null
     or nullif(trim(coalesce(p_emergency_address, '')), '') is null
     or nullif(trim(coalesce(p_portrait_path, '')), '') is null
     or nullif(trim(coalesce(p_my_number_front_path, '')), '') is null
     or nullif(trim(coalesce(p_my_number_back_path, '')), '') is null then
    raise exception 'required onboarding field missing';
  end if;

  update public.employee_registration_invites eri
  set address = trim(p_address),
      blood_type = trim(p_blood_type),
      family_composition = trim(p_family_composition),
      emergency_relation = trim(p_emergency_relation),
      emergency_name = trim(p_emergency_name),
      emergency_phone = trim(p_emergency_phone),
      emergency_address = trim(p_emergency_address),
      portrait_path = trim(p_portrait_path),
      my_number_front_path = trim(p_my_number_front_path),
      my_number_back_path = trim(p_my_number_back_path),
      status = 'approval_pending',
      submitted_at = now()
  where eri.auth_user_id = v_user_id
    and eri.password_changed_at is not null
    and eri.status in ('profile_pending','approval_pending')
  returning eri.id, eri.company_id into v_invite_id, v_company_id;

  if v_invite_id is null then
    raise exception 'employee onboarding is not ready for profile submission';
  end if;

  for v_reviewer in
    select distinct cm.user_id
    from public.company_members cm
    left join public.company_approval_assignees caa
      on caa.company_id = cm.company_id
     and caa.user_id = cm.user_id
    where cm.company_id = v_company_id
      and (
        cm.role::text in ('owner','admin')
        or caa.user_id is not null
      )
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_reviewer.user_id,
      'approval',
      '従業員の本登録申請',
      '本人情報の登録が完了しました。本登録を確認してください。',
      'employee_onboarding_approval',
      v_invite_id
    );
  end loop;
end;
$$;

create or replace function public.can_review_employee_onboarding()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.company_members cm
    left join public.company_approval_assignees caa
      on caa.company_id = cm.company_id
     and caa.user_id = cm.user_id
    where cm.user_id = auth.uid()
      and (
        cm.role::text in ('owner','admin')
        or caa.user_id is not null
      )
  );
$$;

create or replace function public.pending_employee_onboarding_rows()
returns table(
  invite_id uuid,
  company_id uuid,
  worker_id uuid,
  auth_user_id uuid,
  name text,
  phone text,
  address text,
  blood_type text,
  family_composition text,
  emergency_relation text,
  emergency_name text,
  emergency_phone text,
  emergency_address text,
  portrait_path text,
  my_number_front_path text,
  my_number_back_path text,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  left join public.company_approval_assignees caa
    on caa.company_id = cm.company_id
   and caa.user_id = cm.user_id
  where cm.user_id = v_user_id
    and (
      cm.role::text in ('owner','admin')
      or caa.user_id is not null
    )
  limit 1;

  if v_company_id is null then
    raise exception 'onboarding approval permission required';
  end if;

  return query
  select
    eri.id,
    eri.company_id,
    eri.worker_id,
    eri.auth_user_id,
    eri.name,
    eri.phone_e164,
    eri.address,
    eri.blood_type,
    eri.family_composition,
    eri.emergency_relation,
    eri.emergency_name,
    eri.emergency_phone,
    eri.emergency_address,
    eri.portrait_path,
    eri.my_number_front_path,
    eri.my_number_back_path,
    eri.submitted_at
  from public.employee_registration_invites eri
  where eri.company_id = v_company_id
    and eri.status = 'approval_pending'
  order by eri.submitted_at nulls last, eri.created_at;
end;
$$;

create or replace function public.approve_employee_onboarding(
  p_invite_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_reviewer uuid := auth.uid();
  v_invite public.employee_registration_invites%rowtype;
begin
  if v_reviewer is null then
    raise exception 'authentication required';
  end if;

  select *
  into v_invite
  from public.employee_registration_invites
  where id = p_invite_id
  for update;

  if not found or v_invite.status <> 'approval_pending' then
    raise exception 'pending onboarding not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    left join public.company_approval_assignees caa
      on caa.company_id = cm.company_id
     and caa.user_id = cm.user_id
    where cm.company_id = v_invite.company_id
      and cm.user_id = v_reviewer
      and (
        cm.role::text in ('owner','admin')
        or caa.user_id is not null
      )
  ) then
    raise exception 'onboarding approval permission required';
  end if;

  if v_reviewer = v_invite.auth_user_id then
    raise exception 'employee cannot approve own onboarding';
  end if;

  insert into public.company_members(company_id, user_id, role)
  values(v_invite.company_id, v_invite.auth_user_id, 'viewer')
  on conflict(company_id, user_id) do nothing;

  update public.workers
  set user_id = v_invite.auth_user_id,
      status = 'active',
      updated_at = now()
  where id = v_invite.worker_id
    and company_id = v_invite.company_id;

  insert into public.user_profiles(user_id, display_name, phone, updated_at)
  values(
    v_invite.auth_user_id,
    v_invite.name,
    v_invite.phone_e164,
    now()
  )
  on conflict(user_id) do update
  set display_name = excluded.display_name,
      phone = excluded.phone,
      updated_at = now();

  update public.employee_registration_invites
  set status = 'approved',
      approved_by = v_reviewer,
      approved_at = now()
  where id = p_invite_id;

  update public.app_notifications
  set read_at = coalesce(read_at, now())
  where company_id = v_invite.company_id
    and action_key = 'employee_onboarding_approval'
    and action_id = p_invite_id;

  perform private.enqueue_notification(
    v_invite.company_id,
    v_invite.auth_user_id,
    'approval',
    'SKO本登録が完了しました',
    '本登録が承認されました。SKOをご利用いただけます。',
    'employee_onboarding_completed',
    p_invite_id
  );
end;
$$;

revoke execute on function public.save_employee_onboarding_profile(
  text,text,text,text,text,text,text,text,text,text
) from public, anon;
revoke execute on function public.can_review_employee_onboarding()
  from public, anon;
revoke execute on function public.pending_employee_onboarding_rows()
  from public, anon;
revoke execute on function public.approve_employee_onboarding(uuid)
  from public, anon;

grant execute on function public.save_employee_onboarding_profile(
  text,text,text,text,text,text,text,text,text,text
) to authenticated;
grant execute on function public.can_review_employee_onboarding()
  to authenticated;
grant execute on function public.pending_employee_onboarding_rows()
  to authenticated;
grant execute on function public.approve_employee_onboarding(uuid)
  to authenticated;
