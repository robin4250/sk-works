alter table public.employee_registration_invites
  add column if not exists requested_role text not null default 'viewer',
  add column if not exists requested_approval_assignee boolean not null default false,
  add column if not exists replace_approval_assignee_user_id uuid
    references auth.users(id) on delete set null;

alter table public.employee_registration_invites
  drop constraint if exists employee_registration_invites_requested_role_check;

alter table public.employee_registration_invites
  add constraint employee_registration_invites_requested_role_check
  check (requested_role in ('viewer','manager'));

alter table public.employee_registration_invites
  drop constraint if exists employee_registration_invites_requested_approver_role_check;

alter table public.employee_registration_invites
  add constraint employee_registration_invites_requested_approver_role_check
  check (
    not requested_approval_assignee
    or requested_role = 'manager'
  );

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
  v_assignee_count integer;
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

  if v_invite.requested_role not in ('viewer','manager') then
    raise exception 'invalid requested employee role';
  end if;

  if v_invite.requested_approval_assignee
     and v_invite.requested_role <> 'manager' then
    raise exception 'approval assignee must be sub-admin or above';
  end if;

  insert into public.company_members(company_id, user_id, role)
  values(
    v_invite.company_id,
    v_invite.auth_user_id,
    v_invite.requested_role
  )
  on conflict(company_id, user_id) do update
  set role = excluded.role;

  update public.workers
  set user_id = v_invite.auth_user_id,
      status = 'active',
      role = case
        when v_invite.requested_role = 'manager' then 'サブ管理者'
        else '一般ユーザー'
      end,
      updated_at = now()
  where id = v_invite.worker_id
    and company_id = v_invite.company_id;

  if v_invite.requested_approval_assignee then
    perform pg_advisory_xact_lock(
      hashtextextended(v_invite.company_id::text, 0)
    );

    select count(*)
    into v_assignee_count
    from public.company_approval_assignees
    where company_id = v_invite.company_id;

    if v_assignee_count >= 3 then
      if v_invite.replace_approval_assignee_user_id is null then
        raise exception 'approval_assignee_limit_reached';
      end if;

      if not exists (
        select 1
        from public.company_approval_assignees
        where company_id = v_invite.company_id
          and user_id = v_invite.replace_approval_assignee_user_id
      ) then
        raise exception 'approval_assignee_replacement_invalid';
      end if;

      delete from public.company_approval_assignees
      where company_id = v_invite.company_id
        and user_id = v_invite.replace_approval_assignee_user_id;
    end if;

    select count(*)
    into v_assignee_count
    from public.company_approval_assignees
    where company_id = v_invite.company_id;

    if v_assignee_count >= 3 then
      raise exception 'approval_assignee_limit_reached';
    end if;

    insert into public.company_approval_assignees(
      company_id,
      user_id,
      created_by
    )
    values(
      v_invite.company_id,
      v_invite.auth_user_id,
      v_reviewer
    )
    on conflict(company_id, user_id) do nothing;
  end if;

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
    case
      when v_invite.requested_role = 'manager'
        and v_invite.requested_approval_assignee
        then 'サブ管理者・承認担当者として本登録されました。SKOをご利用いただけます。'
      when v_invite.requested_role = 'manager'
        then 'サブ管理者として本登録されました。SKOをご利用いただけます。'
      else '本登録が承認されました。SKOをご利用いただけます。'
    end,
    'employee_onboarding_completed',
    p_invite_id
  );
end;
$$;

revoke execute on function public.approve_employee_onboarding(uuid)
  from public, anon;
grant execute on function public.approve_employee_onboarding(uuid)
  to authenticated;


create or replace function public.pending_employee_onboarding_review_rows()
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
  submitted_at timestamptz,
  requested_role text,
  requested_approval_assignee boolean,
  replace_approval_assignee_user_id uuid,
  replace_approval_assignee_name text
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
    eri.submitted_at,
    eri.requested_role,
    eri.requested_approval_assignee,
    eri.replace_approval_assignee_user_id,
    coalesce(replacement_profile.display_name, replacement_member.role::text)
  from public.employee_registration_invites eri
  left join public.user_profiles replacement_profile
    on replacement_profile.user_id = eri.replace_approval_assignee_user_id
  left join public.company_members replacement_member
    on replacement_member.company_id = eri.company_id
   and replacement_member.user_id = eri.replace_approval_assignee_user_id
  where eri.company_id = v_company_id
    and eri.status = 'approval_pending'
  order by eri.submitted_at nulls last, eri.created_at;
end;
$$;

revoke execute on function public.pending_employee_onboarding_review_rows()
  from public, anon;
grant execute on function public.pending_employee_onboarding_review_rows()
  to authenticated;
