create table if not exists public.company_approval_assignees (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (company_id, user_id)
);

alter table public.company_approval_assignees enable row level security;

revoke all on public.company_approval_assignees from anon;
revoke insert, update, delete on public.company_approval_assignees from authenticated;
revoke select on public.company_approval_assignees from authenticated;

-- Existing companies begin with their protected owner as the initial approver.
insert into public.company_approval_assignees(company_id, user_id, created_by)
select cm.company_id, cm.user_id, cm.user_id
from public.company_members cm
where cm.role::text = 'owner'
  and not exists (
    select 1
    from public.company_approval_assignees caa
    where caa.company_id = cm.company_id
  )
on conflict do nothing;

alter table public.daily_report_edit_requests
  alter column approvals_required set default 1;

update public.daily_report_edit_requests
set approvals_required = 1
where status = 'pending'
  and approvals_required <> 1;

alter table public.daily_report_edit_requests
  drop constraint if exists daily_report_edit_requests_approvals_required_check;

alter table public.daily_report_edit_requests
  add constraint daily_report_edit_requests_approvals_required_check
  check (approvals_required between 1 and 3);

create or replace function public.company_approval_assignee_rows()
returns table(
  user_id uuid,
  display_name text,
  role text,
  is_assignee boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  return query
  select
    cm.user_id,
    coalesce(up.display_name, 'SKOユーザー')::text,
    cm.role::text,
    (caa.user_id is not null)
  from public.company_members cm
  left join public.user_profiles up on up.user_id = cm.user_id
  left join public.company_approval_assignees caa
    on caa.company_id = cm.company_id
   and caa.user_id = cm.user_id
  where cm.company_id = v_company_id
    and cm.role::text in ('owner','admin','manager')
  order by
    (caa.user_id is not null) desc,
    coalesce(up.display_name, 'SKOユーザー');
end;
$$;

create or replace function public.set_company_approval_assignee(
  p_user_id uuid,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_target_role text;
  v_count integer;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  select cm.role::text
  into v_target_role
  from public.company_members cm
  where cm.company_id = v_company_id
    and cm.user_id = p_user_id
  limit 1;

  if v_target_role is null then
    raise exception 'target user is not in company';
  end if;

  if p_enabled and v_target_role not in ('owner','admin','manager') then
    raise exception 'approval assignee must be sub-admin or above';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_company_id::text, 0));

  select count(*)
  into v_count
  from public.company_approval_assignees
  where company_id = v_company_id;

  if p_enabled then
    if exists (
      select 1 from public.company_approval_assignees
      where company_id = v_company_id and user_id = p_user_id
    ) then
      return;
    end if;

    if v_count >= 3 then
      raise exception 'approval_assignee_limit_reached';
    end if;

    insert into public.company_approval_assignees(
      company_id, user_id, created_by
    )
    values(v_company_id, p_user_id, v_actor);
    return;
  end if;

  if not exists (
    select 1 from public.company_approval_assignees
    where company_id = v_company_id and user_id = p_user_id
  ) then
    return;
  end if;

  if v_count <= 1 then
    raise exception 'at_least_one_approval_assignee_required';
  end if;

  delete from public.company_approval_assignees
  where company_id = v_company_id
    and user_id = p_user_id;
end;
$$;

