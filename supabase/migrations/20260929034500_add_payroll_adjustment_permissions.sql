alter table public.member_feature_permissions
  add column if not exists can_view_payroll_adjustments boolean not null default false,
  add column if not exists can_manage_payroll_adjustments boolean not null default false;

create table if not exists public.payroll_adjustment_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  page_label text not null default '給与調整',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint payroll_adjustment_settings_page_label_check
    check (char_length(trim(page_label)) between 1 and 40)
);

create table if not exists public.payroll_adjustment_types (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  label text not null,
  direction text not null,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_adjustment_types_label_check
    check (char_length(trim(label)) between 1 and 60),
  constraint payroll_adjustment_types_direction_check
    check (direction in ('addition','deduction'))
);

create unique index if not exists payroll_adjustment_types_company_label_direction_uidx
  on public.payroll_adjustment_types(company_id, lower(trim(label)), direction);

create table if not exists public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete restrict,
  type_id uuid references public.payroll_adjustment_types(id) on delete set null,
  label_snapshot text not null,
  direction text not null,
  amount_yen integer not null,
  effective_date date not null,
  note text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  constraint payroll_adjustments_label_check
    check (char_length(trim(label_snapshot)) between 1 and 60),
  constraint payroll_adjustments_direction_check
    check (direction in ('addition','deduction')),
  constraint payroll_adjustments_amount_check
    check (amount_yen > 0),
  constraint payroll_adjustments_cancel_fields_check
    check (
      (cancelled_at is null and cancelled_by is null)
      or (cancelled_at is not null and cancelled_by is not null)
    )
);

create index if not exists payroll_adjustments_company_date_idx
  on public.payroll_adjustments(company_id, effective_date desc);
create index if not exists payroll_adjustments_worker_date_idx
  on public.payroll_adjustments(worker_id, effective_date desc);
create index if not exists payroll_adjustments_type_idx
  on public.payroll_adjustments(type_id);

create table if not exists public.payroll_adjustment_audit_log (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  action text not null,
  target_kind text not null,
  target_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists payroll_adjustment_audit_company_created_idx
  on public.payroll_adjustment_audit_log(company_id, created_at desc);

alter table public.payroll_adjustment_settings enable row level security;
alter table public.payroll_adjustment_types enable row level security;
alter table public.payroll_adjustments enable row level security;
alter table public.payroll_adjustment_audit_log enable row level security;

create or replace function public.current_feature_permissions()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_perm public.member_feature_permissions%rowtype;
  v_is_approval_assignee boolean := false;
begin
  if v_user_id is null then
    return '{}'::jsonb;
  end if;

  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    return '{}'::jsonb;
  end if;

  select exists (
    select 1
    from public.company_approval_assignees caa
    where caa.company_id = v_company_id
      and caa.user_id = v_user_id
  )
  into v_is_approval_assignee;

  if v_role in ('owner','admin') then
    return jsonb_build_object(
      'can_approve_daily_report_edits', v_is_approval_assignee,
      'can_manage_attendance', true,
      'can_manage_people', true,
      'can_view_invoices', true,
      'can_manage_invoices', true,
      'can_view_admin_site_data', true,
      'can_manage_admin_site_data', true,
      'can_manage_payroll', true,
      'can_manage_partner_chat', true,
      'can_view_payroll_adjustments', true,
      'can_manage_payroll_adjustments', true
    );
  end if;

  select *
  into v_perm
  from public.member_feature_permissions
  where company_id = v_company_id
    and user_id = v_user_id;

  if found then
    return jsonb_build_object(
      'can_approve_daily_report_edits', v_is_approval_assignee,
      'can_manage_attendance', coalesce(v_perm.can_manage_attendance, false),
      'can_manage_people', coalesce(v_perm.can_manage_people, false),
      'can_view_invoices', false,
      'can_manage_invoices', false,
      'can_view_admin_site_data', false,
      'can_manage_admin_site_data', false,
      'can_manage_payroll', false,
      'can_manage_partner_chat', coalesce(v_perm.can_manage_partner_chat, false),
      'can_view_payroll_adjustments',
        coalesce(v_perm.can_view_payroll_adjustments, false)
        or coalesce(v_perm.can_manage_payroll_adjustments, false),
      'can_manage_payroll_adjustments',
        case when v_role = 'manager'
          then coalesce(v_perm.can_manage_payroll_adjustments, false)
          else false
        end
    );
  end if;

  return jsonb_build_object(
    'can_approve_daily_report_edits', v_is_approval_assignee,
    'can_manage_attendance', v_role = 'manager',
    'can_manage_people', false,
    'can_view_invoices', false,
    'can_manage_invoices', false,
    'can_view_admin_site_data', false,
    'can_manage_admin_site_data', false,
    'can_manage_payroll', false,
    'can_manage_partner_chat', false,
    'can_view_payroll_adjustments', false,
    'can_manage_payroll_adjustments', false
  );
end;
$$;

drop function if exists public.company_member_permission_rows();

create function public.company_member_permission_rows()
returns table(
  user_id uuid,
  display_name text,
  role text,
  can_approve_daily_report_edits boolean,
  can_manage_attendance boolean,
  can_manage_people boolean,
  can_view_invoices boolean,
  can_manage_invoices boolean,
  can_view_admin_site_data boolean,
  can_manage_admin_site_data boolean,
  can_manage_payroll boolean,
  can_manage_partner_chat boolean,
  can_view_payroll_adjustments boolean,
  can_manage_payroll_adjustments boolean
)
language sql
security definer
set search_path = public, pg_temp
as $$
  with my_company as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
    limit 1
  )
  select
    cm.user_id,
    coalesce(up.display_name, 'SKOユーザー') as display_name,
    cm.role::text,
    exists (
      select 1
      from public.company_approval_assignees caa
      where caa.company_id = cm.company_id
        and caa.user_id = cm.user_id
    ) as can_approve_daily_report_edits,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_attendance, cm.role::text = 'manager') end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_people, false) end,
    cm.role::text in ('owner','admin') as can_view_invoices,
    cm.role::text in ('owner','admin') as can_manage_invoices,
    cm.role::text in ('owner','admin') as can_view_admin_site_data,
    cm.role::text in ('owner','admin') as can_manage_admin_site_data,
    cm.role::text in ('owner','admin') as can_manage_payroll,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_manage_partner_chat, false) end,
    case when cm.role::text in ('owner','admin') then true
         else coalesce(p.can_view_payroll_adjustments, false)
           or coalesce(p.can_manage_payroll_adjustments, false) end,
    case when cm.role::text in ('owner','admin') then true
         when cm.role::text = 'manager'
           then coalesce(p.can_manage_payroll_adjustments, false)
         else false end
  from public.company_members cm
  join my_company mc on mc.company_id = cm.company_id
  left join public.user_profiles up on up.user_id = cm.user_id
  left join public.member_feature_permissions p
    on p.company_id = cm.company_id
   and p.user_id = cm.user_id
  order by display_name;
$$;

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
  v_can_manage_attendance boolean;
  v_can_manage_people boolean;
  v_can_manage_partner_chat boolean;
  v_can_view_payroll_adjustments boolean;
  v_can_manage_payroll_adjustments boolean;
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

    insert into public.payroll_adjustment_audit_log(
      company_id, action, target_kind, target_id, actor_user_id, details
    )
    values(
      v_company_id,
      'permission_change',
      'user',
      p_user_id,
      v_actor,
      jsonb_build_object(
        'role', p_role,
        'can_view_payroll_adjustments', true,
        'can_manage_payroll_adjustments', true
      )
    );
    return;
  end if;

  v_can_manage_attendance :=
    coalesce((p_permissions ->> 'can_manage_attendance')::boolean, false);
  v_can_manage_people :=
    coalesce((p_permissions ->> 'can_manage_people')::boolean, false);
  v_can_manage_partner_chat :=
    coalesce((p_permissions ->> 'can_manage_partner_chat')::boolean, false);
  v_can_view_payroll_adjustments :=
    coalesce((p_permissions ->> 'can_view_payroll_adjustments')::boolean, false);
  v_can_manage_payroll_adjustments :=
    p_role = 'manager'
    and coalesce(
      (p_permissions ->> 'can_manage_payroll_adjustments')::boolean,
      false
    );

  if v_can_manage_payroll_adjustments then
    v_can_view_payroll_adjustments := true;
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
    can_view_payroll_adjustments,
    can_manage_payroll_adjustments,
    updated_by,
    updated_at
  )
  values(
    v_company_id,
    p_user_id,
    false,
    v_can_manage_attendance,
    v_can_manage_people,
    false,
    false,
    false,
    false,
    false,
    v_can_manage_partner_chat,
    v_can_view_payroll_adjustments,
    v_can_manage_payroll_adjustments,
    v_actor,
    now()
  )
  on conflict(company_id,user_id) do update
  set can_approve_daily_report_edits = false,
      can_manage_attendance = excluded.can_manage_attendance,
      can_manage_people = excluded.can_manage_people,
      can_view_invoices = false,
      can_manage_invoices = false,
      can_view_admin_site_data = false,
      can_manage_admin_site_data = false,
      can_manage_payroll = false,
      can_manage_partner_chat = excluded.can_manage_partner_chat,
      can_view_payroll_adjustments = excluded.can_view_payroll_adjustments,
      can_manage_payroll_adjustments = excluded.can_manage_payroll_adjustments,
      updated_by = v_actor,
      updated_at = now();

  insert into public.payroll_adjustment_audit_log(
    company_id, action, target_kind, target_id, actor_user_id, details
  )
  values(
    v_company_id,
    'permission_change',
    'user',
    p_user_id,
    v_actor,
    jsonb_build_object(
      'role', p_role,
      'can_view_payroll_adjustments', v_can_view_payroll_adjustments,
      'can_manage_payroll_adjustments', v_can_manage_payroll_adjustments
    )
  );