-- Keep the owner role protected while preventing a selected approver
-- from being downgraded to a normal user without first moving approval duty.
create or replace function public.set_member_feature_permissions(
  p_user_id uuid,
  p_role text,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_target_role text;
  v_assignee_count integer;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  select cm.role::text
  into v_target_role
  from public.company_members cm
  where cm.company_id = v_company_id
    and cm.user_id = p_user_id
  limit 1;

  if v_target_role is null then
    raise exception 'target user is not in company';
  end if;

  if v_target_role = 'owner' then
    raise exception 'owner role cannot be changed';
  end if;

  if p_role not in ('admin','manager','viewer') then
    raise exception 'invalid role';
  end if;

  if p_role = 'viewer' and exists (
    select 1 from public.company_approval_assignees
    where company_id = v_company_id
      and user_id = p_user_id
  ) then
    select count(*) into v_assignee_count
    from public.company_approval_assignees
    where company_id = v_company_id;

    if v_assignee_count <= 1 then
      raise exception 'remove approval duty after assigning another approver';
    end if;

    delete from public.company_approval_assignees
    where company_id = v_company_id
      and user_id = p_user_id;
  end if;

  update public.company_members
  set role = p_role
  where company_id = v_company_id
    and user_id = p_user_id;

  if p_role = 'admin' then
    delete from public.member_feature_permissions
    where company_id = v_company_id
      and user_id = p_user_id;
    return;
  end if;

  insert into public.member_feature_permissions(
    company_id,
    user_id,
    can_approve_daily_report_edits,
    can_manage_attendance,
    can_manage_people,
    can_view_invoices,
    can_manage_invoices,
    can_view_admin_site_data,
    can_manage_admin_site_data,
    can_manage_payroll,
    can_manage_partner_chat,
    updated_by,
    updated_at
  )
  values(
    v_company_id,
    p_user_id,
    coalesce((p_permissions ->> 'can_approve_daily_report_edits')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_attendance')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_people')::boolean, false),
    coalesce((p_permissions ->> 'can_view_invoices')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_invoices')::boolean, false),
    coalesce((p_permissions ->> 'can_view_admin_site_data')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_admin_site_data')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_payroll')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_partner_chat')::boolean, false),
    v_actor,
    now()
  )
  on conflict(company_id, user_id) do update
  set can_approve_daily_report_edits = excluded.can_approve_daily_report_edits,
      can_manage_attendance = excluded.can_manage_attendance,
      can_manage_people = excluded.can_manage_people,
      can_view_invoices = excluded.can_view_invoices,
      can_manage_invoices = excluded.can_manage_invoices,
      can_view_admin_site_data = excluded.can_view_admin_site_data,
      can_manage_admin_site_data = excluded.can_manage_admin_site_data,
      can_manage_payroll = excluded.can_manage_payroll,
      can_manage_partner_chat = excluded.can_manage_partner_chat,
      updated_by = v_actor,
      updated_at = now();
end;
$$;

create or replace function public.request_daily_report_edit(
  p_report_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_request_id uuid;
  v_approver record;
  v_count integer;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select dr.company_id
  into v_company_id
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id = dr.company_id
   and cm.user_id = v_user_id
  where dr.id = p_report_id
    and dr.status = 'signed';

  if v_company_id is null then
    raise exception 'signed daily report not found';
  end if;

  select count(*) into v_count
  from public.company_approval_assignees
  where company_id = v_company_id;

  if v_count < 1 or v_count > 3 then
    raise exception 'company approval assignee configuration is invalid';
  end if;

  insert into public.daily_report_edit_requests(
    report_id, company_id, requested_by, reason, approvals_required
  )
  values(
    p_report_id, v_company_id, v_user_id,
    nullif(trim(coalesce(p_reason, '')), ''),
    1
  )
  returning id into v_request_id;

  for v_approver in
    select caa.user_id
    from public.company_approval_assignees caa
    where caa.company_id = v_company_id
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_approver.user_id,
      'approval',
      '日報の修正承認',
      '確定済み日報の修正申請があります。',
      'daily_report_edit_request',
      v_request_id
    );
  end loop;

  return v_request_id;
end;
$$;

create or replace function public.decide_daily_report_edit(
  p_request_id uuid,
  p_decision text
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_requested_by uuid;
  v_status text;
  v_assignee_count integer;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select req.company_id, req.requested_by, req.status
  into v_company_id, v_requested_by, v_status
  from public.daily_report_edit_requests req
  where req.id = p_request_id
  for update;

  if v_company_id is null or v_status <> 'pending' then
    raise exception 'pending request not found';
  end if;

  if not exists (
    select 1
    from public.company_approval_assignees caa
    where caa.company_id = v_company_id
      and caa.user_id = v_user_id
  ) then
    raise exception 'approval assignee permission required';
  end if;

  select count(*) into v_assignee_count
  from public.company_approval_assignees
  where company_id = v_company_id;

  -- Multi-person companies keep separation of requester/approver.
  -- A sole proprietor may self-approve only when they are the company's
  -- single configured approval assignee.
  if v_requested_by = v_user_id and v_assignee_count > 1 then
    raise exception 'requester cannot approve own request';
  end if;

  insert into public.daily_report_edit_approvals(
    request_id,
    approver_user_id,
    decision
  )
  values(
    p_request_id,
    v_user_id,
    p_decision
  )
  on conflict(request_id, approver_user_id) do update
  set decision = excluded.decision,
      decided_at = now();

  if p_decision = 'reject' then
    update public.daily_report_edit_requests
    set status = 'rejected',
        resolved_at = now()
    where id = p_request_id;

    perform private.enqueue_notification(
      v_company_id,
      v_requested_by,
      'warning',
      '日報修正申請が却下されました',
      '確定済み日報の修正申請が却下されました。',
      'daily_report_edit_request',
      p_request_id
    );
    return 'rejected';
  end if;

  update public.daily_report_edit_requests
  set status = 'approved',
      resolved_at = now(),
      approvals_required = 1
  where id = p_request_id;

  perform private.enqueue_notification(
    v_company_id,
    v_requested_by,
    'approval',
    '日報を編集できます',
    '設定された承認担当者の承認が完了しました。日報を開いて編集してください。',
    'daily_report_edit_request',
    p_request_id
  );

  return 'approved';
end;
$$;

-- New companies automatically start with their owner as the single approver.
create or replace function public.create_company(company_name text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  new_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(company_name), '') is null then
    raise exception 'Company name is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  if exists (
    select 1
    from public.company_members cm
    where cm.user_id = v_user_id
  ) then
    raise exception 'User already belongs to a company';
  end if;

  insert into public.companies(name)
  values (trim(company_name))
  returning id into new_company_id;

  insert into public.company_members(company_id, user_id, role)
  values (new_company_id, v_user_id, 'owner');

  insert into public.company_approval_assignees(
    company_id, user_id, created_by
  )
  values(new_company_id, v_user_id, v_user_id);

  return new_company_id;
end;
$$;

revoke execute on function public.company_approval_assignee_rows() from public, anon;
revoke execute on function public.set_company_approval_assignee(uuid, boolean) from public, anon;
grant execute on function public.company_approval_assignee_rows() to authenticated;
grant execute on function public.set_company_approval_assignee(uuid, boolean) to authenticated;