end;
$$;

drop policy if exists "company members can read payroll adjustment settings"
  on public.payroll_adjustment_settings;
create policy "company members can read payroll adjustment settings"
on public.payroll_adjustment_settings
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payroll_adjustment_settings.company_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "authorized users can read payroll adjustment types"
  on public.payroll_adjustment_types;
create policy "authorized users can read payroll adjustment types"
on public.payroll_adjustment_types
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    left join public.member_feature_permissions p
      on p.company_id = cm.company_id
     and p.user_id = cm.user_id
    where cm.company_id = payroll_adjustment_types.company_id
      and cm.user_id = auth.uid()
      and (
        cm.role::text in ('owner','admin')
        or coalesce(p.can_view_payroll_adjustments, false)
        or coalesce(p.can_manage_payroll_adjustments, false)
      )
  )
);

drop policy if exists "authorized users can read payroll adjustments"
  on public.payroll_adjustments;
create policy "authorized users can read payroll adjustments"
on public.payroll_adjustments
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    left join public.member_feature_permissions p
      on p.company_id = cm.company_id
     and p.user_id = cm.user_id
    where cm.company_id = payroll_adjustments.company_id
      and cm.user_id = auth.uid()
      and (
        cm.role::text in ('owner','admin')
        or coalesce(p.can_view_payroll_adjustments, false)
        or coalesce(p.can_manage_payroll_adjustments, false)
      )
  )
);

drop policy if exists "admins can read payroll adjustment audit"
  on public.payroll_adjustment_audit_log;
create policy "admins can read payroll adjustment audit"
on public.payroll_adjustment_audit_log
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payroll_adjustment_audit_log.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

create or replace function public.set_payroll_adjustment_page_label(
  p_label text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_label text := trim(coalesce(p_label, ''));
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

  if char_length(v_label) < 1 or char_length(v_label) > 40 then
    raise exception 'page label must be 1 to 40 characters';
  end if;

  insert into public.payroll_adjustment_settings(
    company_id, page_label, updated_by, updated_at
  )
  values(v_company_id, v_label, v_actor, now())
  on conflict(company_id) do update
  set page_label = excluded.page_label,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;

  insert into public.payroll_adjustment_audit_log(
    company_id, action, target_kind, actor_user_id, details
  )
  values(
    v_company_id,
    'page_label_change',
    'settings',
    v_actor,
    jsonb_build_object('page_label', v_label)
  );
end;
$$;

revoke execute on function public.current_feature_permissions() from public, anon;
revoke execute on function public.company_member_permission_rows() from public, anon;
revoke execute on function public.set_member_feature_permissions(uuid,text,jsonb)
  from public, anon;
revoke execute on function public.set_payroll_adjustment_page_label(text)
  from public, anon;

grant execute on function public.current_feature_permissions() to authenticated;
grant execute on function public.company_member_permission_rows() to authenticated;
grant execute on function public.set_member_feature_permissions(uuid,text,jsonb)
  to authenticated;
grant execute on function public.set_payroll_adjustment_page_label(text)
  to authenticated;
